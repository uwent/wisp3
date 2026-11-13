<script lang="ts">
  import { untrack } from 'svelte'
  import { Form, Link, page } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import { type Boundary, boundaryAcres, boundaryErrors, type PivotShape, systemName } from '@/lib/geo'
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
  import FieldAreaInput from '@/lib/setup/FieldAreaInput.svelte'
  import FieldSoilInput from '@/lib/setup/FieldSoilInput.svelte'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { units as unitsFor } from '@/lib/units'
  import { fieldOutlines, fields, setup } from '@/routes'
  import type { Field, SoilType } from '@/types/serializers'

  type System = PivotShape & { id: number; name: string; kind_name?: string }

  // A field's outline (PLAN.md Phase 8 G.10), called its shape on the page (G.6): drawn or read from a
  // file; its acres are offered for the field's area and the soil survey under it labels the soil
  // menu, with the field dialog's own inputs (G.14 part 5). For the map and suggestions only: the
  // balance doesn't use it.
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

  let boundary = $state<Boundary | null>(untrack(() => field.boundary))
  let mode = $state<DrawMode>('view')
  let map = $state<OutlineMap>()
  // The tools wait for the map and its drawing tools to load
  let ready = $state(false)

  const acres = $derived(boundary ? boundaryAcres(boundary) : null)
  const problems = $derived(boundary ? boundaryErrors(boundary) : [])

  let area = $state<number | null>(untrack(() => field.area_acres))
  let soilTypeId = $state(untrack(() => String(field.soil_type_id)))

  // The map shows the field's own system first, then the others and the other fields' outlines
  const references = $derived<Reference[]>([
    { name: systemName(pivot), shape: pivot },
    ...other_pivots.map((other) => ({ name: other.name, shape: other })),
    ...other_fields.map((other) => ({ name: other.name, boundary: other.boundary })),
  ])

  // Unsaved changes
  const initial = untrack(() => JSON.stringify(field.boundary))
  let saved = $state(false)

  const changed = $derived(
    JSON.stringify(boundary) !== initial || soilTypeId !== String(field.soil_type_id) || area !== field.area_acres,
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
    Irrigation system: {systemName(pivot)}. The shape draws the field on the map and measures its area, and the soil
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
    <Button type="button" variant="ghost" disabled={reading} onclick={() => fileInput?.click()}
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
      <p class="mt-2 text-xs text-ink-muted">
        To add shapes for several fields at once, use Import field shapes in Setup.
      </p>
    </div>
  {/if}

  <OutlineMap
    bind:this={map}
    bind:boundary
    bind:mode
    bind:ready
    saved={field.boundary}
    {references}
    soilTypes={soil_types}
  />
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

    <!-- Each card its own height: the soil survey arriving doesn't stretch the area's -->
    <div class="grid items-start gap-4 md:grid-cols-2">
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
          boundary={boundary && !problems.length ? boundary : null}
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
