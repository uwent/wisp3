<script lang="ts">
  import { Form, Link, page } from '@inertiajs/svelte'
  import { systemName } from '@/lib/geo'

  import Button from '@/lib/components/Button.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import type { PivotShape } from '@/lib/geo'
  import ImportMap from '@/lib/outlines/ImportMap.svelte'
  import { type Choice, initialChoices, suggestSystem } from '@/lib/outlines/matching'
  import { forgetKept, type KeptFile, type KeptShape, keepShapes, readAt, readKept } from '@/lib/outlines/kept'
  import { unusableSummary } from '@/lib/outlines/picker'
  import { ACCEPT, type ImportedShape, readOutlineFileResult, shapeName, shapeNotes } from '@/lib/outlines/read'
  import type { Reference } from '@/lib/outlines/references'
  import { formatArea } from '@/lib/plantings'
  import { fetchSoilSurvey, suggestSoil } from '@/lib/soils'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { currentUnits } from '@/lib/units'
  import { outlineImport, setup } from '@/routes'
  import type { SoilType } from '@/types/serializers'

  type System = PivotShape & { id: number; name: string; kind_name: string; farm: string }
  type ExistingField = { id: number; name: string; pivot_id: number; area_acres: number | null; outlined: boolean }

  // Field outlines for many fields from one file: read in the browser, each
  // shape matched to a field of the same name or made a new field under the system it sits under,
  // the grower adjusting either, then saved together. New fields take their outline's acres and the
  // soil survey's main soil.
  let {
    pivots,
    fields,
    soil_types,
    default_soil_type_id,
  }: {
    pivots: System[]
    fields: ExistingField[]
    soil_types: SoilType[]
    default_soil_type_id: number | null
  } = $props()

  const units = $derived(currentUnits())

  type Row = {
    shape: ImportedShape
    systemId: number | null
    choice: Choice
    name: string
    soilTypeId: number
    soil: 'default' | 'survey' | 'chosen'
  }

  let fileName = $state<string | null>(null)
  let fileKey = $state(0)
  let reading = $state(false)
  let fileError = $state<string | null>(null)
  let skipped = $state(0)
  let keys = $state<string[]>([])
  let nameKey = $state<string | null>(null)
  let rows = $state<Row[]>([])
  let selected = $state<number | null>(null)
  let useArea = $state(false)
  let saved = $state(false)
  confirmUnsavedChanges(
    () => !saved && rows.some((row) => row.choice.kind !== 'skip'),
    () => document.getElementById('outline-import-form'),
  )

  const systemLabel = (system: System) => `${system.farm} › ${systemName(system)}`
  const systemOptions = $derived([
    { value: '', label: 'Choose an irrigation system' },
    ...pivots.map((system) => ({ value: String(system.id), label: systemLabel(system) })),
  ])
  const fieldOptions = $derived([
    { value: 'skip', label: 'Skip this shape' },
    { value: 'new', label: 'New field' },
    ...fields.map((field) => {
      const system = pivots.find((p) => p.id === field.pivot_id)
      return { value: `field:${field.id}`, label: system ? `${field.name} (${system.name})` : field.name }
    }),
  ])
  const choiceValue = (choice: Choice) => (choice.kind === 'field' ? `field:${choice.fieldId}` : choice.kind)
  const parseChoice = (value: string): Choice =>
    value.startsWith('field:') ? { kind: 'field', fieldId: Number(value.slice(6)) } : { kind: value as 'skip' | 'new' }

  const references = $derived<Reference[]>(pivots.map((system) => ({ name: system.name, shape: system })))

  // The last file read here or on a field's shape page is kept for the session (lib/outlines/kept.ts),
  // to finish here what was started there, or the other way round
  const groupId = page.props.auth.group?.id ?? null
  let kept = $state<KeptFile | null>(readKept(groupId))

  // Shapes that can't be saved have no row (nor a soil survey, nor a place on the map): a county
  // file's thousands are one line saying why
  let unusable = $state<KeptShape[]>([])
  const UNUSABLE_LISTED = 200

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
    // This file is kept in place of the last one
    if (result.shapes.length > 1) keepShapes(groupId, { fileName: file.name, ...result })
    else forgetKept(groupId)
    kept = null
    load({ fileName: file.name, ...result })
  }

  function useKept() {
    if (!kept) return
    load(kept)
    kept = null
  }

  function forgetShapes() {
    forgetKept(groupId)
    kept = null
  }

  function load(file: { fileName: string; nameKey: string | null; skipped: number; shapes: KeptShape[] }) {
    fileName = file.fileName
    skipped = file.skipped
    keys = [...new Set(file.shapes.flatMap((shape) => Object.keys(shape.properties)))]
    nameKey = file.nameKey
    unusable = file.shapes.filter((shape) => shape.problems.length || !shape.boundary)
    startRows(file.shapes.filter((shape): shape is ImportedShape => !shape.problems.length && shape.boundary !== null))
    fileKey++
  }

  function startRows(shapes: ImportedShape[]) {
    const named = shapes.map((shape) => ({
      shape,
      name: shapeName(shape, nameKey),
      systemId: suggestSystem(shape.boundary, pivots),
    }))
    const choices = initialChoices(
      named.map(({ name, systemId, shape }) => ({ name, systemId, problems: shape.problems })),
      fields,
    )
    rows = named.map(({ shape, name, systemId }, index) => ({
      shape,
      systemId,
      choice: choices[index],
      name: name || `Field ${index + 1}`,
      soilTypeId: default_soil_type_id ?? soil_types[0]?.id,
      soil: 'default',
    }))
    selected = null
    surveyNewRows()
  }

  // A different name attribute renames the shapes and matches them again
  function changeNameKey(key: string) {
    nameKey = key || null
    startRows(rows.map((row) => row.shape))
  }

  // The soil survey's main soil for each new field, one at a time, until the grower picks one. A call
  // while a run is going (a row made new, another file or name attribute) has the run start over once
  // it's through, so rows behind it aren't missed. Each shape's answer is kept (null: none, or the
  // survey couldn't be reached), so rows made again for another name attribute don't ask twice.
  let surveying = false
  let again = false
  const surveyed = new WeakMap<object, number | null>()
  async function soilFor(shape: ImportedShape) {
    if (!surveyed.has(shape)) {
      let id: number | null = null
      try {
        const suggestion = suggestSoil(await fetchSoilSurvey(shape.boundary))
        id = soil_types.find((type) => type.key === suggestion.key)?.id ?? null
      } catch {
        // The survey can't be reached: the default stays, and the grower can pick
      }
      surveyed.set(shape, id)
    }
    return surveyed.get(shape) ?? null
  }
  async function surveyNewRows() {
    if (surveying) {
      again = true
      return
    }
    surveying = true
    try {
      do {
        again = false
        for (let index = 0; index < rows.length; index++) {
          const row = rows[index]
          if (row.choice.kind !== 'new' || row.soil !== 'default') continue
          const soilId = await soilFor(row.shape)
          if (soilId !== null && rows[index] === row && row.soil === 'default') {
            row.soilTypeId = soilId
            row.soil = 'survey'
          }
        }
      } while (again)
    } finally {
      surveying = false
    }
  }

  function choose(index: number, value: string) {
    rows[index].choice = parseChoice(value)
    if (rows[index].choice.kind === 'new') surveyNewRows()
  }

  // A field chosen in two rows: each later row, by the earlier row it repeats
  const usedBy = $derived.by(() => {
    const first: Record<number, number> = {}
    const repeats: Record<number, number> = {}
    rows.forEach((row, index) => {
      if (row.choice.kind !== 'field') return
      const earlier = first[row.choice.fieldId]
      if (earlier === undefined) first[row.choice.fieldId] = index
      else repeats[index] = earlier
    })
    return repeats
  })

  const included = $derived(rows.map((row, index) => ({ row, index })).filter(({ row }) => row.choice.kind !== 'skip'))
  const unready = $derived(
    included.filter(
      ({ row, index }) =>
        usedBy[index] !== undefined || (row.choice.kind === 'new' && (row.systemId === null || !row.name.trim())),
    ),
  )
  const counts = $derived({
    existing: included.filter(({ row }) => row.choice.kind === 'field').length,
    added: included.filter(({ row }) => row.choice.kind === 'new').length,
  })

  // The server's errors are keyed by the submitted rows' order ("rows.2.name")
  const rowError = (errors: Record<string, string | string[]>, index: number, attribute: string) => {
    const position = included.findIndex((entry) => entry.index === index)
    const error = errors[`rows.${position}.${attribute}`]
    return error === undefined ? undefined : [error].flat()[0]
  }

  function pick(index: number) {
    selected = index
    document.getElementById(`shape-${index}`)?.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
  }
