<script lang="ts">
  import { page } from '@inertiajs/svelte'
  import { onMount, type Snippet } from 'svelte'

  import type { ChartView } from './echarts'
  import { formatDate } from '../dates'
  import { downloadCsv, exportedAt, frontmatter, SOURCE, toCsv } from '../csv'
  import { units as unitsFor, type Units } from '../units'
  import CollapsibleSection from '../components/CollapsibleSection.svelte'
  import Chart from './Chart.svelte'
  import ChartCard from './ChartCard.svelte'
  import {
    correctedOn,
    panelCsvRows,
    panelSummary,
    panelTable,
    defaultView,
    seasonSliderOption,
    weatherChartOption,
    type WeatherPanel,
  } from './weatherCharts'
  import { about } from '@/routes'
  import type { WeatherPanelDay } from '@/types/serializers'

  // The weather panels for a pivot's cell (on a field's page or the pivot's), in a collapsible
  // section; they're long on a phone, so they start collapsed there until opened once. panels builds them in some
  // units: the user's for the charts, imperial (as stored) for each chart's CSV. exports: the
  // place and file name for those CSVs, and the link to the pivot's whole weather CSV.
  let {
    title = 'Weather at this location',
    panels: build,
    days,
    units,
    exports,
    children,
  }: {
    title?: string
    panels: (units: Units) => WeatherPanel[]
    days: WeatherPanelDay[]
    units: Units
    exports: { place: string; file: string; href: string }
    children?: Snippet
  } = $props()

  const WIDE = '(min-width: 768px)'
  const open = typeof matchMedia === 'undefined' || matchMedia(WIDE).matches
  const panels = $derived(build(units))

  // Wide, the charts sit in two columns, each its own stack (alternate panels, so pairs sit side
  // by side), so opening one's "Summary and data" lengthens only its column instead of stretching
  // the chart beside it. Narrow, one column in order.
  let wide = $state(typeof matchMedia !== 'undefined' && matchMedia(WIDE).matches)
  onMount(() => {
    const query = matchMedia(WIDE)
    const change = () => (wide = query.matches)
    query.addEventListener('change', change)
    return () => query.removeEventListener('change', change)
  })
  const columns = $derived(
    wide ? [panels.filter((_, i) => i % 2 === 0), panels.filter((_, i) => i % 2 === 1)] : [panels],
  )
  const stored = unitsFor('imperial')

  // The charts zoom together, following the season slider above them or any one of them
  const group = $props.id()
  let slider: Chart | undefined = $state()
  let zoomed = $state(false)
  let inView: ChartView | undefined = $state()
  // The days the charts show, for the slider's heading
  const range = $derived.by(() => {
    const { start, end } = inView ?? defaultView(days)
    const [first, last] = [days[start]?.date, days[end]?.date]
    const str = first && last ? `${formatDate(first)} – ${formatDate(last, { year: true })}` : ''
    const n = end - start + 1
    return `${str} (${n} days)`
  })

  // The slider's bar casts a shadow while it floats over the charts (stuck to the top of the window,
  // or below the bars pinned there)
  let bar: HTMLDivElement | undefined = $state()
  let floating = $state(false)
  onMount(() => {
    const check = () =>
      (floating = !!bar && bar.getBoundingClientRect().top < parseFloat(getComputedStyle(bar).top) + 1)
    addEventListener('scroll', check, { passive: true })
    return () => removeEventListener('scroll', check)
  })

  // The labels of the panel's correction that its days went through ("openmeteo-rh v1"), for its CSV
  function correctionsLine(panel: WeatherPanel): string | null {
    if (!panel.corrected) return null
    const labels = new Set(
      days.flatMap((day) => day.corrections.filter((label) => label.startsWith(`${panel.corrected} v`))),
    )
    const uncorrected = days.filter((day) => !correctedOn(day, panel.corrected!)).length
    if (!labels.size) return 'none (stored before the corrections)'
    return (
      `${[...labels].join(', ')}; see Details` +
      (uncorrected ? ` (${uncorrected} ${uncorrected === 1 ? 'day was' : 'days were'} stored before it)` : '')
    )
  }

  function download(key: string) {
    const panel = build(stored).find((p) => p.key === key)!
    // The panel's unit, and a lower grid's own (cloud cover's %)
    const unit = [
      ...new Set([
        panel.unit(stored),
        ...(panel.below?.series.map((s) => s.unit?.(stored) ?? panel.unit(stored)) ?? []),
      ]),
    ].join(', ')
    const user = page.props.auth.user
    const forecast = days.filter((day) => day.forecast).length
    const name = [user?.first_name, user?.last_name].filter(Boolean).join(' ')
    const rows = [
      ...frontmatter(`WISP weather chart: ${panel.title}, ${exports.place}`, {
        Operation: page.props.auth.group?.name,
        'Irrigation system': exports.place,
        Days:
          `${days[0].date} to ${days.at(-1)!.date}, one row each` +
          (forecast ? `; ${forecast === 1 ? 'the last is' : `the last ${forecast} are`} from the latest forecast` : ''),
        Units: `${unit}, as stored`,
        'Weather corrections': correctionsLine(panel),
        'Exported by': user && (name ? `${name} (${user.email})` : user.email),
        Exported: exportedAt(),
        Source: SOURCE,
        Details: new URL(about().url, location.origin).href,
      }),
      ...panelCsvRows(panel, days, stored),
    ]
    downloadCsv(`${exports.file}-${key.replaceAll('_', '-')}.csv`, toCsv(rows))
  }
