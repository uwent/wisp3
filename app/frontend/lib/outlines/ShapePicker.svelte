<script lang="ts">
  import type { Snippet } from 'svelte'

  import Button from '@/lib/components/Button.svelte'
  import DataTable from '@/lib/components/DataTable.svelte'
  import Dialog from '@/lib/components/Dialog.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import type { Boundary } from '@/lib/boundary'
  import { formatArea } from '@/lib/plantings'
  import type { Column } from '@/lib/table'
  import { currentUnits } from '@/lib/units'

  import { readAt } from './kept'
  import {
    attributeKeys,
    attributeValue,
    type PickerContext,
    type PickerRow,
    type PickerShape,
    pickerRows,
    rowNotes,
    rowTag,
    sameBoundary,
    shapeDistances,
  } from './picker'
  import { formatReach } from './problems'

  // One field's shape from a file's (PLAN.md Phase 8 G.10): a file just read, or the shapes kept from
  // the last one. A card beside the map with a compact table (name, area, distance to the field's
  // system), the field's likely ones first, staying open so each shape picked can be looked at on
  // the map before saving; expanded, a dialog with every attribute as a column to sort and search
  // by, and the shapes that can't be saved when asked for. Thousands of shapes (a county file) draw
  // the first few hundred, and the search narrows them.
  let {
    shapes,
    fileName,
    nameKey = $bindable(),
    savedAt = null,
    skipped = 0,
    context,
    systemLabel,
    current = null,
    onpick,
    onclose,
    onchoose,
    onforget,
    children,
  }: {
    shapes: PickerShape[]
    fileName: string
    nameKey: string | null
    /** When kept shapes were read (ms), for the heading; null for a file just read */
    savedAt?: number | null
    /** Features that aren't polygons, left out */
    skipped?: number
    context: PickerContext
    /** The field's irrigation system, as growers see it */
    systemLabel: string
    /** The shape on the map now, to mark its row */
    current?: Boundary | null
    onpick: (shape: PickerShape) => void
    onclose: () => void
    /** Read another file */
    onchoose: () => void
    onforget?: () => void
    /** In the footer (a link to import them all) */
    children?: Snippet
  } = $props()

  const ROW_LIMIT = 200
  const units = $derived(currentUnits())
  const id = $props.id()

  const keys = $derived(attributeKeys(shapes))
  // The distances are worked out once for the file's shapes, not again for another name attribute
  const distances = $derived(shapeDistances(shapes, context.system))
  const rows = $derived(pickerRows(shapes, nameKey, context, distances))
  const usable = $derived(rows.filter((row) => row.usable))
  const unusableCount = $derived(rows.length - usable.length)
  let showUnusable = $state(false)
  // With none that can be saved, those that can't are shown, to say why
  const compactRows = $derived(usable.length ? usable : rows)
  const expandedRows = $derived(showUnusable || !usable.length ? rows : usable)

  let expanded = $state(false)
  // The row whose shape the map shows now (picked, and not drawn over since)
  const shownIndex = $derived.by(() => {
    if (!current) return null
    const at = current
    return rows.find((row) => row.usable && row.shape.boundary && sameBoundary(row.shape.boundary, at))?.index ?? null
  })

  function pick(row: PickerRow) {
    expanded = false
    onpick(row.shape)
  }

  const count = (n: number) => n.toLocaleString('en-US')
  const label = (row: PickerRow) => row.name || `Shape ${row.index + 1}`
  const distance = (row: PickerRow) => (row.meters === null ? '' : formatReach(row.meters, units.system))

  const summary = $derived(
    `Loaded ${count(shapes.length)} ${shapes.length === 1 ? 'shape' : 'shapes'} from ${fileName}${
      savedAt === null ? '' : ` (${readAt(savedAt)})`
    }.`,
  )
  const leftOut = $derived(
    [
      unusableCount ? `${count(unusableCount)} can't be used for a field` : '',
      skipped ? `${count(skipped)} ${skipped === 1 ? 'point or line was' : 'points or lines were'} left out` : '',
    ]
      .filter(Boolean)
      .join('; '),
  )

  const nameColumn: Column<PickerRow> = {
    key: 'name',
    label: 'Name',
    value: (row) => row.name || null,
    text: label,
    searchable: true,
    pin: 'left',
  }
  const areaColumn = $derived<Column<PickerRow>>({
    key: 'area',
    label: 'Area',
    value: (row) => row.shape.acres,
    text: (row) => formatArea(units, row.shape.acres),
    align: 'right',
    firstDirection: 'desc',
  })
  const distanceColumn = $derived<Column<PickerRow>>({
    key: 'distance',
    label: 'Distance',
    value: (row) => row.meters,
    text: distance,
    align: 'right',
  })
  const compactColumns = $derived<Column<PickerRow>[]>([nameColumn, areaColumn, distanceColumn])
  // Expanded: the notes and every other attribute, searchable too
  const expandedColumns = $derived<Column<PickerRow>[]>([
    nameColumn,
    areaColumn,
    distanceColumn,
    { key: 'status', label: 'Notes', value: (row) => rowNotes(row).join('. '), searchable: true },
    ...keys
      .filter((key) => key !== nameKey)
      .map((key) => ({
        key: `attribute:${key}`,
        label: key,
        value: (row: PickerRow) => attributeValue(row.shape.properties[key]),
        searchable: true,
      })),
  ])
  // The compact table also searches the attributes it doesn't show, so a CLU number finds its shape
  const otherAttributes = (row: PickerRow) =>
    keys.filter((key) => key !== nameKey).map((key) => String(attributeValue(row.shape.properties[key]) ?? ''))

  const rowClass = (row: PickerRow) => (row.usable ? '' : 'text-ink-muted')
  const selected = (row: PickerRow) => row.index === shownIndex
