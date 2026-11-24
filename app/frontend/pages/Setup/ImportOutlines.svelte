<script lang="ts">
  import { onMount, tick } from 'svelte'
  import { Form, Link, page } from '@inertiajs/svelte'
  import { isPoint, systemName } from '@/lib/geo'

  import Button from '@/lib/components/Button.svelte'
  import DataTable from '@/lib/components/DataTable.svelte'
  import SegmentedChoice from '@/lib/components/SegmentedChoice.svelte'
  import Spinner from '@/lib/components/Spinner.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { type Boundary, boundaryCenter } from '@/lib/boundary'
  import type { SystemShape } from '@/lib/geo'
  import { type FieldCandidate, fieldCandidates, systemCandidates } from '@/lib/outlines/candidates'
  import ImportMap from '@/lib/outlines/ImportMap.svelte'
  import { ImportRow } from '@/lib/outlines/importRow.svelte'
  import { type Choice, initialChoices, sameAs, systemSuggester } from '@/lib/outlines/matching'
  import { forgetKept, type KeptShape, keepShapes, readAt, readKept } from '@/lib/outlines/kept'
  import { attributeValue, unusableSummary } from '@/lib/outlines/picker'
  import { OVERLAP_WARNING_SHARE, overlappingPairs, sharePercent } from '@/lib/outlines/overlap'
  import { formatReach, nearestSystemM } from '@/lib/outlines/problems'
  import { ACCEPT, type ImportedShape, readOutlineFileResult, shapeName, shapeNotes } from '@/lib/outlines/read'
  import type { Reference } from '@/lib/outlines/references'
  import { formatArea } from '@/lib/plantings'
  import { fetchSoilSurvey, suggestSoil } from '@/lib/soils'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { currentUnits } from '@/lib/units'
  import type { Column } from '@/lib/table'
  import { outlineImport, systems as systemRoutes, setup } from '@/routes'
  import type { SoilType } from '@/types/serializers'

  type System = SystemShape & { id: number; name: string; kind_name: string; farm: string }
  type ExistingField = {
    id: number
    name: string
    system_id: number
    area_acres: number | null
    boundary: Boundary | null
  }

  // Field outlines for many fields from one file: read in the browser, each shape matched to the
  // field of the same name or whose outline it covers, or made a new field under the system it sits
  // under, the grower adjusting any (Skip | New field | Update field), then saved together. A shape
  // overlapping a field, or another shape going in, says so, to keep duplicates out. New fields take
  // their outline's acres and the soil survey's main soil. Only the shapes going somewhere get a card; the rest (a county file's
  // thousands) start as Skip in one searchable list, from which the grower adds any that are theirs.
  let {
    systems,
    fields,
    soil_types,
    default_soil_type_id,
  }: {
    systems: System[]
    fields: ExistingField[]
    soil_types: SoilType[]
    default_soil_type_id: number | null
  } = $props()

  const units = $derived(currentUnits())

  let fileName = $state<string | null>(null)
  let fileKey = $state(0)
  let fileError = $state<string | null>(null)
  let skipped = $state(0)
  let keys = $state<string[]>([])
  let nameKey = $state<string | null>(null)
  // Replaced whole, never changed in place; each row's own state is reactive (ImportRow)
  let rows = $state.raw<ImportRow[]>([])
  let selected = $state<number | null>(null)
  let useArea = $state(false)
  let saved = $state(false)
  // What the grower has changed since the file was matched: leaving without importing loses only
  // that, as the file itself is kept
  const edits = (list: ImportRow[]) =>
    JSON.stringify(
      list.map((row) => [
        row.choice,
        row.carded,
        row.systemId,
        row.nameEdited && row.name,
        row.soil === 'chosen' && row.soilTypeId,
      ]),
    )
  let matched = $state('')
  confirmUnsavedChanges(
    () => !saved && rows.length > 0 && edits(rows) !== matched,
    () => document.getElementById('outline-import-form'),
  )

  const systemLabel = (system: System) => `${system.farm} › ${systemName(system)}`
  const fieldsById = $derived(new Map(fields.map((field) => [field.id, field])))
  const systemsById = $derived(new Map(systems.map((system) => [system.id, system])))

  // Where a shape goes, in the map's colors
  const CHOICES: { kind: Choice['kind']; label: string; color: string }[] = [
    { kind: 'skip', label: 'Skip', color: 'var(--color-map-shape-skip)' },
    { kind: 'new', label: 'New', color: 'var(--color-map-shape-new)' },
    { kind: 'field', label: 'Update', color: 'var(--color-map-shape-update)' },
  ]

  // Each shape's fields and systems, nearest first, worked out once per shape (lib/outlines/candidates.ts)
  const fieldsNear = new WeakMap<object, FieldCandidate[]>()
  function fieldsFor(shape: ImportedShape) {
    if (!fieldsNear.has(shape)) fieldsNear.set(shape, fieldCandidates(shape.boundary, fields, systems))
    return fieldsNear.get(shape)!
  }
  const systemsNear = new WeakMap<object, { id: number; meters: number }[]>()
  function systemsFor(shape: ImportedShape) {
    if (!systemsNear.has(shape)) systemsNear.set(shape, systemCandidates(shape.boundary, systems))
    return systemsNear.get(shape)!
  }
  const SHOWN_SHARE = 0.01
  const reach = (meters: number) => (Number.isFinite(meters) ? formatReach(meters, units.system) : '')
  const fieldOptionsFor = (shape: ImportedShape) =>
    fieldsFor(shape).map(({ id, share, meters }) => {
      const field = fieldsById.get(id)!
      const system = systemsById.get(field.system_id)
      const where = share >= SHOWN_SHARE ? `overlaps ${sharePercent(share)}` : reach(meters)
      return {
        value: String(id),
        label: `${field.name}${system ? ` (${system.name})` : ''}${where ? ` · ${where}` : ''}`,
      }
    })
  const systemOptionsFor = (shape: ImportedShape) => [
    { value: '', label: 'Choose an irrigation system' },
    ...systemsFor(shape).map(({ id, meters }) => {
      const system = systemsById.get(id)!
      const where = meters > 0 ? reach(meters) : isPoint(system.kind) ? 'inside' : 'overlaps'
      return { value: String(id), label: `${systemLabel(system)} · ${where}` }
    }),
  ]

  /** "East 40's shape", for a shape that's already a field's */
  const alreadyWhose = (row: ImportRow) => `${fieldsById.get(row.same!.fieldId)?.name ?? 'a field'}'s shape`
  const sameCount = $derived(rows.filter((row) => row.same && !row.carded).length)

  // Where a shape goes, for the map's hover label
  function mapDetail(row: ImportRow) {
    const { choice } = row
    if (choice.kind === 'field') return `Update ${fieldsById.get(choice.fieldId)?.name ?? 'field'}`
    if (choice.kind === 'skip') return row.same ? `Skip · already ${alreadyWhose(row)}` : 'Skip'
    const system = row.systemId === null ? undefined : systemsById.get(row.systemId)
    return system ? `New field under ${system.name}` : 'New field'
  }

  // The saved fields' outlines, each with the shape that will replace it
  const fieldsOnMap = $derived.by(() => {
    const updatedBy = new Map(
      rows.flatMap((row) =>
        row.choice.kind === 'field' ? [[row.choice.fieldId, shapeName(row.shape, nameKey) || 'a shape'] as const] : [],
      ),
    )
    return fields.flatMap((field) =>
      field.boundary
        ? [{ name: field.name, boundary: field.boundary, updatedBy: updatedBy.get(field.id) ?? null }]
        : [],
    )
  })

  const references = $derived<Reference[]>(systems.map((system) => ({ name: system.name, shape: system })))

  // The last file read here or on a field's shape page is kept in the browser (lib/outlines/kept.ts),
  // to finish here what was started there, or the other way round: it's matched as the page opens
  const groupId = page.props.auth.group?.id ?? null
  /** When the file shown was read */
  let readTime = $state<number | null>(null)
  /** Whether the file shown is kept (a file of one shape isn't, nor one too big to keep) */
  let fileKept = $state(false)
  onMount(() => {
    const kept = readKept(groupId)
    if (kept) {
      fileKept = true
      loadShowing(kept, kept.savedAt)
    }
  })

  // Shapes that can't be saved have no row (nor a soil survey, nor a place on the map): a county
  // file's thousands are one line saying why
  let unusable = $state<KeptShape[]>([])
  const UNUSABLE_LISTED = 200
  // Only a file's first shapes are read: even a large operation has at most a few hundred fields, and
  // a file of thousands (a county's or a state's field boundaries) is better cut down where it came from
  const MAX_SHAPES = 1000
  let discarded = $state(0)
  const OTHERS_LISTED = 200

  // What's in progress (reading the file, matching its shapes), shown with a spinner. Each step
  // waits for a frame first, so the message is on screen before the work holds up the page.
  let busy = $state<string | null>(null)
  const painted = () => new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve)))
  const count = (n: number, one: string, many: string) => `${n.toLocaleString('en-US')} ${n === 1 ? one : many}`

  async function readFile(event: Event) {
    const input = event.currentTarget as HTMLInputElement
    const file = input.files?.[0]
    input.value = ''
    if (!file) return
    fileError = null
    busy = `Reading ${file.name}…`
    await painted()
    const read = await readOutlineFileResult(file)
    if ('error' in read) {
      busy = null
      fileError = read.error
      return
    }
    const { result } = read
    // This file is kept in place of the last one
    if (result.shapes.length > 1) fileKept = keepShapes(groupId, { fileName: file.name, ...result })
    else {
      forgetKept(groupId)
      fileKept = false
    }
    await loadShowing({ fileName: file.name, ...result }, Date.now())
  }

  async function loadShowing(file: Parameters<typeof load>[0], readAtTime: number) {
    busy = `Matching ${count(Math.min(file.shapes.length, MAX_SHAPES), 'shape', 'shapes')} to your fields and irrigation systems…`
    await painted()
    try {
      load(file)
      readTime = readAtTime
      matched = edits(rows)
    } finally {
      busy = null
    }
  }

  // Forget this file: it's no longer kept, and the page is back to choosing one
  function forgetShapes() {
    forgetKept(groupId)
    fileName = null
    readTime = null
    fileKept = false
    rows = []
    unusable = []
    keys = []
    nameKey = null
    skipped = 0
    discarded = 0
    selected = null
    matched = ''
  }

  function load(file: { fileName: string; nameKey: string | null; skipped: number; shapes: KeptShape[] }) {
    const shapes = file.shapes.slice(0, MAX_SHAPES)
    fileName = file.fileName
    skipped = file.skipped
    discarded = file.shapes.length - shapes.length
    keys = [...new Set(shapes.flatMap((shape) => Object.keys(shape.properties)))]
    nameKey = file.nameKey
    unusable = shapes.filter((shape) => shape.problems.length || !shape.boundary)
    startRows(shapes.filter((shape): shape is ImportedShape => !shape.problems.length && shape.boundary !== null))
    fileKey++
  }

  function startRows(shapes: ImportedShape[]) {
    const suggest = systemSuggester(systems)
    const named = shapes.map((shape) => ({
      shape,
      name: shapeName(shape, nameKey),
      systemId: suggest(shape.boundary),
    }))
    const choices = initialChoices(
      named.map(({ name, systemId, shape }) => ({
        name,
        systemId,
        problems: shape.problems,
        boundary: shape.boundary,
      })),
      fields,
    )
    rows = named.map(
      ({ shape, name, systemId }, index) =>
        new ImportRow(shape, {
          systemId,
          choice: choices[index].choice,
          same: choices[index].same,
          name: name || `Field ${index + 1}`,
          soilTypeId: default_soil_type_id ?? soil_types[0]?.id,
        }),
    )
    selected = null
    surveyNewRows()
  }

  // A different name attribute renames the shapes: the cards stay as they are (a name the grower
  // typed for a new field too), re-sorted by the new names; nothing is matched again
  function changeNameKey(key: string) {
    nameKey = key || null
    rows.forEach((row, index) => {
      if (!row.nameEdited) row.name = shapeName(row.shape, nameKey) || `Field ${index + 1}`
    })
  }

  // The soil survey's main soil for each new field, one at a time, until the grower picks one. A call
  // while a run is going (a row made new, another file) has the run start over once it's through, so
  // rows behind it aren't missed. Each shape's answer is kept (null: none, or the survey couldn't be
  // reached), so a shape skipped and made new again doesn't ask twice.
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

  // The cards in order: by name, or north to south (by the shape's center)
  let cardOrder = $state<'name' | 'north'>('north')
  const titleOf = (row: ImportRow) => shapeName(row.shape, nameKey) || 'Unnamed shape'
  const cards = $derived.by(() => {
    const carded = rows.flatMap((row, index) => (row.carded ? [{ row, index }] : []))
    return cardOrder === 'name'
      ? carded.toSorted((a, b) => titleOf(a.row).localeCompare(titleOf(b.row), undefined, { numeric: true }))
      : carded
          .map((card) => ({ card, latitude: boundaryCenter(card.row.shape.boundary)[1] }))
          .toSorted((a, b) => b.latitude - a.latitude)
          .map(({ card }) => card)
  })

  // The shapes without a card, nearest the operation's systems first. Each shape's distance is worked
  // out once (null with no systems), not again for another name attribute.
  type OtherRow = {
    index: number
    name: string
    acres: number
    meters: number | null
    shape: ImportedShape
    /** "Already East 40's shape" */
    already: string | null
  }
  const nearest = new WeakMap<object, number | null>()
  function nearestM(shape: ImportedShape) {
    if (!nearest.has(shape)) {
      nearest.set(shape, nearestSystemM(shape.boundary, systems))
    }
    return nearest.get(shape) ?? null
  }
  const others = $derived(
    rows.flatMap((row, index): OtherRow[] =>
      row.carded
        ? []
        : [
            {
              index,
              name: shapeName(row.shape, nameKey),
              acres: row.shape.acres,
              meters: nearestM(row.shape),
              shape: row.shape,
              already: row.same ? `Already ${alreadyWhose(row)}` : null,
            },
          ],
    ),
  )
  let othersSort = $state<{ key: string; direction: 'asc' | 'desc' } | null>({ key: 'distance', direction: 'asc' })
  const otherColumns = $derived<Column<OtherRow>[]>([
    {
      key: 'name',
      label: 'Name',
      value: (row) => row.name || null,
      text: (row) => row.name || 'Unnamed shape',
      searchable: true,
      wrap: true,
    },
    {
      key: 'area',
      label: 'Area',
      value: (row) => row.acres,
      text: (row) => formatArea(units, row.acres),
      align: 'right',
      firstDirection: 'desc',
    },
    {
      key: 'distance',
      label: 'Nearest\nsystem',
      value: (row) => row.meters,
      text: (row) => (row.meters === null ? '' : formatReach(row.meters, units.system)),
      align: 'right',
    },
    { key: 'add', label: '', value: () => null, sortable: false },
  ])
  // The search also finds the attributes not shown, so a CLU number finds its shape
  const otherAttributes = (row: OtherRow) =>
    keys.filter((key) => key !== nameKey).map((key) => String(attributeValue(row.shape.properties[key]) ?? ''))

  /** The skipped shapes' summary: those already a field's shape, and the rest */
  function skippedSummary(total: number, same: number) {
    const rest = total - same
    const parts = [
      same === 1
        ? "1 shape is already a field's shape"
        : same
          ? `${count(same, '', 'shapes are')} already your fields' shapes`
          : '',
      rest
        ? `${count(rest, 'shape matches', 'shapes match')} no field and ${rest === 1 ? "isn't" : "aren't"} under your irrigation systems`
        : '',
    ].filter(Boolean)
    return `${parts.join(', and ')}, so ${total === 1 ? "it's" : "they're"} skipped. Add (+) any you want to import.`
  }

  /** Gives a shape a card, as an update of the field whose shape it already is, else as a new field (asking the soil survey), and shows it */
  function add(index: number) {
    rows[index].carded = true
    setKind(index, rows[index].same ? 'field' : 'new')
    pick(index)
  }

  // Update picks the field last chosen, else the nearest no other shape updates
  function setKind(index: number, kind: Choice['kind']) {
    const row = rows[index]
    if (kind === 'field') {
      const taken = (id: number) =>
        rows.some((other, i) => i !== index && other.choice.kind === 'field' && other.choice.fieldId === id)
      const candidates = fieldsFor(row.shape)
      const id = row.lastFieldId ?? (candidates.find((c) => !taken(c.id)) ?? candidates[0])?.id
      if (id === undefined) return
      row.choice = { kind: 'field', fieldId: id }
    } else {
      row.choice = { kind }
    }
    if (kind === 'new') surveyNewRows()
  }

  function chooseField(index: number, id: number) {
    rows[index].choice = { kind: 'field', fieldId: id }
    rows[index].lastFieldId = id
  }

  // Shapes going in that overlap each other, by row
  const shapeOverlaps = $derived.by(() => {
    const byRow: Record<number, { other: number; share: number }[]> = {}
    const outlines = included.map(({ row, index }) => ({ id: index, boundary: row.shape.boundary }))
    for (const { a, b, share } of overlappingPairs(outlines)) {
      ;(byRow[a.id] ??= []).push({ other: b.id, share })
      ;(byRow[b.id] ??= []).push({ other: a.id, share })
    }
    return byRow
  })

  type Warning = { text: string; update?: ExistingField }
  /** Under the field to update: whether its shape changes */
  function updateHint(row: ImportRow, field: (typeof fields)[number]) {
    const same = sameAs(row.shape.boundary, field)
    if (!same) return 'Replaces its shape'
    return same.meters < 0.5
      ? 'Already its shape: nothing changes'
      : `Already its shape, within ${formatReach(same.meters, units.system)}`
  }

  /** What a card warns of: fields its shape overlaps (but the one it updates), other shapes going in it overlaps, and an update far from the field's shape now */
  function warningsFor(row: ImportRow, index: number): Warning[] {
    if (row.choice.kind === 'skip') return []
    const target = row.choice.kind === 'field' ? row.choice.fieldId : null
    const warnings: Warning[] = fieldsFor(row.shape)
      .filter(({ id, share }) => share >= OVERLAP_WARNING_SHARE && id !== target)
      .map(({ id, share }) => {
        const field = fieldsById.get(id)!
        return { text: `Overlaps ${field.name} (${sharePercent(share)})`, update: field }
      })
    for (const { other, share } of shapeOverlaps[index] ?? [])
      warnings.push({ text: `Overlaps the shape ${titleOf(rows[other])} (${sharePercent(share)})` })
    if (target !== null) {
      const field = fieldsById.get(target)
      const candidate = fieldsFor(row.shape).find(({ id }) => id === target)
      if (field?.boundary && candidate && candidate.share < SHOWN_SHARE)
        warnings.push({ text: `${reach(candidate.meters)} from ${field.name}'s shape now` })
    }
    return warnings
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

  // A shape picked on the map, or added: its card, or for a skipped shape its row in the skipped
  // shapes' table (opened, the row drawn even if the search or limit would leave it out), scrolled to
  let othersOpen = $state(false)
  async function pick(index: number) {
    selected = index
    if (!rows[index].carded) othersOpen = true
    await tick()
    const id = rows[index].carded ? `shape-${index}` : `other-${index}`
    document.getElementById(id)?.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
  }
</script>

<svelte:head><title>Import field shapes · WISP</title></svelte:head>

<div class="space-y-1">
  <Link href={setup.show()} class="text-sm text-brand-600 hover:underline">← Setup</Link>
  <h1 class="text-2xl font-semibold">Import field shapes</h1>
  <p class="text-sm text-ink-muted">
    Import your field shapes to draw your fields on the map and measure their area; the soil survey under each also
    suggests its soil. The water balance doesn't use the shapes themselves. You may already have them: your FSA field
    boundaries (Common Land Units) from your county office, or boundaries you export from John Deere Operations Center,
    Climate FieldView or Google Earth. Choose a zipped shapefile (.zip with the .shp, .dbf and .prj), GeoJSON, or KML or
    KMZ. The file stays on your computer: WISP sends only the shapes you import, and keeps the file's shapes in this
    browser for a week so you can come back to them.
  </p>
</div>

{#snippet filePicker(label: string, variant: 'primary' | 'secondary')}
  <label
    class="inline-flex cursor-pointer items-center rounded-md text-sm font-medium focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-brand-500
      {variant === 'primary'
      ? 'bg-brand-600 px-4 py-2 text-white hover:bg-brand-700 dark:text-surface'
      : 'border border-line bg-surface-raised px-3 py-1 text-ink hover:bg-surface'}
      {busy ? 'pointer-events-none opacity-60' : ''}"
  >
    {label}
    <input type="file" accept={ACCEPT} class="sr-only" disabled={!!busy} onchange={readFile} />
  </label>
{/snippet}

{#if fileName}
  <!-- The file shown, kept in this browser for a week: another can take its place, or it can go -->
  <div class="flex flex-wrap items-center gap-x-3 gap-y-2 text-sm">
    <span>
      {`Shapes from ${fileName}`}{#if readTime !== null}<span class="text-ink-muted">
          {` (${readAt(readTime)})`}
        </span>{/if}
    </span>
    {@render filePicker('Choose another file', 'secondary')}
    <Button type="button" variant="ghost" class="px-3 py-1" disabled={!!busy} onclick={forgetShapes}>
      Forget this file
    </Button>
  </div>
{:else if !busy}
  <div class="flex flex-wrap items-center gap-3">
    {@render filePicker('Choose a file', 'primary')}
  </div>
{/if}
<!-- Always there, so screen readers announce its text when it changes -->
<p class="flex items-center gap-2 text-sm {busy ? 'pt-2' : 'sr-only'}" role="status">
  {#if busy}<Spinner />{busy}{/if}
</p>
{#if fileError}<p class="text-sm text-status-irrigate-ink" role="alert">{fileError}</p>{/if}

{#if unusable.length}
  <details class="rounded-lg border border-line bg-surface-raised p-4 text-sm">
    <summary class="cursor-pointer">
      <span class="text-status-irrigate-ink">
        {`${unusable.length.toLocaleString('en-US')} ${unusable.length === 1 ? "shape can't" : "shapes can't"} be used for a field`}
      </span>{`: ${unusableSummary(unusable)}.`}
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

{#if discarded}
  <p class="text-sm text-status-caution-ink" role="alert">
    {`This file has ${count(discarded + MAX_SHAPES, 'shape', 'shapes')}. WISP read the first ${MAX_SHAPES.toLocaleString('en-US')} and discarded the other ${discarded.toLocaleString('en-US')}; to import fields among those, export a file of just your farm's fields.`}
  </p>
{/if}

{#if rows.length}
  <div class="space-y-3">
    <p class="text-sm" aria-live="polite">
      {rows.length === 1 ? 'One shape' : `${rows.length.toLocaleString('en-US')} shapes`}{unusable.length
        ? ' that can be used'
        : ''}{skipped ? `, and ${skipped} ${skipped === 1 ? 'point or line' : 'points or lines'} left out` : ''}. Each
      updates the field of the same name or whose shape it covers, or becomes a new field under the irrigation system
      it's under; one that's already its field's shape is skipped. Change any of them beside the map.
    </p>
  </div>

  <!-- Side by side on a wide screen, as tall as the window: picking a shape on the map scrolls only
       the cards, so the map stays in view -->
  <div class="grid grid-cols-[minmax(0,1fr)] gap-4 lg:h-[calc(100dvh-2rem)] lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
    <ImportMap
      shapes={rows.map((row) => ({
        boundary: row.shape.boundary,
        label: shapeName(row.shape, nameKey),
        state: row.choice.kind,
        detail: mapDetail(row),
      }))}
      fields={fieldsOnMap}
      {references}
      {selected}
      {fileKey}
      onselect={pick}
      fill
    />

    <Form
      id="outline-import-form"
      action={outlineImport()}
      class="flex min-h-0 min-w-0 flex-col gap-3"
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
            <input type="hidden" name="outline_import[rows][{position}][system_id]" value={row.systemId ?? ''} />
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

        <h2 class="font-medium">Fields to import</h2>

        <div class="min-h-0 flex-1 space-y-3 overflow-y-auto pr-2">
          {#if keys.length > 1}
            <div>
              <SelectField
                label="Names from"
                value={nameKey ?? ''}
                options={[{ value: '', label: 'No names' }, ...keys.map((key) => ({ value: key, label: key }))]}
                onchange={(event) => changeNameKey((event.currentTarget as HTMLSelectElement).value)}
                info="field.shape_names"
              />
            </div>
          {/if}

          <div class="space-y-2">
            <SegmentedChoice
              legend="Sort by"
              name="card-order"
              showLegend
              options={[
                { value: 'name', label: 'Name' },
                { value: 'north', label: 'N–S' },
              ]}
              value={cardOrder}
              onchange={(order) => (cardOrder = order)}
            />
          </div>

          <ol class="space-y-2">
            {#each cards as { row, index } (row)}
              {@const title = titleOf(row)}
              {@const updating = row.choice.kind === 'field' ? fieldsById.get(row.choice.fieldId) : undefined}
              {@const warnings = warningsFor(row, index)}
              <li
                id="shape-{index}"
                class="rounded-lg border bg-surface-raised p-3 text-sm
                    {selected === index ? 'border-brand-500' : 'border-line'}"
              >
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <div class="flex min-w-0 items-baseline gap-x-2">
                    <button
                      type="button"
                      class="truncate font-medium hover:underline"
                      onclick={() => (selected = index)}
                    >
                      {title}
                    </button>
                    <span class="shrink-0 text-ink-muted">{formatArea(units, row.shape.acres)}</span>
                  </div>
                  <SegmentedChoice
                    legend="Where {title} goes"
                    name="shape-{index}-choice"
                    options={CHOICES.map((option) => ({
                      value: option.kind,
                      label: option.label,
                      color: option.color,
                      disabled: option.kind === 'field' && !fields.length,
                    }))}
                    value={row.choice.kind}
                    onchange={(kind) => setKind(index, kind)}
                  />
                </div>
                {#if row.shape.notes.length}<p class="mt-1 text-xs text-ink-muted">{shapeNotes(row.shape)}</p>{/if}

                {#if row.choice.kind === 'field'}
                  <div class="mt-2">
                    <SelectField
                      label="Field to update"
                      id="shape-{index}-field"
                      value={String(row.choice.fieldId)}
                      options={fieldOptionsFor(row.shape)}
                      onchange={(event) => chooseField(index, Number((event.currentTarget as HTMLSelectElement).value))}
                      error={usedBy[index] !== undefined
                        ? `Also chosen for ${titleOf(rows[usedBy[index]])}`
                        : rowError(errors, index, 'field_id')}
                      hint={updating?.boundary ? updateHint(row, updating) : undefined}
                    />
                  </div>
                {:else if row.choice.kind === 'new'}
                  <div class="mt-2 grid gap-2 sm:grid-cols-2">
                    <div class="sm:col-span-2">
                      <TextField
                        label="New field's name"
                        name="shape-{index}-name"
                        bind:value={row.name}
                        oninput={() => (row.nameEdited = true)}
                        error={row.name.trim() ? rowError(errors, index, 'name') : 'Give the field a name'}
                      />
                    </div>
                    <SelectField
                      label="Irrigation system"
                      id="shape-{index}-system"
                      value={row.systemId === null ? '' : String(row.systemId)}
                      options={systemOptionsFor(row.shape)}
                      onchange={(event) => {
                        const value = (event.currentTarget as HTMLSelectElement).value
                        row.systemId = value ? Number(value) : null
                      }}
                      error={row.systemId === null
                        ? 'Choose the system that waters it'
                        : rowError(errors, index, 'system')}
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
                      hint={row.soil === 'survey' ? 'From the soil survey' : undefined}
                      error={rowError(errors, index, 'soil_type')}
                    />
                  </div>
                {/if}

                {#if warnings.length}
                  <ul class="mt-2 space-y-1 text-status-caution-ink">
                    {#each warnings as warning, position (position)}
                      <li class="flex flex-wrap items-center gap-x-2">
                        <span>{warning.text}</span>
                        {#if warning.update}
                          <button
                            type="button"
                            class="underline underline-offset-2 hover:text-ink"
                            onclick={() => chooseField(index, warning.update!.id)}
                          >
                            Update {warning.update.name} instead
                          </button>
                        {/if}
                      </li>
                    {/each}
                  </ul>
                {/if}
                {#if rowError(errors, index, 'boundary')}
                  <p class="mt-2 text-status-irrigate-ink">The shape {rowError(errors, index, 'boundary')}</p>
                {/if}
              </li>
            {/each}
          </ol>

          {#if others.length > sameCount}
            <!-- Shapes under no system need one first: the system map shows this file's shapes when it's kept -->
            <p class="text-sm text-ink-muted">
              {`To import ${others.length - sameCount === 1 ? 'the shape' : 'shapes'} with no irrigation system under ${others.length - sameCount === 1 ? 'it' : 'them'}, set up ${others.length - sameCount === 1 ? 'its system' : 'their systems'} first: `}<Link
                href={systemRoutes.new()}
                class="text-brand-600 underline"
              >
                add an irrigation system
              </Link>{fileKept
                ? `, and this file's shapes are on its map to place it on. Then come back here: the file is kept in this browser for a week.`
                : ', then read this file here again.'}
            </p>
          {/if}
          {#if others.length}
            <!-- Enter in its search mustn't save the import -->
            <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
            <details
              bind:open={othersOpen}
              class="rounded-lg border border-line bg-surface-raised p-3 text-sm"
              onkeydown={(event) => {
                if (event.key === 'Enter' && event.target instanceof HTMLInputElement) event.preventDefault()
              }}
            >
              <summary class="cursor-pointer">
                {skippedSummary(others.length, sameCount)}
              </summary>
              <div class="mt-3">
                <DataTable
                  rows={others}
                  columns={otherColumns}
                  searchAlso={otherAttributes}
                  bind:sort={othersSort}
                  rowKey={(row) => row.index}
                  label="Skipped shapes from {fileName}"
                  searchPlaceholder="Search the skipped shapes"
                  maxHeight="22rem"
                  limit={OTHERS_LISTED}
                  selected={(row) => row.index === selected}
                  showSelected
                  rowId={(row) => `other-${row.index}`}
                  nowrap
                >
                  {#snippet cell(row, column)}
                    {#if column.key === 'add'}
                      <Button
                        type="button"
                        variant="secondary"
                        class="px-2 py-0 text-base/6"
                        aria-label="Add {row.name || 'Unnamed shape'}"
                        title="Add to the fields to import"
                        onclick={() => add(row.index)}
                      >
                        +
                      </Button>
                    {:else if column.key === 'name'}
                      <button
                        type="button"
                        class="text-left font-medium wrap-anywhere hover:underline"
                        aria-current={row.index === selected ? 'true' : undefined}
                        onclick={() => (selected = row.index)}
                      >
                        {row.name || 'Unnamed shape'}
                      </button>{#if row.already}<span class="block text-xs text-ink-muted">{row.already}</span>{/if}
                    {:else}
                      {column.text ? column.text(row) : (column.value(row) ?? '')}
                    {/if}
                  {/snippet}
                </DataTable>
              </div>
            </details>
          {/if}
        </div>

        <div class="space-y-2 border-t border-line pt-3">
          <label class="flex items-start gap-2 text-sm">
            <input type="checkbox" class="mt-0.5 rounded-sm" bind:checked={useArea} />
            <span>Set existing fields' area from their shapes (seasons that have ended keep theirs)</span>
          </label>
          {#if errors.rows}<p class="text-sm text-status-irrigate-ink">{[errors.rows].flat()[0]}</p>{/if}
          <div class="flex flex-wrap items-center gap-3">
            <Button type="submit" disabled={processing || !included.length || unready.length > 0}>
              Save {included.length === 1 ? 'the shape' : `${included.length} shapes`}
            </Button>
            <span class="text-sm text-ink-muted">
              {counts.existing} to update, {counts.added} new
            </span>
            <Link href={setup.show()} class="text-sm text-brand-600 hover:underline">Cancel</Link>
          </div>
        </div>
      {/snippet}
    </Form>
  </div>
{/if}
