<script lang="ts">
  import { Link, page, router } from '@inertiajs/svelte'
  import { systemName } from '@/lib/geo'

  import { gddFrom, plantingStarts, weatherPanels } from '@/lib/charts/weatherCharts'
  import WeatherSection from '@/lib/charts/WeatherSection.svelte'
  import ForecastStrip from '@/lib/components/ForecastStrip.svelte'
  import Spinner from '@/lib/components/Spinner.svelte'
  import Term from '@/lib/components/Term.svelte'
  import { fileSlug } from '@/lib/csv'
  import { currentYear, formatDate } from '@/lib/dates'
  import { pollWeather } from '@/lib/weatherPolling.svelte'
  import { units as unitsFor, type Units } from '@/lib/units'
  import { fields as fieldRoutes, pivots as pivotRoutes, weatherZones } from '@/routes'
  import { weatherZone, weatherZoneExport } from '@/lib/weatherZones'
  import type { ForecastDay, WeatherPanelDay, WeatherZone } from '@/types/serializers'

  // A weather zone (G.12): its systems, the week ahead, and the season's weather panels (?year=).
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
    zones: { id: number; name: string; coordinates: string; location: string }[]
    year: number
    years: number[]
    weather_from: string
    weather: WeatherPanelDay[]
    plantings: { id: number; label: string; planted: string }[]
    forecast: ForecastDay[]
    updating_pivot_ids: number[]
  } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  // The zone's fields by system, in the systems' order, then by name
  const zoneFields = $derived(
    [...zone.fields].sort(
      (a, b) =>
        zone.pivots.findIndex((pivot) => pivot.id === a.pivot_id) -
          zone.pivots.findIndex((pivot) => pivot.id === b.pivot_id) || a.name.localeCompare(b.name),
    ),
  )

  // Growing degree days add up since January 1 and since the first day in view, and (picked under
  // the chart) since a planting date, the year's plantings that day named together (G.6)
  const starts = $derived(plantingStarts(plantings))
  // The date picked, while it's one of this page's: Inertia keeps the component across a visit to
  // another zone or year, and the picked date stays behind
  let picked = $state('')
  const gddStart = $derived(starts.some((start) => start.date === picked) ? picked : '')
  const plantingTotals = $derived(gddStart ? gddFrom(weather, gddStart) : undefined)
  const panels = $derived((u: Units) =>
    weatherPanels(u, {
      gddSince: formatDate(weather_from),
      gddPlanting:
        gddStart && plantingTotals
          ? { label: `planting (${formatDate(gddStart)})`, totals: plantingTotals }
          : undefined,
    }),
  )

  function visit(location: string, y: number) {
    router.get(weatherZone(location).url, y === currentYear() ? {} : { year: y })
  }

  // While the zone's weather is being fetched, reload until it lands
  const weatherWait = pollWeather(() => updating_pivot_ids)
  const weatherState = $derived(weatherWait.state(updating_pivot_ids.length > 0))
</script>

<svelte:head><title>Weather: {zone.coordinates} · WISP</title></svelte:head>

<!-- Two columns until narrow, so a long list of systems wraps beside the pickers instead of pushing them below -->
<div class="grid items-end gap-3 sm:grid-cols-[minmax(0,1fr)_auto]">
  <div>
    <Link href={weatherZones.index()} class="text-sm text-brand-600 hover:underline">← Weather zones</Link>
    <h1 class="text-2xl font-semibold">
      <span class="font-normal text-ink-muted">Weather:</span>
      {zone.coordinates}
    </h1>
    <!-- The coordinates name the place; the systems in it follow (G.6) -->
    <p class="text-sm text-ink-muted">
      <Term id="weather_zone">Weather zone</Term>{zone.elevation_ft === null
        ? ''
        : `, elevation ${units.format('distance', zone.elevation_ft)}`}
    </p>
    <!-- Its systems, then their fields in the same order, each a link to its page (G.6) -->
    {#if zone.pivots.length}
      <p class="text-sm">
        <span class="text-ink-muted">{zone.pivots.length === 1 ? 'Irrigation system' : 'Irrigation systems'}:</span>
        {#each zone.pivots as pivot, i (pivot.id)}{i ? ', ' : ''}<Link
            href={pivotRoutes.show(pivot.id)}
            class="text-brand-600 underline underline-offset-2">{systemName(pivot)}</Link
          >{` (${pivot.farm})`}{/each}
      </p>
    {/if}
    {#if zoneFields.length}
      <p class="text-sm">
        <span class="text-ink-muted">{zoneFields.length === 1 ? 'Field' : 'Fields'}:</span>
        {#each zoneFields as field, i (field.id)}{i ? ', ' : ''}<Link
            href={fieldRoutes.show(field.id)}
            class="text-brand-600 underline underline-offset-2">{field.name}</Link
          >{` (${field.pivot})`}{/each}
      </p>
    {/if}
  </div>
  <div class="flex flex-wrap gap-2 sm:justify-end">
    {#if zones.length > 1}
      <select
        class="max-w-64 rounded-md text-sm"
        aria-label="Weather zone"
        value={zone.location}
        onchange={(e) => visit(e.currentTarget.value, year)}
      >
        {#each zones as other (other.id)}<option value={other.location}>{other.coordinates}: {other.name}</option
          >{/each}
      </select>
    {/if}
    <select
      class="rounded-md text-sm"
      aria-label="Season"
      value={year}
      onchange={(e) => visit(zone.location, Number(e.currentTarget.value))}
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

{#if year === currentYear()}
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
      href: weatherZoneExport(zone.location, { query: { year } }).url,
    }}
  >
    {#snippet panelControls(key)}
      {#if key === 'gdd' && plantings.length}
        <label class="mt-1 flex min-w-0 items-center gap-2 text-xs text-ink-muted">
          <span class="shrink-0">Add the total since</span>
          <select
            class="w-0 min-w-0 flex-1 rounded-md py-0.5 text-xs"
            bind:value={() => gddStart, (value) => (picked = value)}
          >
            <option value="">no planting</option>
            {#each starts as start (start.date)}<option value={start.date}>{start.label}</option>{/each}
          </select>
        </label>
      {/if}
    {/snippet}
    Each planting's crop ET and soil water are on its own page.
  </WeatherSection>
{:else}
  <p class="text-sm text-ink-muted">No weather stored for {year} in this zone.</p>
{/if}
