<script lang="ts">
  import { untrack } from 'svelte'
  import { Form, Link, page } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import SoilSurvey from '@/lib/components/SoilSurvey.svelte'
  import {
    type Boundary,
    boundaryAcres,
    boundaryErrors,
    boundaryFrom,
    isPoint,
    KIND_NOUNS,
    type PivotShape,
    pivotOutline,
    roundBoundary,
    systemName,
  } from '@/lib/geo'
  import OutlineMap, { type DrawMode } from '@/lib/outlines/OutlineMap.svelte'
  import {
    ACCEPT,
    type ImportedShape,
    OutlineFileError,
    readOutlineFile,
    shapeName,
    shapeNotes,
  } from '@/lib/outlines/read'
  import type { Reference } from '@/lib/outlines/references'
  import { formatArea } from '@/lib/plantings'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { units as unitsFor } from '@/lib/units'
  import { fieldOutlines, fields, setup } from '@/routes'
  import type { Field, SoilType } from '@/types/serializers'

  type System = PivotShape & { id: number; name: string; kind_name?: string }

  // A field's outline (PLAN.md Phase 8 G.10): drawn, copied from its irrigation system, or read from
  // a file; its acres offered for the field's area and the soil survey's main soil for its soil. For
  // the map and suggestions only: the balance doesn't use it.
  let {
    field,
    pivot,
    other_pivots,
    other_fields,
    soil_types,
    from,
  }: {
    field: Field
    pivot: System & { kind_name: string }
    other_pivots: System[]
    other_fields: { id: number; name: string; boundary: Boundary }[]
    soil_types: SoilType[]
    from: 'setup' | 'field'
  } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const noun = $derived(KIND_NOUNS[pivot.kind])
  const hasShape = $derived(!isPoint(pivot.kind))

  let boundary = $state<Boundary | null>(untrack(() => field.boundary))
  let mode = $state<DrawMode>('view')
  let map = $state<OutlineMap>()
  // The tools wait for the map and its drawing tools to load
  let ready = $state(false)

  const acres = $derived(boundary ? boundaryAcres(boundary) : null)
  const problems = $derived(boundary ? boundaryErrors(boundary) : [])

  // The area: offered from the outline, used when the box is ticked (ticked to start when the
  // field has no area, or the outline is new and differs from it)
  let useArea = $state(untrack(() => field.area_acres === null))
  const areaDiffers = $derived(acres !== null && Math.abs(acres - (field.area_acres ?? 0)) >= 0.05)
  const roundedAcres = $derived(acres === null ? null : Math.round(acres * 100) / 100)

  // The soil: the survey's suggestion, used only when asked
  let soilTypeId = $state<number | null>(null)
  const currentSoil = $derived(soil_types.find((soil) => soil.id === field.soil_type_id))
  const chosenSoil = $derived(soil_types.find((soil) => soil.id === soilTypeId))

  // The map shows the field's own system first, then the others and the other fields' outlines
  const references = $derived<Reference[]>([
    { name: systemName(pivot), shape: pivot },
    ...other_pivots.map((other) => ({ name: other.name, shape: other })),
    ...other_fields.map((other) => ({ name: other.name, boundary: other.boundary })),
  ])

  // Unsaved changes
  const initial = untrack(() => JSON.stringify(field.boundary))
  let saved = $state(false)
  const changed = $derived(JSON.stringify(boundary) !== initial || soilTypeId !== null)
  confirmUnsavedChanges(() => !saved && changed)

  function sameAsSystem() {
    const ring = pivotOutline(pivot, 96)
    if (!ring) return
    boundary = roundBoundary(boundaryFrom(ring))
    mode = 'view'
    fileNote = null
    useArea = field.area_acres === null || useArea
  }

  function removeOutline() {
    boundary = null
    mode = 'view'
    fileNote = null
  }

  // Drawing over an outline replaces it once the new one is finished, so ask first
  function toggleDraw() {
    if (mode === 'draw') {
      mode = 'view'
      return
    }
    if (boundary && !confirm('Draw a new outline? It replaces this one once you finish it.')) return
    mode = 'draw'
    fileNote = null
  }

  // The server's errors arrive as a string or a list
  const listed = (error: string | string[] | undefined) => (error === undefined ? [] : [error].flat())

  // A file: one shape is used; several are listed to pick one
  let fileInput = $state<HTMLInputElement>()
  let reading = $state(false)
  let fileError = $state<string | null>(null)
  // What reading the file changed in the shape used ("Kept the largest of 3 parts")
  let fileNote = $state<string | null>(null)
  let choices = $state<{ shapes: ImportedShape[]; nameKey: string | null; skipped: number } | null>(null)

  async function readFile(event: Event) {
    const input = event.currentTarget as HTMLInputElement
    const file = input.files?.[0]
    input.value = ''
    if (!file) return
    reading = true
    fileError = null
    choices = null
    try {
      const result = await readOutlineFile(file)
      const usable = result.shapes.filter((shape) => !shape.problems.length)
      if (result.shapes.length === 1 && usable.length === 1) useShape(usable[0])
      else choices = result
    } catch (error) {
      fileError =
        error instanceof OutlineFileError ? error.message : `This file couldn't be read (${(error as Error).message}).`
    } finally {
      reading = false
    }
  }

  function useShape(shape: ImportedShape) {
    boundary = shape.boundary
    choices = null
    mode = 'view'
    fileNote = shapeNotes(shape) || null
  }

  const backHref = $derived(from === 'setup' ? setup.show().url : fields.show(field.id).url)
  const MODE_HINTS: Record<DrawMode, string> = {
    view: '',
    draw: 'Click the map at each corner of the field. Click the first corner again, or press Enter, to finish.',
    edit: 'Click the outline to select it, then drag a corner to move it, drag a midpoint to add a corner, or right-click a corner to remove it.',
  }
