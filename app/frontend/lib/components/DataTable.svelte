<script lang="ts" generics="T">
  import type { Snippet } from 'svelte'

  import { cellText, matchesQuery, sortRows, type Column, type SortDirection } from '../table'

  // A table that sorts by any column (click a heading; again to reverse) and filters rows by a
  // search box over the searchable columns. Cells show cellText unless a `cell` snippet renders them.

  let {
    rows,
    columns,
    rowKey,
    label,
    searchPlaceholder = 'Search',
    sort = $bindable<{ key: string; direction: SortDirection } | null>(null),
    cell,
    rowClass,
    empty = 'Nothing here yet.',
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
  } = $props()

  let query = $state('')

  const searchable = $derived(columns.filter((column) => column.searchable))
  const filtered = $derived(
    query.trim() ? rows.filter((row) => matchesQuery(query, searchable.map((column) => cellText(column, row)))) : rows,
  )
  const sortColumn = $derived(sort && columns.find((column) => column.key === sort!.key))
  const shown = $derived(sortColumn && sort ? sortRows(filtered, sortColumn.value, sort.direction) : filtered)

  function toggle(column: Column<T>) {
    const first = column.firstDirection ?? 'asc'
    sort = sort?.key === column.key ? { key: column.key, direction: sort.direction === 'asc' ? 'desc' : 'asc' } : { key: column.key, direction: first }
  }

  const alignClass = { left: 'text-left', right: 'text-right', center: 'text-center' }
  const ariaSort = (column: Column<T>) =>
    sort?.key === column.key ? (sort.direction === 'asc' ? 'ascending' : 'descending') : column.sortable === false ? undefined : 'none'
</script>

<div class="space-y-2">
  <div class="flex flex-wrap items-center justify-between gap-2">
    {#if searchable.length}
      <input
        type="search"
        bind:value={query}
        placeholder={searchPlaceholder}
        aria-label={searchPlaceholder}
        class="w-full max-w-xs rounded-md shadow-sm focus:border-brand-500 focus:ring-brand-500 sm:text-sm
          border-line bg-surface-raised"
      />
    {/if}
    <span class="text-xs text-ink-muted" role="status">{query.trim() ? `${shown.length} of ${rows.length} shown` : ''}</span>
  </div>

  <div class="overflow-x-auto rounded-lg border border-line bg-surface-raised">
    <table class="w-full text-sm" aria-label={label}>
      <thead class="border-b border-line text-xs text-ink-muted">
        <tr>
          {#each columns as column (column.key)}
            <th scope="col" class="px-3 py-2 font-medium whitespace-nowrap {alignClass[column.align ?? 'left']}" aria-sort={ariaSort(column)}>
              {#if column.sortable === false}
                {column.label}
              {:else}
                <button type="button" class="inline-flex items-center gap-1 hover:text-ink" onclick={() => toggle(column)}>
                  {column.label}
                  <span aria-hidden="true" class="w-2 {sort?.key === column.key ? 'text-ink' : 'opacity-0'}">
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
              <td class="px-3 py-2 {alignClass[column.align ?? 'left']}">
                {#if cell}{@render cell(row, column)}{:else}{cellText(column, row)}{/if}
              </td>
            {/each}
          </tr>
        {:else}
          <tr>
            <td colspan={columns.length} class="px-3 py-6 text-center text-ink-muted">{query.trim() ? 'No matches.' : empty}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
</div>
