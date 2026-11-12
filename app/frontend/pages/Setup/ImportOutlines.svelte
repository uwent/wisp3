<script lang="ts">
  import { Form, Link, page } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import type { PivotShape } from '@/lib/geo'
  import ImportMap from '@/lib/outlines/ImportMap.svelte'
  import { type Choice, initialChoices, suggestSystem } from '@/lib/outlines/matching'
  import { ACCEPT, type ImportedShape, OutlineFileError, readOutlineFile, shapeName } from '@/lib/outlines/read'
  import type { Reference } from '@/lib/outlines/references'
  import { formatArea } from '@/lib/plantings'
  import { fetchSoilSurvey, suggestSoil } from '@/lib/soils'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { units as unitsFor } from '@/lib/units'
  import { outlineImport, setup } from '@/routes'
  import type { SoilType } from '@/types/serializers'

  type System = PivotShape & { id: number; name: string; kind_name: string; farm: string }
  type ExistingField = { id: number; name: string; pivot_id: number; area_acres: number | null; outlined: boolean }

  // Field outlines for many fields from one file (PLAN.md Phase 8 G.10): read in the browser, each
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

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))

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
  confirmUnsavedChanges(() => !saved && rows.some((row) => row.choice.kind !== 'skip'))

  const systemLabel = (system: System) => `${system.farm} › ${system.kind_name}: ${system.name}`
  const systemOptions = $derived([
    { value: '', label: 'Choose an irrigation system' },
    ...pivots.map((system) => ({ value: String(system.id), label: systemLabel(system) })),
  ])
  const fieldOptions = $derived([
    { value: 'skip', label: 'Skip this shape' },
    { value: 'new', label: 'New field' },
    ...fields.map((field) => {
      const system = pivots.find((p) => p.id === field.pivot_id)
      return { value: `field:${field.id}`, label: `${field.name} (${system ? system.name : ''})` }
    }),
  ])
  const choiceValue = (choice: Choice) => (choice.kind === 'field' ? `field:${choice.fieldId}` : choice.kind)
  const parseChoice = (value: string): Choice =>
    value.startsWith('field:') ? { kind: 'field', fieldId: Number(value.slice(6)) } : { kind: value as 'skip' | 'new' }

  const references = $derived<Reference[]>([...pivots.map((system) => ({ name: system.name, shape: system }))])

  async function readFile(event: Event) {
    const input = event.currentTarget as HTMLInputElement
    const file = input.files?.[0]
    input.value = ''
    if (!file) return
    reading = true
    fileError = null
    try {
      const result = await readOutlineFile(file)
      fileName = file.name
      skipped = result.skipped
      keys = [...new Set(result.shapes.flatMap((shape) => Object.keys(shape.properties)))]
      nameKey = result.nameKey
      startRows(result.shapes)
      fileKey++
    } catch (error) {
      fileError =
        error instanceof OutlineFileError ? error.message : `This file couldn't be read (${(error as Error).message}).`
    } finally {
      reading = false
    }
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

  // The soil survey's main soil for each new field, one at a time, until the grower picks one
  let surveying = false
  async function surveyNewRows() {
    if (surveying) return
    surveying = true
    try {
      for (let index = 0; index < rows.length; index++) {
        const row = rows[index]
        if (row.choice.kind !== 'new' || row.soil !== 'default') continue
        try {
          const suggestion = suggestSoil(await fetchSoilSurvey(row.shape.boundary))
          const soil = soil_types.find((type) => type.key === suggestion.key)
          if (soil && rows[index] === row && row.soil === 'default') {
            row.soilTypeId = soil.id
            row.soil = 'survey'
          }
        } catch {
          // The survey can't be reached: the default stays, and the grower can pick
        }
      }
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

<svelte:head><title>Import field outlines · WISP</title></svelte:head>

<div class="space-y-1">
  <Link href={setup.show()} class="text-sm text-brand-600 hover:underline">← Setup</Link>
  <h1 class="text-2xl font-semibold">Import field outlines</h1>
  <p class="max-w-prose text-sm text-ink-muted">
    Outlines draw your fields on the map and suggest their area and soil; the water balance doesn't use them. Most
    growers already have them: FSA field boundaries (Common Land Units) from your county office, or boundaries exported
    from John Deere Operations Center, Climate FieldView or Google Earth. WISP reads a zipped shapefile (.zip with the
    .shp, .dbf and .prj), GeoJSON, or KML and KMZ. The file stays on your computer; only the outlines you save are sent.
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

{#if rows.length}
  <div class="space-y-3">
    <p class="text-sm" aria-live="polite">
      {rows.length === 1 ? 'One shape' : `${rows.length} shapes`}{skipped
        ? `, and ${skipped} ${skipped === 1 ? 'point or line' : 'points or lines'} left out`
        : ''}. Each goes to the field of the same name, or becomes a new field under the irrigation system it's under;
      change any of them below.
    </p>
    {#if keys.length > 1}
      <div class="max-w-xs">
        <SelectField
          label="Names from"
          value={nameKey ?? ''}
          options={[{ value: '', label: 'No names' }, ...keys.map((key) => ({ value: key, label: key }))]}
          onchange={(event) => changeNameKey((event.currentTarget as HTMLSelectElement).value)}
          hint="The file's attribute that holds each field's name"
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
    <p class="flex flex-wrap gap-x-4 text-xs text-ink-muted">
      <span><span class="inline-block size-3 rounded-sm bg-[#3987e5] align-middle"></span> An existing field</span>
      <span><span class="inline-block size-3 rounded-sm bg-[#16a34a] align-middle"></span> A new field</span>
      <span><span class="inline-block size-3 rounded-sm bg-[#9ca3af] align-middle"></span> Skipped</span>
    </p>
  </div>

  <Form action={outlineImport()} class="space-y-4" options={{ preserveScroll: true }} onSuccess={() => (saved = true)}>
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
              {#if row.shape.simplified}<span class="text-xs text-ink-muted">simplified to fewer corners</span>{/if}
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
                  hint={existing?.outlined ? 'Replaces its outline' : undefined}
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
                    hint={row.soil === 'survey' ? 'The main soil in the outline, from the soil survey' : undefined}
                    error={rowError(errors, index, 'soil_type')}
                  />
                {/if}
              </div>
              {#if rowError(errors, index, 'boundary')}
                <p class="mt-2 text-status-irrigate-ink">The outline {rowError(errors, index, 'boundary')}</p>
              {/if}
            {/if}
          </li>
        {/each}
      </ol>

      <label class="flex items-start gap-2 text-sm">
        <input type="checkbox" class="mt-0.5 rounded" bind:checked={useArea} />
        <span>Set existing fields' area from their outlines (seasons that have ended keep theirs)</span>
      </label>
      {#if errors.rows}<p class="text-sm text-status-irrigate-ink">{[errors.rows].flat()[0]}</p>{/if}
      <div class="flex flex-wrap items-center gap-3">
        <Button type="submit" disabled={processing || !included.length || unready.length > 0}
          >Save {included.length === 1 ? 'the outline' : `${included.length} outlines`}</Button
        >
        <span class="text-sm text-ink-muted">
          {counts.existing} existing {counts.existing === 1 ? 'field' : 'fields'}, {counts.added} new
        </span>
        <Link href={setup.show()} class="text-sm text-brand-600 hover:underline">Cancel</Link>
      </div>
    {/snippet}
  </Form>
{/if}