</script>

<svelte:head><title>Import field shapes · WISP</title></svelte:head>

<div class="space-y-1">
  <Link href={setup.show()} class="text-sm text-brand-600 hover:underline">← Setup</Link>
  <h1 class="text-2xl font-semibold">Import field shapes</h1>
  <p class="max-w-prose text-sm text-ink-muted">
    Field shapes draw your fields on the map and measure their area, and the soil survey under them suggests their soil;
    the water balance doesn't use the shapes themselves. Most growers already have them: FSA field boundaries (Common
    Land Units) from your county office, or boundaries exported from John Deere Operations Center, Climate FieldView or
    Google Earth. WISP reads a zipped shapefile (.zip with the .shp, .dbf and .prj), GeoJSON, or KML and KMZ. The file
    stays on your computer; only the shapes you save are sent.
  </p>
</div>

<div class="flex flex-wrap items-center gap-3">
  <label
    class="inline-flex cursor-pointer items-center rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white
      focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-brand-500 hover:bg-brand-700
      dark:text-surface"
  >
    {reading ? 'Reading…' : fileName ? 'Choose another file' : 'Choose a file'}
    <input type="file" accept={ACCEPT} class="sr-only" disabled={reading} onchange={readFile} />
  </label>
  {#if fileName}<span class="text-sm text-ink-muted">{fileName}</span>{/if}
</div>
{#if fileError}<p class="text-sm text-status-irrigate-ink" role="alert">{fileError}</p>{/if}

{#if kept && !fileName}
  <div class="flex flex-wrap items-center gap-x-3 gap-y-2 rounded-lg border border-line bg-surface-raised p-4 text-sm">
    <p>
      {`The ${kept.shapes.length.toLocaleString('en-US')} shapes from ${kept.fileName} (${readAt(kept.savedAt)}) are still here.`}
    </p>
    <Button type="button" variant="secondary" class="px-3 py-1" onclick={useKept}>Use these shapes</Button>
    <Button type="button" variant="ghost" class="px-3 py-1" onclick={forgetShapes}>Forget these shapes</Button>
  </div>
{/if}

{#if unusable.length}
  <details class="rounded-lg border border-line bg-surface-raised p-4 text-sm">
    <summary class="cursor-pointer">
      <span class="text-status-irrigate-ink"
        >{`${unusable.length.toLocaleString('en-US')} ${unusable.length === 1 ? "shape can't" : "shapes can't"} be used for a field`}</span
      >{`: ${unusableSummary(unusable)}.`}
    </summary>
    <ul class="mt-2 space-y-0.5 text-ink-muted">
      {#each unusable.slice(0, UNUSABLE_LISTED) as shape, index (index)}
        <li>
          {`${shapeName(shape, nameKey) || 'Unnamed shape'}, ${formatArea(units, shape.acres)}: ${shape.problems.join('; ')}`}
        </li>
      {/each}
      {#if unusable.length > UNUSABLE_LISTED}
        <li>{`and ${(unusable.length - UNUSABLE_LISTED).toLocaleString('en-US')} more`}</li>
      {/if}
    </ul>
  </details>
{/if}

{#if rows.length}
  <div class="space-y-3">
    <p class="text-sm" aria-live="polite">
      {rows.length === 1 ? 'One shape' : `${rows.length.toLocaleString('en-US')} shapes`}{unusable.length
        ? ' that can be used'
        : ''}{skipped ? `, and ${skipped} ${skipped === 1 ? 'point or line' : 'points or lines'} left out` : ''}. Each
      goes to the field of the same name, or becomes a new field under the irrigation system it's under; change any of
      them below.
    </p>
    {#if keys.length > 1}
      <div class="max-w-xs">
        <SelectField
          label="Names from"
          value={nameKey ?? ''}
          options={[{ value: '', label: 'No names' }, ...keys.map((key) => ({ value: key, label: key }))]}
          onchange={(event) => changeNameKey((event.currentTarget as HTMLSelectElement).value)}
          info="field.shape_names"
        />
      </div>
    {/if}

    <ImportMap
      shapes={rows.map((row, index) => ({
        boundary: row.shape.boundary,
        label: `${index + 1}${row.name ? ` ${row.name}` : ''}`,
        state: row.choice.kind,
      }))}
      {references}
      {selected}
      {fileKey}
      onselect={pick}
    />
  </div>

  <Form
    id="outline-import-form"
    action={outlineImport()}
    class="space-y-4"
    options={{ preserveScroll: true }}
    onSuccess={() => (saved = true)}
  >
    {#snippet children({ errors, processing })}
      {#each included as { row }, position (row)}
        <input
          type="hidden"
          name="outline_import[rows][{position}][boundary]"
          value={JSON.stringify(row.shape.boundary)}
        />
        {#if row.choice.kind === 'field'}
          <input type="hidden" name="outline_import[rows][{position}][field_id]" value={row.choice.fieldId} />
        {:else}
          <input type="hidden" name="outline_import[rows][{position}][pivot_id]" value={row.systemId ?? ''} />
          <input type="hidden" name="outline_import[rows][{position}][name]" value={row.name} />
          <input type="hidden" name="outline_import[rows][{position}][soil_type_id]" value={row.soilTypeId} />
          <input
            type="hidden"
            name="outline_import[rows][{position}][area_acres]"
            value={Math.round(row.shape.acres * 100) / 100}
          />
        {/if}
      {/each}
      <input type="hidden" name="outline_import[use_area]" value={useArea ? '1' : '0'} />

      <ol class="space-y-3">
        {#each rows as row, index (row)}
          {@const existing =
            row.choice.kind === 'field'
              ? fields.find((f) => f.id === (row.choice as { fieldId: number }).fieldId)
              : null}
          <li
            id="shape-{index}"
            class="rounded-lg border bg-surface-raised p-4 text-sm
              {selected === index ? 'border-brand-500' : 'border-line'}"
          >
            <div class="flex flex-wrap items-baseline gap-x-3">
              <button type="button" class="font-medium hover:underline" onclick={() => (selected = index)}
                >{index + 1}. {shapeName(row.shape, nameKey) || 'Unnamed shape'}</button
              >
              <span class="text-ink-muted">{formatArea(units, row.shape.acres)}</span>
              {#if row.shape.notes.length}<span class="text-xs text-ink-muted">{shapeNotes(row.shape)}</span>{/if}
            </div>
            {#if row.shape.problems.length}
              <p class="mt-1 text-status-irrigate-ink">
                This shape {row.shape.problems.join('; ')}, so it can't be saved.
              </p>
            {:else}
              <div class="mt-3 grid gap-3 sm:grid-cols-2">
                <SelectField
                  label="Field"
                  id="shape-{index}-field"
                  value={choiceValue(row.choice)}
                  options={fieldOptions}
                  onchange={(event) => choose(index, (event.currentTarget as HTMLSelectElement).value)}
                  error={usedBy[index] !== undefined
                    ? `Also chosen for shape ${usedBy[index] + 1}`
                    : rowError(errors, index, 'field_id')}
                  hint={existing?.outlined ? 'Replaces its shape' : undefined}
                />
                {#if row.choice.kind === 'new'}
                  <SelectField
                    label="Irrigation system"
                    id="shape-{index}-system"
                    value={row.systemId === null ? '' : String(row.systemId)}
                    options={systemOptions}
                    onchange={(event) => {
                      const value = (event.currentTarget as HTMLSelectElement).value
                      row.systemId = value ? Number(value) : null
                    }}
                    error={row.systemId === null
                      ? 'Choose the system that waters it'
                      : rowError(errors, index, 'pivot')}
                  />
                  <TextField
                    label="New field's name"
                    name="shape-{index}-name"
                    bind:value={row.name}
                    error={row.name.trim() ? rowError(errors, index, 'name') : 'Give the field a name'}
                  />
                  <SelectField
                    label="Soil"
                    id="shape-{index}-soil"
                    value={String(row.soilTypeId)}
                    options={soil_types.map((soil) => ({ value: String(soil.id), label: soil.name }))}
                    onchange={(event) => {
                      row.soilTypeId = Number((event.currentTarget as HTMLSelectElement).value)
                      row.soil = 'chosen'
                    }}
                    hint={row.soil === 'survey' ? 'The main soil in the shape, from the soil survey' : undefined}
                    error={rowError(errors, index, 'soil_type')}
                  />
                {/if}
              </div>
              {#if rowError(errors, index, 'boundary')}
                <p class="mt-2 text-status-irrigate-ink">The shape {rowError(errors, index, 'boundary')}</p>
              {/if}
            {/if}
          </li>
        {/each}
      </ol>

      <label class="flex items-start gap-2 text-sm">
        <input type="checkbox" class="mt-0.5 rounded" bind:checked={useArea} />
        <span>Set existing fields' area from their shapes (seasons that have ended keep theirs)</span>
      </label>
      {#if errors.rows}<p class="text-sm text-status-irrigate-ink">{[errors.rows].flat()[0]}</p>{/if}
      <div class="flex flex-wrap items-center gap-3">
        <Button type="submit" disabled={processing || !included.length || unready.length > 0}
          >Save {included.length === 1 ? 'the shape' : `${included.length} shapes`}</Button
        >
        <span class="text-sm text-ink-muted">
          {counts.existing} existing {counts.existing === 1 ? 'field' : 'fields'}, {counts.added} new
        </span>
        <Link href={setup.show()} class="text-sm text-brand-600 hover:underline">Cancel</Link>
      </div>
    {/snippet}
  </Form>
{/if}
