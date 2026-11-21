<script lang="ts" generics="T">
  import type { Snippet } from 'svelte'

  import { cellText, matchesQuery, sortRows, type Column, type SortDirection } from '../table'

  // A table that sorts by any column (click a heading; again to reverse) and filters rows by a
  // search box over the searchable columns. Cells show cellText unless a `cell` snippet renders them.
  // Too wide for its box, it scrolls sideways with its pinned columns (Column.pin) kept in view. A
  // heading's label can break onto two lines at a newline.

  let {
    rows,
    columns,
    rowKey,
    label,
    searchPlaceholder = 'Search',
    sort = $bindable<{ key: string; direction: SortDirection } | null>(null),
    cell,
    rowClass,
    empty = 'Nothing to show yet.',
    nowrap = false,
  }: {
    rows: T[]
    columns: Column<T>[]
    rowKey: (row: T) => string | number
    /** The table's accessible name */
    label: string
    searchPlaceholder?: string
    sort?: { key: string; direction: SortDirection } | null
    cell?: Snippet<[T, Column<T>]>
    rowClass?: (row: T) => string
    empty?: string
    /** Cells keep to one line, so rows stay one line high and the table scrolls sideways instead */
    nowrap?: boolean
  } = $props()

  let query = $state('')

  const searchable = $derived(columns.filter((column) => column.searchable))
  const filtered = $derived(
    query.trim()
      ? rows.filter((row) =>
          matchesQuery(
            query,
            searchable.map((column) => cellText(column, row)),
          ),
        )
      : rows,
  )
  const sortColumn = $derived(sort && columns.find((column) => column.key === sort!.key))
  const shown = $derived(sortColumn && sort ? sortRows(filtered, sortColumn.value, sort.direction) : filtered)

  function toggle(column: Column<T>) {
    const first = column.firstDirection ?? 'asc'
    sort =
      sort?.key === column.key
        ? { key: column.key, direction: sort.direction === 'asc' ? 'desc' : 'asc' }
        : { key: column.key, direction: first }
  }

  const alignClass = { left: 'text-left', right: 'text-right', center: 'text-center' }

  // Pinned columns: each left one's offset is the width of those pinned before it, measured from
  // the headings. The last left one and the right one draw a rule where the rest scroll under them.
  let widths = $state<Record<string, number>>({})
  const leftPinned = $derived(columns.filter((column) => column.pin === 'left'))
  const lastLeft = $derived(leftPinned.at(-1)?.key)
  function offset(column: Column<T>): number {
    let total = 0
    for (const other of leftPinned) {
      if (other.key === column.key) break
      total += widths[other.key] ?? 0
    }
    return total
  }
  function pinClass(column: Column<T>): string {
    if (column.pin === 'right') return 'sticky right-0 z-10 bg-surface-raised shadow-[inset_1px_0_0_var(--color-line)]'
    if (column.pin !== 'left') return ''
    return `sticky z-10 bg-surface-raised ${column.key === lastLeft ? 'shadow-[inset_-1px_0_0_var(--color-line)]' : ''}`
  }
  const pinStyle = (column: Column<T>) => (column.pin === 'left' ? `left: ${offset(column)}px` : undefined)
  const ariaSort = (column: Column<T>) =>
    sort?.key === column.key
      ? sort.direction === 'asc'
        ? 'ascending'
        : 'descending'
      : column.sortable === false
        ? undefined
        : 'none'
</script>

<div class="space-y-2">
  <div class="flex flex-wrap items-center justify-between gap-2">
    {#if searchable.length}
      <input
        type="search"
        bind:value={query}
        placeholder={searchPlaceholder}
        aria-label={searchPlaceholder}
        class="w-full max-w-xs rounded-md border-line bg-surface-raised shadow-sm focus:border-brand-500 focus:ring-brand-500 sm:text-sm"
      />
    {/if}
    <span class="text-xs text-ink-muted" role="status"
      >{query.trim() ? `${shown.length} of ${rows.length} shown` : ''}</span
    >
  </div>

  <div class="overflow-x-auto rounded-lg border border-line bg-surface-raised">
    <table class="w-full text-sm" aria-label={label}>
      <thead class="border-b border-line text-xs text-ink-muted">
        <tr>
          {#each columns as column (column.key)}
            {@const lines = column.label.split('\n')}
            <th
              scope="col"
              class="px-3 py-2 align-bottom font-medium whitespace-nowrap {alignClass[
                column.align ?? 'left'
              ]} {pinClass(column)}"
              style={pinStyle(column)}
              aria-sort={ariaSort(column)}
              bind:offsetWidth={widths[column.key]}
            >
              {#if column.sortable === false}
                {column.label}
              {:else}
                <!-- The arrow hangs past the label, so the label lines up with the column's cells -->
                <button
                  type="button"
                  class="relative inline-block hover:text-ink {alignClass[column.align ?? 'left']}"
                  aria-label={lines.length > 1 ? lines.join(' ') : undefined}
                  onclick={() => toggle(column)}
                >
                  {#each lines as line, i (i)}{#if i}<br />{/if}{line}{/each}
                  <span
                    aria-hidden="true"
                    class="absolute bottom-0 left-full ml-0.5 {sort?.key === column.key ? 'text-ink' : 'opacity-0'}"
                  >
                    {sort?.key === column.key && sort.direction === 'desc' ? '▾' : '▴'}
                  </span>
                </button>
              {/if}
            </th>
          {/each}
        </tr>
      </thead>
      <tbody class="divide-y divide-line">
        {#each shown as row (rowKey(row))}
          <tr class={rowClass?.(row) ?? ''}>
            {#each columns as column (column.key)}
              <td
                class="px-3 py-2 {alignClass[column.align ?? 'left']} {nowrap ? 'whitespace-nowrap' : ''} {pinClass(
                  column,
                )}"
                style={pinStyle(column)}
              >
                {#if cell}{@render cell(row, column)}{:else}{cellText(column, row)}{/if}
              </td>
            {/each}
          </tr>
        {:else}
          <tr>
            <td colspan={columns.length} class="px-3 py-6 text-center text-ink-muted"
              >{query.trim() ? 'Nothing matches your search.' : empty}</td
            >
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
</div>
