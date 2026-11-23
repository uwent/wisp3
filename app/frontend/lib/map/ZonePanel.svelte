<script lang="ts">
  import { Link } from '@inertiajs/svelte'

  import ForecastStrip from '@/lib/components/ForecastStrip.svelte'
  import type { Units } from '@/lib/units'
  import { weatherZone } from '@/lib/weatherZones'
  import type { MapZone } from '@/types/serializers'

  import MapPanel from './MapPanel.svelte'
  import WeatherLines from './WeatherLines.svelte'

  // A weather zone selected on the map, in the pivot panel's place: its last week and the week
  // ahead in brief (weatherLines), the week ahead day by day (ForecastStrip) and a link to its
  // season of weather.
  let { zone, today, units, onclose }: { zone: MapZone; today: string; units: Units; onclose: () => void } = $props()
</script>

<MapPanel titleId="zone-panel-title" {onclose}>
  {#snippet header()}
    <h2 id="zone-panel-title" class="truncate font-medium">
      <span class="font-normal text-ink-muted">Weather zone:</span>
      {zone.coordinates}
    </h2>
    <Link href={weatherZone(zone.location)} class="text-xs font-medium text-brand-600 hover:underline"
      >View its weather</Link
    >
  {/snippet}
  <WeatherLines weather={zone.weather} {units} empty="No weather for this zone yet." />
  {#if zone.forecast.length}
    <ForecastStrip days={zone.forecast} {units} {today} compact />
  {/if}
</MapPanel>
