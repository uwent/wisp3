<script lang="ts">
  import { Link, page, router } from '@inertiajs/svelte'

  import { gddFrom, weatherPanels } from '@/lib/charts/weatherCharts'
  import WeatherSection from '@/lib/charts/WeatherSection.svelte'
  import ForecastStrip from '@/lib/components/ForecastStrip.svelte'
  import Spinner from '@/lib/components/Spinner.svelte'
  import Term from '@/lib/components/Term.svelte'
  import { fileSlug } from '@/lib/csv'
  import { formatDate } from '@/lib/dates'
  import { poll, weatherUpdate } from '@/lib/poll'
  import { units as unitsFor, type Units } from '@/lib/units'
  import { exportWeatherZone, pivots as pivotRoutes, weatherZones } from '@/routes'
  import type { ForecastDay, WeatherPanelDay, WeatherZone } from '@/types/serializers'

  // A weather zone (G.12): its systems, the week ahead, and the season's weather panels (?year=).
  // ?planting= adds a growing degree day total from that planting's date (the planting page's link).
  let {
    zone,
    zones,
    year,
    years,
    weather_from,
    weather,
    plantings,
    forecast,
    updating_pivot_ids,
  }: {
    zone: WeatherZone
    zones: { id: number; name: string }[]
    year: number
    years: number[]
    weather_from: string
    weather: WeatherPanelDay[]
    plantings: { id: number; label: string; planted: string }[]
    forecast: ForecastDay[]
    updating_pivot_ids: number[]
  } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))

  // Growing degree days add up since January 1 and since the first day in view, and (picked under
  // the chart) since one of the year's plantings went in
  const requested = new URL(page.url, 'http://wisp').searchParams.get('planting')
  let gddStart = $state(requested ?? '')
  const gddPlanting = $derived(plantings.find((planting) => String(planting.id) === gddStart))
  const plantingTotals = $derived(gddPlanting && gddFrom(weather, gddPlanting.planted))
  const panels = $derived((u: Units) =>
    weatherPanels(u, {
      gddSince: formatDate(weather_from),
      gddPlanting:
        gddPlanting && plantingTotals
          ? { label: `planting (${formatDate(gddPlanting.planted)})`, totals: plantingTotals }
          : undefined,
    }),
  )

  function visit(id: number, y: number) {
    router.get(weatherZones.show(id).url, y === new Date().getFullYear() ? {} : { year: y })
  }

  // While the zone's weather is being fetched, reload until it lands
  let timedOut = $state(false)
  $effect(() => {
    if (!updating_pivot_ids.length) return
    timedOut = false
    return poll(
      () => updating_pivot_ids,
      (done) => router.reload({ onFinish: done }),
      { ongiveup: () => (timedOut = true) },
    )
  })
  const weatherState = $derived(weatherUpdate(updating_pivot_ids.length > 0, timedOut))
</script>

<svelte:head><title>Weather: {zone.name} · WISP</title></svelte:head>

<!-- Two columns until narrow, so a long list of systems wraps beside the pickers instead of pushing them below -->
<div class="grid items-end gap-3 sm:grid-cols-[minmax(0,1fr)_auto]">
  <div>
    {#if zones.length > 1}
      <Link href={weatherZones.index()} class="text-sm text-brand-600 hover:underline">← Weather zones</Link>
    {/if}
    <h1 class="text-2xl font-semibold">
      <span class="font-normal text-ink-muted">Weather:</span>
      {zone.name}
    </h1>
    <p class="text-sm text-ink-muted">
      <Term id="weather_zone">Weather zone</Term>
      {` at ${zone.coordinates}`}{zone.elevation_ft === null
        ? ''
        : `, elevation ${units.format('distance', zone.elevation_ft)}`}
      {#if zone.pivots.length}
        · {zone.pivots.length === 1 ? 'Irrigation system' : 'Irrigation systems'}:
        {#each zone.pivots as pivot, i (pivot.id)}{i ? ', ' : ''}<Link
            href={pivotRoutes.show(pivot.id)}
            class="text-brand-600 underline underline-offset-2">{pivot.kind_name}: {pivot.name}</Link
          >{` (${pivot.farm})`}{/each}
      {/if}
    </p>
  </div>
  <div class="flex flex-wrap gap-2 sm:justify-end">
    {#if zones.length > 1}
      <select
        class="max-w-64 rounded-md text-sm"
        aria-label="Weather zone"
        value={zone.id}
        onchange={(e) => visit(Number(e.currentTarget.value), year)}
      >
        {#each zones as other (other.id)}<option value={other.id}>{other.name}</option>{/each}
      </select>
    {/if}
    <select
      class="rounded-md text-sm"
      aria-label="Season"
      value={year}
      onchange={(e) => visit(zone.id, Number(e.currentTarget.value))}
    >
      {#each years as y (y)}<option value={y}>{y}</option>{/each}
    </select>
  </div>
</div>

{#if weatherState === 'updating'}
  <p role="status" class="flex items-center gap-1.5 text-sm text-ink-muted"><Spinner />Updating weather…</p>
{:else if weatherState === 'failed'}
  <p role="status" class="text-sm text-status-irrigate-ink">Weather update failed. Refresh the page to try again.</p>
{/if}

{#if year === new Date().getFullYear()}
  <section class="space-y-2" aria-labelledby="week-heading">
    <h2 id="week-heading" class="text-lg font-medium">The week ahead</h2>
    <ForecastStrip days={forecast} {units} />
  </section>
{/if}

{#if weather.length}
  <WeatherSection
    title="Weather charts"
    {panels}
    days={weather}
    {units}
    controlled={plantings.length ? ['gdd'] : []}
    exports={{
      place: zone.name,
      file: `wisp-weather-${fileSlug(zone.name)}-${year}`,
      href: exportWeatherZone(zone.id, { query: { year } }).url,
    }}
  >
    {#snippet panelControls(key)}
      {#if key === 'gdd' && plantings.length}
        <label class="mt-1 flex min-w-0 items-center gap-2 text-xs text-ink-muted">
          <span class="shrink-0">Add the total since</span>
          <select class="w-0 min-w-0 flex-1 rounded-md py-0.5 text-xs" bind:value={gddStart}>
            <option value="">no planting</option>
            {#each plantings as planting (planting.id)}
              <option value={String(planting.id)}>{planting.label}, planted {formatDate(planting.planted)}</option>
            {/each}
          </select>
        </label>
      {/if}
    {/snippet}
    Each planting's crop ET and soil water are on its own page.
  </WeatherSection>
{:else}
  <p class="text-sm text-ink-muted">No weather stored for {year} in this zone.</p>
{/if}
