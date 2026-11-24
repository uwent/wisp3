<script lang="ts">
  import { untrack } from 'svelte'
  import { Form, Link, page } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import { type SystemShape, systemName } from '@/lib/geo'
  import { type Boundary, boundaryAcres, boundaryCenter, boundaryErrors } from '@/lib/boundary'
  import OutlineMap, { type DrawMode } from '@/lib/outlines/OutlineMap.svelte'
  import { forgetKept, keepShapes, readKept } from '@/lib/outlines/kept'
  import type { PickerShape } from '@/lib/outlines/picker'
  import { ACCEPT, readOutlineFileResult, shapeNotes } from '@/lib/outlines/read'
  import ShapePicker from '@/lib/outlines/ShapePicker.svelte'
  import {
    formatReach,
    reachLine,
    systemDistanceM,
    systemReach,
    systemsNear,
    touchesSystem,
  } from '@/lib/outlines/problems'
  import type { Reference } from '@/lib/outlines/references'
  import FieldAreaInput from '@/lib/setup/FieldAreaInput.svelte'
  import FieldSoilInput from '@/lib/setup/FieldSoilInput.svelte'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { currentUnits } from '@/lib/units'
  import { fieldOutlines, fields, newOutlineImport, setup } from '@/routes'
  import type { Field, SoilType } from '@/types/serializers'

  type System = SystemShape & { id: number; name: string; kind_name: string; weather_cell_id: number | null }

  // A field's outline, called its shape on the page: drawn or read from a
  // file; its acres are offered for the field's area and the soil survey under it labels the soil
  // menu, with the field dialog's own inputs. For the map and suggestions only: the
  // balance doesn't use it.
  let {
    field,
    system,
    cell,
    open_years,
    other_systems,
    other_fields,
    soil_types,
    from,
  }: {
    field: Field
    system: System
    cell: { north: number; south: number; west: number; east: number }
    open_years: number[]
    other_systems: System[]
    other_fields: { id: number; name: string; boundary: Boundary }[]
    soil_types: SoilType[]
    from: 'setup' | 'field'
  } = $props()

  const units = $derived(currentUnits())

  let boundary = $state<Boundary | null>(untrack(() => field.boundary))
  let mode = $state<DrawMode>('view')
  let map = $state<OutlineMap>()
  // The tools wait for the map and its drawing tools to load
  let ready = $state(false)

  const acres = $derived(boundary ? boundaryAcres(boundary) : null)
  const problems = $derived(boundary ? boundaryErrors(boundary) : [])

  let area = $state<number | null>(untrack(() => field.area_acres))
  let soilTypeId = $state(untrack(() => String(field.soil_type_id)))

  // A shape away from its system: kept there (a traveler's location is often rough),
  // or the field moved with the save to another system within half a mile, or to a new Location at
  // it. All of it reads the shape as it was when the map last left drawing or editing: a shape being
  // drawn or edited changes with every move of the pointer, so the distances and the soil survey are
  // worked out once, on Done editing (or an import or Remove), not as it moves
  let settled = $state<Boundary | null>(untrack(() => field.boundary))
  $effect(() => {
    if (mode === 'view') settled = boundary
  })
  const settledProblems = $derived(settled ? boundaryErrors(settled) : [])
  const away = $derived(settled !== null && !settledProblems.length && !touchesSystem(settled, system))
  const nearby = $derived(settled && away ? systemsNear(settled, other_systems) : [])
  const ownMeters = $derived(settled && away ? systemDistanceM(settled, system) : 0)
  let systemChoice = $state('keep')
  const moveTo = $derived(nearby.find(({ system }) => `system-${system.id}` === systemChoice)?.system)
  const howFar = (system: System, meters: number) => systemReach(system, meters, units.system)
  const toLocation = $derived(away && systemChoice === 'location')
  const location = $derived(settled && toLocation ? boundaryCenter(settled) : null)
  // Whether the move changes the weather its open seasons use: another cell's system, or a
  // Location outside this system's cell
  const newWeather = $derived(
    moveTo
      ? moveTo.weather_cell_id !== system.weather_cell_id
      : location
        ? location[1] > cell.north || location[1] <= cell.south || location[0] < cell.west || location[0] >= cell.east
        : false,
  )
  const seasons = $derived(
    open_years.length === 1
      ? `Its ${open_years[0]} season`
      : `Its ${open_years.slice(0, -1).join(', ')} and ${open_years.at(-1)} seasons`,
  )
  // The line to the system chosen (its own, or one switched to), drawn while they don't touch and
  // the shape isn't being drawn or edited (not for a new system, which is made at the shape)
  const target = $derived(toLocation ? null : (moveTo ?? system))
  const reach = $derived(
    settled && away && target && mode === 'view' && !touchesSystem(settled, target) ? reachLine(settled, target) : null,
  )
  const arrow = $derived(
    reach && target && { ...reach, label: `${systemName(target)} · ${formatReach(reach.meters, units.system)}` },
  )

  // The map shows the field's own system first, then the others and the other fields' outlines
  const references = $derived<Reference[]>([
    { name: systemName(system), shape: system },
    ...other_systems.map((other) => ({ name: other.name, shape: other })),
    ...other_fields.map((other) => ({ name: other.name, boundary: other.boundary })),
  ])

  // Unsaved changes
  const initial = untrack(() => JSON.stringify(field.boundary))
  let saved = $state(false)

  const changed = $derived(
    JSON.stringify(boundary) !== initial ||
      soilTypeId !== String(field.soil_type_id) ||
      area !== field.area_acres ||
      (away && systemChoice !== 'keep'),
  )
  confirmUnsavedChanges(() => !saved && changed)

  function removeOutline() {
    boundary = null
    mode = 'view'
    fileNote = null
  }

  // Drawing over an outline replaces it once the new one is finished, so ask first
  function startDraw() {
    if (boundary && !confirm('Draw a new shape? It replaces this one once you finish it.')) return
    mode = 'draw'
    fileNote = null
  }

  // The server's errors arrive as a string or a list
  const listed = (error: string | string[] | undefined) => (error === undefined ? [] : [error].flat())

  // A file: one shape is used; several are listed to pick one, and kept in the browser for a week so the
  // operation's other fields can be outlined from them without reading the file again (offered
  // when the page opens; lib/outlines/kept.ts)
  const groupId = page.props.auth.group?.id ?? null
  let fileInput = $state<HTMLInputElement>()
  let reading = $state(false)
  let fileError = $state<string | null>(null)
  // What reading the file changed in the shape used ("Kept the largest of 3 parts")
  let fileNote = $state<string | null>(null)
  type Choices = {
    fileName: string
    shapes: PickerShape[]
    nameKey: string | null
    skipped: number
    /** When kept shapes were read; null for a file read on this page */
    savedAt: number | null
  }
  let choices = $state<Choices | null>(readKept(groupId))
  // Kept shapes start open for a field without a shape
  let choicesOpen = $state(untrack(() => !field.boundary))

  async function readFile(event: Event) {
    const input = event.currentTarget as HTMLInputElement
    const file = input.files?.[0]
    input.value = ''
    if (!file) return
    reading = true
    fileError = null
    const read = await readOutlineFileResult(file)
    reading = false
    if ('error' in read) return (fileError = read.error)
    const { result } = read
    const usable = result.shapes.filter((shape) => !shape.problems.length)
    if (result.shapes.length === 1 && usable.length === 1) return useShape(usable[0])
    keepShapes(groupId, { fileName: file.name, ...result })
    choices = { fileName: file.name, ...result, savedAt: null }
    choicesOpen = true
  }

  // Shapes kept from earlier open again; otherwise a file is chosen
  function importFromFile() {
    if (choices && !choicesOpen) choicesOpen = true
    else fileInput?.click()
  }

  // A shape picked shows on the map, the list staying open to try another. Below the card on a small
  // screen, the map is brought into view.
  let mapBox = $state<HTMLElement>()
  function useShape(shape: PickerShape) {
    if (!shape.boundary) return
    boundary = shape.boundary
    mode = 'view'
    fileNote = shapeNotes(shape) || null
    if (matchMedia('(min-width: 64rem)').matches) return
    const still = matchMedia('(prefers-reduced-motion: reduce)').matches
    mapBox?.scrollIntoView({ behavior: still ? 'auto' : 'smooth', block: 'start' })
  }

  function forgetShapes() {
    forgetKept(groupId)
    choices = null
  }

  // What the list matches the shapes against: the field (its name, system and saved shape) and the
  // other fields' shapes
  const pickerContext = $derived({
    field: { id: field.id, name: field.name, system_id: field.system_id, boundary: field.boundary },
    system: system,
    otherFields: other_fields,
  })

  const backHref = $derived(from === 'setup' ? setup.show().url : fields.show(field.id).url)
  const MODE_HINTS: Record<DrawMode, string> = {
    view: '',
    draw: 'Click the map at each corner of the field. The shape turns orange while its edges cross.',
    edit: 'Drag inside the shape to move it, drag a corner to move it, drag a midpoint to add a corner, or right-click a corner to remove it. The saved shape stays dashed until the page is saved.',
  }
