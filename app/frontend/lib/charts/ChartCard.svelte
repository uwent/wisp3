<script lang="ts">
  import type { Snippet } from 'svelte'

  import InfoTip from '../components/InfoTip.svelte'
  import Chart from './Chart.svelte'
  import type { ChartView, EChartsCoreOption } from './echarts'
  import type { Palette } from './palette'

  // A chart in a card: its title, then (top right) a reset button once the chart has been zoomed
  // or had series toggled, and an (i) explaining what it shows
  let {
    title,
    info,
    build,
    height = '12rem',
    label = title,
    subtitle,
  }: {
    title: string
    info: string
    build: (palette: Palette, view?: ChartView) => EChartsCoreOption
    height?: string
    label?: string
    subtitle?: Snippet
  } = $props()

  let chart: Chart | undefined = $state()
  let modified = $state(false)
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
  <Chart bind:this={chart} bind:modified {height} {label} {build} />
</div>
