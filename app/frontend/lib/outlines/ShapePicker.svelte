<script lang="ts">
  import type { Snippet } from 'svelte'

  import Button from '@/lib/components/Button.svelte'
  import DataTable from '@/lib/components/DataTable.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
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
  } from './picker'

  // One field's shape from a file's (PLAN.md Phase 8 G.10): a file just read, or the shapes kept from
  // the last one. A table of them with every attribute as a column to sort and search by, the field's
  // likely ones first; shapes that can't be saved are hidden until asked for. Thousands of shapes (a
  // county file) draw the first few hundred, and the search narrows them.
  let {
    shapes,
    fileName,
    nameKey = $bindable(),
    savedAt = null,
    skipped = 0,
    context,
    systemLabel,
    open = $bindable(true),
    onpick,
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
    open?: boolean
    onpick: (shape: PickerShape) => void
    onforget?: () => void
    /** Below the table (a link to import them all) */
    children?: Snippet
  } = $props()

  const ROW_LIMIT = 200
  const units = $derived(currentUnits())
  const id = $props.id()

  const keys = $derived(attributeKeys(shapes))
  const rows = $derived(pickerRows(shapes, nameKey, context))
  const usable = $derived(rows.filter((row) => row.usable))
  const unusableCount = $derived(rows.length - usable.length)
  let showUnusable = $state(false)
  // With none that can be saved, those that can't are shown, to say why
  const listed = $derived(showUnusable || !usable.length ? rows : usable)

  const count = (n: number) => n.toLocaleString('en-US')
  const label = (row: PickerRow) => row.name || `Shape ${row.index + 1}`
  const statusText = (row: PickerRow) => rowNotes(row, systemLabel).join('. ')

  const columns = $derived<Column<PickerRow>[]>([
    {
      key: 'name',
      label: nameKey ?? 'Name',
      value: (row) => row.name || null,
      text: label,
      searchable: true,
      pin: 'left',
    },
    {
      key: 'area',
      label: 'Area',
      value: (row) => row.shape.acres,
      text: (row) => formatArea(units, row.shape.acres),
      align: 'right',
      firstDirection: 'desc',
    },
    { key: 'status', label: 'Notes', value: statusText, searchable: true },
    ...keys
      .filter((key) => key !== nameKey)
      .map((key) => ({
        key: `attribute:${key}`,
        label: key,
        value: (row: PickerRow) => attributeValue(row.shape.properties[key]),
        searchable: true,
      })),
  ])
</script>

<section class="space-y-3 rounded-lg border border-line bg-surface-raised p-4 text-sm" aria-labelledby="{id}-heading">
  <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
    <h2 id="{id}-heading" class="font-medium">
      {`Shapes from ${fileName}: pick one for ${context.field.name}`}{savedAt === null ? '' : ` (${readAt(savedAt)})`}
    </h2>
    <div class="flex items-center gap-1">
      <Button
        type="button"
        variant="ghost"
        class="px-2 py-1"
        aria-expanded={open}
        aria-controls="{id}-body"
        onclick={() => (open = !open)}>{open ? 'Hide the shapes' : 'Show the shapes'}</Button
      >
      {#if onforget}
        <Button type="button" variant="ghost" class="px-2 py-1" onclick={onforget}>Forget these shapes</Button>
      {/if}
    </div>
  </div>

  <div id="{id}-body" class="space-y-3" hidden={!open}>
    <p class="text-ink-muted">
      {`${count(shapes.length)} ${shapes.length === 1 ? 'shape' : 'shapes'}`}{skipped
        ? `, and ${count(skipped)} ${skipped === 1 ? 'point or line' : 'points or lines'} left out`
        : ''}{unusableCount ? `; ${count(unusableCount)} can't be used for a field` : ''}. Sort or search by any column
      to find this field's.
    </p>
    <div class="flex flex-wrap items-end gap-x-6 gap-y-2">
      {#if keys.length > 1}
        <div class="w-full max-w-xs">
          <SelectField
            label="Names from"
            id="{id}-names"
            value={nameKey ?? ''}
            options={[{ value: '', label: 'No names' }, ...keys.map((key) => ({ value: key, label: key }))]}
            onchange={(event) => (nameKey = (event.currentTarget as HTMLSelectElement).value || null)}
            hint="The file's attribute that holds each field's name"
          />
        </div>
      {/if}
      {#if unusableCount && usable.length}
        <label class="flex items-center gap-2 pb-2">
          <input type="checkbox" class="rounded" bind:checked={showUnusable} />
          <span>Show the {count(unusableCount)} that can't be used</span>
        </label>
      {/if}
    </div>

    <DataTable
      rows={listed}
      {columns}
      rowKey={(row) => row.index}
      label="Shapes from {fileName}"
      searchPlaceholder="Search the shapes"
      rowClass={(row) => (row.usable ? '' : 'text-ink-muted')}
      maxHeight="24rem"
      limit={ROW_LIMIT}
      nowrap
    >
      {#snippet cell(row, column)}
        {#if column.key === 'name'}
          {#if row.usable}
            <button
              type="button"
              class="font-medium text-brand-600 underline underline-offset-2 hover:text-brand-700"
              onclick={() => onpick(row.shape)}>{label(row)}</button
            >
          {:else}
            {label(row)}
          {/if}
        {:else if column.key === 'status'}
          {#if !row.usable}
            <span class="text-status-irrigate-ink">{statusText(row)}</span>
          {:else}
            {#each rowNotes(row, systemLabel) as note, i (i)}{i ? '. ' : ''}<span
                class={i === 0 && row.match ? 'font-medium' : ''}>{note}</span
              >{/each}
          {/if}
        {:else}
          {column.text ? column.text(row) : (column.value(row) ?? '')}
        {/if}
      {/snippet}
    </DataTable>
    {@render children?.()}
  </div>
</section>