</script>

<svelte:head><title>Outline: {field.name} · WISP</title></svelte:head>

<div class="space-y-1">
  <Link href={backHref} class="text-sm text-brand-600 hover:underline">← {from === 'setup' ? 'Setup' : field.name}</Link
  >
  <h1 class="text-2xl font-semibold">Outline: {field.name}</h1>
  <p class="text-sm text-ink-muted">
    Irrigation system: {systemName(pivot)}. The outline draws the field on the map and suggests its area and soil; the
    water balance doesn't use it.
  </p>
</div>

<div class="space-y-3">
  <!-- The tools wait for the map to load -->
  <fieldset class="flex flex-wrap items-center gap-2" disabled={!ready} aria-label="Outline tools">
    {#if !boundary}
      {#if hasShape}
        <Button type="button" variant="secondary" onclick={sameAsSystem}>Same as the {noun}</Button>
      {/if}
      <Button type="button" variant={mode === 'draw' ? 'primary' : 'secondary'} onclick={toggleDraw}
        >Draw the outline</Button
      >
    {:else}
      <Button
        type="button"
        variant={mode === 'edit' ? 'primary' : 'secondary'}
        aria-pressed={mode === 'edit'}
        onclick={() => (mode = mode === 'edit' ? 'view' : 'edit')}>Edit corners</Button
      >
      <Button
        type="button"
        variant={mode === 'draw' ? 'primary' : 'secondary'}
        aria-pressed={mode === 'draw'}
        onclick={toggleDraw}>Draw a new one</Button
      >
      {#if hasShape}
        <Button type="button" variant="ghost" onclick={sameAsSystem}>Same as the {noun}</Button>
      {/if}
    {/if}
    <Button type="button" variant="ghost" disabled={reading} onclick={() => fileInput?.click()}
      >{reading ? 'Reading…' : 'Import from a file'}</Button
    >
    {#if boundary}
      <Button type="button" variant="danger-ghost" onclick={removeOutline}>Remove the outline</Button>
    {/if}
    <input
      bind:this={fileInput}
      type="file"
      accept={ACCEPT}
      class="sr-only"
      tabindex="-1"
      aria-label="Outline file"
      onchange={readFile}
    />
  </fieldset>
  {#if MODE_HINTS[mode]}
    <p class="text-sm text-ink-muted" aria-live="polite">{MODE_HINTS[mode]}</p>
  {:else if fileNote}
    <p class="text-sm text-ink-muted">From the file: {fileNote}. A field's outline is one shape without holes.</p>
  {/if}
  {#if fileError}
    <p class="text-sm text-status-irrigate-ink" role="alert">{fileError}</p>
  {/if}
  {#if choices}
    <div class="rounded-lg border border-line bg-surface-raised p-4 text-sm">
      <p class="font-medium">This file has {choices.shapes.length} shapes. Which is {field.name}?</p>
      <ul class="mt-2 space-y-1">
        {#each choices.shapes as shape, index (index)}
          <li class="flex flex-wrap items-baseline gap-x-2">
            <button
              type="button"
              class="text-brand-600 underline underline-offset-2 disabled:text-ink-muted disabled:no-underline"
              disabled={shape.problems.length > 0}
              onclick={() => useShape(shape)}>{shapeName(shape, choices!.nameKey) || `Shape ${index + 1}`}</button
            >
            <span class="text-ink-muted">{formatArea(units, shape.acres)}</span>
            {#if shape.problems.length}<span class="text-status-irrigate-ink">: {shape.problems.join('; ')}</span>{/if}
          </li>
        {/each}
      </ul>
      <p class="mt-2 text-xs text-ink-muted">To outline several fields at once, use Import field outlines in Setup.</p>
    </div>
  {/if}

  <OutlineMap bind:this={map} bind:boundary bind:mode bind:ready {references} />
</div>

<Form
  action={fieldOutlines.update(field.id, { query: from === 'setup' ? { from } : {} })}
  class="space-y-4"
  onSuccess={() => (saved = true)}
>
  {#snippet children({ errors, processing })}
    <input type="hidden" name="outline[boundary]" value={boundary ? JSON.stringify(boundary) : ''} />
    {#if boundary && useArea && roundedAcres !== null}
      <input type="hidden" name="outline[area_acres]" value={roundedAcres} />
    {/if}
    {#if soilTypeId !== null}
      <input type="hidden" name="outline[soil_type_id]" value={soilTypeId} />
    {/if}

    {#if problems.length || errors.boundary}
      <div class="rounded-md border border-status-irrigate px-3 py-2 text-sm" role="alert">
        The outline {(errors.boundary ? listed(errors.boundary) : problems).join('; ')}.
      </div>
    {/if}

    <div class="grid gap-4 md:grid-cols-2">
      <section class="space-y-2 rounded-lg border border-line bg-surface-raised p-4 text-sm">
        <h2 class="font-medium">Area</h2>
        {#if acres !== null}
          <p>
            The outline: <span class="font-medium">{formatArea(units, acres)}</span>. The field: {field.area_acres ===
            null
              ? 'no area set'
              : formatArea(units, field.area_acres)}.
          </p>
          {#if areaDiffers}
            <label class="flex items-start gap-2">
              <input type="checkbox" class="mt-0.5 rounded" bind:checked={useArea} />
              <span>Use {formatArea(units, acres)} for the field's area</span>
            </label>
            {#if field.ended_years.length}
              <p class="text-xs text-ink-muted">Seasons that have ended keep the area they ran with.</p>
            {/if}
          {/if}
        {:else}
          <p class="text-ink-muted">Draw or import the outline to measure it.</p>
        {/if}
        {#if errors.area_acres}<p class="text-status-irrigate-ink">Area {listed(errors.area_acres).join('; ')}</p>{/if}
      </section>

      <section class="space-y-2 rounded-lg border border-line bg-surface-raised p-4 text-sm">
        <h2 class="font-medium">Soil</h2>
        <p>
          The field: {currentSoil?.name}{#if chosenSoil}
            {` → ${chosenSoil.name} when saved `}<button
              type="button"
              class="text-brand-600 underline underline-offset-2"
              onclick={() => (soilTypeId = null)}>Keep {currentSoil?.name}</button
            >{/if}
        </p>
        {#if boundary && !problems.length}
          <SoilSurvey
            {boundary}
            soilTypes={soil_types}
            onuse={(soil) => (soilTypeId = soil.id === field.soil_type_id ? null : soil.id)}
          />
        {/if}
      </section>
    </div>

    <div class="flex items-center gap-3">
      <Button type="submit" disabled={processing || problems.length > 0 || mode === 'draw'}>Save</Button>
      <Link href={backHref} class="text-sm text-brand-600 hover:underline">Cancel</Link>
      {#if mode === 'draw'}<span class="text-sm text-ink-muted">Finish the outline you're drawing first.</span>{/if}
    </div>
  {/snippet}
</Form>