</script>

{#snippet nameCell(row: PickerRow, withTag: boolean)}
  {#if row.usable}
    <button
      type="button"
      class="font-medium text-brand-600 underline underline-offset-2 hover:text-brand-700"
      aria-current={row.index === shownIndex ? 'true' : undefined}
      onclick={() => pick(row)}>{label(row)}</button
    >
  {:else}
    {label(row)}
  {/if}
  {#if withTag && rowTag(row)}
    <span class="block text-xs {row.usable ? 'text-ink-muted' : 'text-status-irrigate-ink'}">{rowTag(row)}</span>
  {/if}
{/snippet}

<section
  class="flex flex-col gap-3 rounded-lg border border-line bg-surface-raised p-4 text-sm"
  aria-labelledby="{id}-heading"
>
  <div class="flex items-start justify-between gap-3">
    <div class="space-y-1">
      <h2 id="{id}-heading" class="text-base font-medium">Field import</h2>
      <p class="text-ink-muted">
        {summary}{leftOut ? ` ${leftOut[0].toUpperCase()}${leftOut.slice(1)}.` : ''} Sort or search to find your field.
      </p>
    </div>
    <button
      type="button"
      class="-mt-1 -mr-1 rounded p-1 text-ink-muted hover:text-ink"
      aria-label="Close the field import"
      onclick={onclose}>✕</button
    >
  </div>

  {#if keys.length > 1}
    <div class="w-full max-w-xs">
      <SelectField
        label="Names from"
        id="{id}-names"
        info="field.shape_names"
        value={nameKey ?? ''}
        options={[{ value: '', label: 'No names' }, ...keys.map((key) => ({ value: key, label: key }))]}
        onchange={(event) => (nameKey = (event.currentTarget as HTMLSelectElement).value || null)}
      />
    </div>
  {/if}

  <DataTable
    rows={compactRows}
    columns={compactColumns}
    searchAlso={otherAttributes}
    rowKey={(row) => row.index}
    label="Shapes from {fileName}"
    searchPlaceholder="Search the shapes"
    {rowClass}
    {selected}
    maxHeight="22rem"
    limit={ROW_LIMIT}
    nowrap
  >
    {#snippet actions()}
      <Button type="button" variant="ghost" class="px-2 py-1" onclick={() => (expanded = true)}>Expand the table</Button
      >
    {/snippet}
    {#snippet cell(row, column)}
      {#if column.key === 'name'}
        {@render nameCell(row, true)}
      {:else}
        {column.text ? column.text(row) : (column.value(row) ?? '')}
      {/if}
    {/snippet}
  </DataTable>

  <!-- At the bottom when the card is stretched to the map's height -->
  <div class="mt-auto flex flex-wrap items-center justify-between gap-x-3 gap-y-2 border-t border-line pt-4">
    <div class="text-xs text-ink-muted">{@render children?.()}</div>
    <div class="flex items-center gap-2">
      <Button type="button" variant="secondary" class="px-3 py-1" onclick={onchoose}>Choose another file</Button>
      {#if onforget}
        <Button type="button" variant="secondary" class="px-3 py-1" onclick={onforget}>Forget these shapes</Button>
      {/if}
    </div>
  </div>
</section>

<Dialog
  bind:open={expanded}
  title="Field import"
  description="{summary} Distance is to {systemLabel}. Sort or search by any column to find your field."
  widest
>
  <div class="space-y-3 text-sm">
    {#if unusableCount && usable.length}
      <label class="flex items-center gap-2">
        <input type="checkbox" class="rounded" bind:checked={showUnusable} />
        <span>Show the {count(unusableCount)} that can't be used</span>
      </label>
    {/if}
    <DataTable
      rows={expandedRows}
      columns={expandedColumns}
      rowKey={(row) => row.index}
      label="All of the shapes from {fileName}"
      searchPlaceholder="Search the shapes"
      {rowClass}
      {selected}
      maxHeight="60dvh"
      limit={ROW_LIMIT}
      nowrap
    >
      {#snippet cell(row, column)}
        {#if column.key === 'name'}
          {@render nameCell(row, false)}
        {:else if column.key === 'status'}
          {#if !row.usable}
            <span class="text-status-irrigate-ink">{rowNotes(row).join('. ')}</span>
          {:else}
            {#each rowNotes(row) as note, i (i)}{i ? '. ' : ''}<span class={i === 0 && row.match ? 'font-medium' : ''}
                >{note}</span
              >{/each}
          {/if}
        {:else}
          {column.text ? column.text(row) : (column.value(row) ?? '')}
        {/if}
      {/snippet}
    </DataTable>
  </div>
</Dialog>