</script>

{#if days.length}
  <CollapsibleSection {title} id="weather" storageKey="weather" {open}>
    <p class="text-xs text-ink-muted">
      Modeled by Open-Meteo for the area around this pivot, with the forecast shaded; WISP corrects its sunshine and
      humidity and works out reference ET from them (<a
        href="{about().url}#weather-corrections"
        class="text-brand-600 underline underline-offset-2">weather corrections</a
      >). Drag the bar above the charts, or scroll or pinch any chart, to choose the days they all show, and select the
      (i) on a chart to learn what it shows. {@render children?.()}
      Each chart's data downloads from its "Summary and data", or
      <a href={exports.href} class="text-brand-600 underline underline-offset-2" download
        >download all of this location's weather</a
      >
      (CSV, in inches and °F).
    </p>
    <div
      bind:this={bar}
      class="sticky top-sticky z-10 rounded-lg border border-line bg-surface-raised pb-1.5 transition-shadow motion-reduce:transition-none {floating
        ? 'shadow-lg'
        : ''}"
    >
      <div class="flex items-center justify-between gap-2 px-3 pt-1.5 text-xs">
        <p>
          <span class="font-medium">Weather data range:</span>
          <span class="text-ink-muted tabular-nums">{range}</span>
        </p>
        <button
          type="button"
          class="-mr-1.5 inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-brand-600 hover:bg-surface focus-visible:outline-2 focus-visible:outline-brand-600 disabled:invisible"
          title="Show the charts' opening days again"
          disabled={!zoomed}
          onclick={() => slider?.resetZoom()}
        >
          <svg
            viewBox="0 0 24 24"
            class="size-3.5"
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
          Reset
        </button>
      </div>
      <Chart
        bind:this={slider}
        bind:zoomed
        bind:inView
        {group}
        height="2rem"
        label="The season: drag the bar, or its handles, to choose the days the charts below show"
        build={(palette) => seasonSliderOption(days, palette, units)}
      />
    </div>
    <div class="grid items-start gap-3 md:grid-cols-2">
      {#each columns as column, c (c)}
        <!-- One track that can shrink: an auto track keeps the canvases' old width and overlaps the next column -->
        <div class="grid min-w-0 grid-cols-1 gap-3">
          {#each column as panel (panel.key)}
            <ChartCard
              title={panel.title}
              info={panel.info}
              height={panel.totals || panel.below ? '17rem' : '12rem'}
              build={(palette, view) => weatherChartOption(panel, days, units, palette, view)}
              summary={panelSummary(panel, days, units)}
              table={() => panelTable(panel, days, units)}
              download={() => download(panel.key)}
              {group}
            >
              {#snippet subtitle()}<span class="font-normal text-ink-muted">({panel.unit(units)})</span>{/snippet}
            </ChartCard>
          {/each}
        </div>
      {/each}
    </div>
  </CollapsibleSection>
{/if}
