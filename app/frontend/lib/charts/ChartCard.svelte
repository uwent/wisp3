<script lang="ts">
  import type { Snippet } from 'svelte'

  import InfoTip from '../components/InfoTip.svelte'
  import Chart from './Chart.svelte'
  import type { ChartView, EChartsCoreOption } from './echarts'
  import type { Palette } from './palette'
  import { formatDate } from '../dates'

  export type ChartTable = {
    columns: string[]
    rows: { date: string; forecast: boolean; values: (string | null)[] }[]
  }

  // A chart in a card: its title, then (top right) a reset button once the chart has been zoomed
  // or had series toggled, and an (i) explaining what it shows. Below it, a closed "Summary and
  // data": the chart in words (also its text alternative) and its daily values as a table.
  let {
    title,
    info,
    build,
    height = '12rem',
    summary,
    table,
    unit,
    subtitle,
  }: {
    title: string
    info: string
    build: (palette: Palette, view?: ChartView) => EChartsCoreOption
    height?: string
    summary: string
    table: () => ChartTable
    unit: string
    subtitle?: Snippet
  } = $props()

  let chart: Chart | undefined = $state()
  let modified = $state(false)
  let open = $state(false)
  // Built only once opened: a season of rows for every chart would slow the page for nothing
  const rows = $derived(open ? table() : null)
</script>

<div class="rounded-lg border border-line bg-surface-raised p-3">
  <div class="flex items-start justify-between gap-2">
    <h3 class="text-sm font-medium">{title} {@render subtitle?.()}</h3>
    <div class="-mt-1 -mr-1 flex shrink-0 items-center">
      {#if modified}
        <button
          type="button"
          class="inline-flex size-6 items-center justify-center rounded-full text-ink-muted hover:bg-surface hover:text-ink focus-visible:outline-2 focus-visible:outline-brand-600"
          aria-label="Reset {title} chart"
          title="Reset chart"
          onclick={() => chart?.reset()}
        >
          <svg
            viewBox="0 0 24 24"
            class="size-4"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <path d="M3 12a9 9 0 1 0 3-6.7L3 8" />
            <path d="M3 3v5h5" />
          </svg>
        </button>
      {/if}
      <InfoTip text={info} label="About the {title} chart" />
    </div>
  </div>
  <Chart bind:this={chart} bind:modified {height} label="{title}. {summary}" {build} />
  <details bind:open class="mt-1 text-xs">
    <summary class="cursor-pointer text-brand-600 hover:underline">Summary and data</summary>
    <p class="mt-1 text-ink-muted">{summary}</p>
    {#if rows}
      <!-- Focusable so keyboard users can scroll it (WCAG 2.1.1) -->
      <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
      <div
        class="mt-2 max-h-64 overflow-auto rounded border border-line"
        tabindex="0"
        role="region"
        aria-label="{title} by day"
      >
        <table class="w-full tabular-nums">
          <caption class="sr-only">{title} by day, newest first ({unit})</caption>
          <thead class="sticky top-0 bg-surface-raised text-ink-muted">
            <tr class="text-right">
              <th scope="col" class="px-2 py-1 text-left font-medium">Date</th>
              {#each rows.columns as column (column)}
                <th scope="col" class="px-2 py-1 font-medium">{column} ({unit})</th>
              {/each}
            </tr>
          </thead>
          <tbody class="divide-y divide-line">
            {#each rows.rows as row (row.date)}
              <tr class="text-right {row.forecast ? 'bg-surface text-ink-muted' : ''}">
                <th scope="row" class="px-2 py-0.5 text-left font-normal">
                  {formatDate(row.date, { weekday: true })}{row.forecast ? ' (forecast)' : ''}
                </th>
                {#each row.values as value, i (i)}
                  <td class="px-2 py-0.5">{value ?? '–'}</td>
                {/each}
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  </details>
</div>