</script>

<svelte:head><title>Field shape: {field.name} · WISP</title></svelte:head>

<div class="space-y-1">
  <Link href={backHref} class="text-sm text-brand-600 hover:underline">← {from === 'setup' ? 'Setup' : field.name}</Link
  >
  <h1 class="text-2xl font-semibold">Field shape: {field.name}</h1>
  <p class="text-sm text-ink-muted">
    Irrigation system: {systemName(system)}. The shape draws the field on the map and measures its area, and the soil
    survey under it suggests its soil; the water balance doesn't use the shape itself.
  </p>
</div>

<div class="space-y-3">
  <!-- The tools wait for the map, and for the shape being drawn or edited to be saved or canceled on it -->
  <fieldset class="flex flex-wrap items-center gap-2" disabled={!ready || mode !== 'view'} aria-label="Shape tools">
    {#if !boundary}
      <Button type="button" variant="secondary" onclick={startDraw}>Draw the shape</Button>
    {:else}
      <Button type="button" variant="secondary" onclick={() => (mode = 'edit')}>Edit corners</Button>
      <Button type="button" variant="secondary" onclick={startDraw}>Draw a new one</Button>
    {/if}
    <Button type="button" variant="ghost" disabled={reading} onclick={importFromFile}
      >{reading ? 'Reading…' : 'Import from a file'}</Button
    >
    {#if boundary}
      <Button type="button" variant="danger-ghost" onclick={removeOutline}>Remove the shape</Button>
    {/if}
    <input
      bind:this={fileInput}
      type="file"
      accept={ACCEPT}
      class="sr-only"
      tabindex="-1"
      aria-label="Shape file"
      onchange={readFile}
    />
  </fieldset>
  {#if MODE_HINTS[mode]}
    <p class="text-sm text-ink-muted" aria-live="polite">{MODE_HINTS[mode]}</p>
  {:else if fileNote}
    <p class="text-sm text-ink-muted">From the file: {fileNote}. A field's shape is one piece without holes.</p>
  {/if}
  {#if fileError}
    <p class="text-sm text-status-irrigate-ink" role="alert">{fileError}</p>
  {/if}
  <!-- A file's shapes in a card beside the map (stacked on small screens), the map as tall as the card -->
  <div class="grid gap-4 {choices && choicesOpen ? 'lg:grid-cols-2' : ''}">
    {#if choices && choicesOpen}
      {#key choices}
        <ShapePicker
          shapes={choices.shapes}
          fileName={choices.fileName}
          bind:nameKey={choices.nameKey}
          savedAt={choices.savedAt}
          skipped={choices.skipped}
          context={pickerContext}
          systemLabel={systemName(system)}
          current={boundary}
          onpick={useShape}
          onclose={() => (choicesOpen = false)}
          onchoose={() => fileInput?.click()}
          onforget={forgetShapes}
        >
          To give several fields their shapes at once, use <Link
            href={newOutlineImport()}
            class="text-brand-600 underline underline-offset-2">Import field shapes in Setup</Link
          >.
        </ShapePicker>
      {/key}
    {/if}
    <div bind:this={mapBox} class="h-128 scroll-mt-4 {choices && choicesOpen ? 'lg:h-auto lg:min-h-128' : ''}">
      <OutlineMap
        bind:this={map}
        bind:boundary
        bind:mode
        bind:ready
        saved={field.boundary}
        {references}
        {arrow}
        soilTypes={soil_types}
        fill
      />
    </div>
  </div>
</div>

<Form
  action={fieldOutlines.update(field.id, { query: from === 'setup' ? { from } : {} })}
  class="space-y-4"
  onSuccess={() => (saved = true)}
>
  {#snippet children({ errors, processing })}
    <input type="hidden" name="outline[boundary]" value={boundary ? JSON.stringify(boundary) : ''} />

    {#if problems.length || errors.boundary}
      <div class="rounded-md border border-status-irrigate px-3 py-2 text-sm" role="alert">
        The shape {(errors.boundary ? listed(errors.boundary) : problems).join('; ')}.
      </div>
    {/if}

    {#if away && mode === 'view'}
      <section class="space-y-3 rounded-lg border border-status-caution/60 bg-status-caution/10 p-4 text-sm">
        <p>
          This field is {formatReach(ownMeters, units.system)} away from its assigned irrigation system, {systemName(
            system,
          )}. All fields must have an assigned irrigation system, and a field's weather and irrigation inputs come from
          its system. You can keep the existing system for now, switch to another nearby system, or create a new system
          from the menu below.
        </p>
        <SelectField
          label="Irrigation system for {field.name}"
          bind:value={systemChoice}
          options={[
            {
              value: 'keep',
              label: `Keep with ${systemName(system)} – ${howFar(system, ownMeters)}`,
            },
            ...nearby.map(({ system, meters }) => ({
              value: `system-${system.id}`,
              label: `Switch to ${systemName(system)} – ${howFar(system, meters)}`,
            })),
            { value: 'location', label: 'Create a new system' },
          ]}
          error={errors.system_id}
          hint={toLocation
            ? `This will create a new location-only system named ${field.name} at the center of this field when you save your changes. You will need to configure this system later in Setup.`
            : undefined}
        />
        {#if moveTo}
          <input type="hidden" name="outline[system_id]" value={moveTo.id} />
        {:else if location}
          <input type="hidden" name="outline[new_location]" value="1" />
          <input type="hidden" name="outline[longitude]" value={location[0].toFixed(6)} />
          <input type="hidden" name="outline[latitude]" value={location[1].toFixed(6)} />
        {/if}
        {#if newWeather && open_years.length}
          <p class="text-ink-muted">
            {seasons} will use {moveTo ? `${systemName(moveTo)}'s` : "this location's"} weather{field.ended_years.length
              ? '; seasons that have ended keep theirs'
              : ''}.
          </p>
        {/if}
      </section>
    {/if}

    <div class="grid gap-4 md:grid-cols-2">
      <section class="space-y-2 rounded-lg border border-line bg-surface-raised p-4 text-sm">
        <h2 class="font-medium">Area</h2>
        {#if acres === null}
          <p class="text-ink-muted">Draw or import the field's shape to measure it.</p>
        {/if}
        <FieldAreaInput
          name="outline[area_acres]"
          bind:value={area}
          saved={field.area_acres}
          drawn={acres}
          info="field.area"
          error={errors.area_acres}
        />
        {#if field.ended_years.length && area !== field.area_acres}
          <p class="text-xs text-ink-muted">Seasons that have ended keep the area they ran with.</p>
        {/if}
      </section>

      <section class="space-y-2 rounded-lg border border-line bg-surface-raised p-4 text-sm">
        <h2 class="font-medium">Soil</h2>
        <FieldSoilInput
          name="outline[soil_type_id]"
          bind:value={soilTypeId}
          soilTypes={soil_types}
          saved={field.soil_type_id}
          boundary={settled && !settledProblems.length ? settled : null}
          info="field.soil"
          error={errors.soil_type}
        />
        {#if field.ended_years.length && soilTypeId !== String(field.soil_type_id)}
          <p class="text-xs text-ink-muted">Seasons that have ended keep the soil they ran with.</p>
        {/if}
      </section>
    </div>

    <div class="flex items-center gap-3">
      <Button type="submit" disabled={processing || problems.length > 0 || mode !== 'view'}>Save</Button>
      <Link href={backHref} class="text-sm text-brand-600 hover:underline">Cancel</Link>
      {#if mode !== 'view'}<span class="text-sm text-ink-muted">Save or cancel the shape on the map first.</span>{/if}
    </div>
  {/snippet}
</Form>
