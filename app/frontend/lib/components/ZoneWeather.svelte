<script lang="ts">
  import { Link } from '@inertiajs/svelte'

  import type { Units } from '../units'
  import ForecastStrip from './ForecastStrip.svelte'
  import { weatherZone } from '@/routes'
  import type { ForecastDay } from '@/types/serializers'

  // A page's weather (G.12): the week ahead in its weather zone, and a link to the zone's season of
  // weather. query goes on the link (?year=, or ?planting= to count degree days from its emergence).
  // Without a forecast (another year, time travel, an ended season) only the link.
  let {
    zone,
    forecast,
    units,
    query = {},
  }: {
    zone: { id: number; name: string } | null
    forecast: ForecastDay[]
    units: Units
    query?: Record<string, string | number>
  } = $props()
</script>

{#if zone}
  <section class="space-y-2" aria-labelledby="zone-weather-heading">
    <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
      <h2 id="zone-weather-heading" class="text-lg font-medium">{forecast.length ? 'Weather this week' : 'Weather'}</h2>
      <Link href={weatherZone(zone.id, { query })} class="text-sm text-brand-600 underline underline-offset-2"
        >Season's weather: {zone.name} →</Link
      >
    </div>
    {#if forecast.length}<ForecastStrip days={forecast} {units} />{/if}
  </section>
{/if}
