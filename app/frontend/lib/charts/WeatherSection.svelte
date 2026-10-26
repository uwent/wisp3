<script lang="ts">
  import { page } from '@inertiajs/svelte'
  import type { Snippet } from 'svelte'
  import { slide } from 'svelte/transition'

  import { downloadCsv, exportedAt, frontmatter, SOURCE, toCsv } from '../csv'
  import { motion } from '../motion'
  import { units as unitsFor, type Units } from '../units'
  import ChartCard from './ChartCard.svelte'
  import { panelCsvRows, panelSummary, panelTable, weatherChartOption, type WeatherPanel } from './weatherCharts'
  import { about } from '@/routes'
  import type { WeatherPanelDay } from '@/types/serializers'

  // The weather panels for a pivot's cell (on a field's page or the pivot's), with a show/hide
  // toggle; they're long on a phone, so they start collapsed there. panels builds them in some
  // units: the user's for the charts, imperial (as stored) for each chart's CSV. exports: the
  // place and file name for those CSVs, and the link to the pivot's whole weather CSV.
  let {
    title = 'Weather at this pivot',
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

  let open = $state(typeof matchMedia === 'undefined' || matchMedia('(min-width: 768px)').matches)
  const panels = $derived(build(units))
  const stored = unitsFor('imperial')

  function download(key: string) {
    const panel = build(stored).find((p) => p.key === key)!
    const unit = panel.unit(stored)
    const user = page.props.auth.user
    const forecast = days.filter((day) => day.forecast).length
    const name = [user?.first_name, user?.last_name].filter(Boolean).join(' ')
    const rows = [
      ...frontmatter(`WISP weather chart: ${panel.title}, ${exports.place}`, {
        Operation: page.props.auth.group?.name,
        Pivot: exports.place,
        Days:
          `${days[0].date} to ${days.at(-1)!.date}, one row each` +
          (forecast ? `; ${forecast === 1 ? 'the last is' : `the last ${forecast} are`} from the latest forecast` : ''),
        Units: `${unit}, as stored`,
        'Exported by': user && (name ? `${name} (${user.email})` : user.email),
        Exported: exportedAt(),
        Source: SOURCE,
        Details: new URL(about().url, location.origin).href,
      }),
      ...panelCsvRows(panel, days, unit),
    ]
    downloadCsv(`${exports.file}-${key.replaceAll('_', '-')}.csv`, toCsv(rows))
  }
</script>

{#if days.length}
  <section class="space-y-3">
    <div class="flex items-center justify-between">
      <h2 class="font-medium">{title}</h2>
      <button
        type="button"
        class="text-sm text-brand-600 hover:underline"
        onclick={() => (open = !open)}
        aria-expanded={open}
      >
        {open ? 'Hide' : 'Show'}
      </button>
    </div>
    {#if open}
      <div class="space-y-3" transition:slide={{ duration: motion(200) }}>
        <p class="text-xs text-ink-muted">
          Modeled by Open-Meteo for the area around this pivot, with the forecast shaded. Scroll or pinch a chart to see
          more of the season, and select the (i) on a chart to learn what it shows. {@render children?.()}
          Each chart's data downloads from its "Summary and data", or
          <a href={exports.href} class="text-brand-600 underline underline-offset-2" download
            >download all of this pivot's weather</a
          >
          (CSV, in inches and °F).
        </p>
        <div class="grid gap-3 md:grid-cols-2">
          {#each panels as panel (panel.key)}
            <ChartCard
              title={panel.title}
              info={panel.info}
              height={panel.totals ? '17rem' : '12rem'}
              build={(palette, view) => weatherChartOption(panel, days, units, palette, view)}
              summary={panelSummary(panel, days, units)}
              table={() => panelTable(panel, days)}
              unit={panel.unit(units)}
              download={() => download(panel.key)}
            >
              {#snippet subtitle()}<span class="font-normal text-ink-muted">({panel.unit(units)})</span>{/snippet}
            </ChartCard>
          {/each}
        </div>
      </div>
    {/if}
  </section>
{/if}
