<script lang="ts">
  import { Link } from '@inertiajs/svelte'

  import type { Units } from '../units'
  import CollapsibleSection from './CollapsibleSection.svelte'
  import ForecastStrip from './ForecastStrip.svelte'
  import { weatherZone } from '@/lib/weatherZones'
  import type { ForecastDay } from '@/types/serializers'

  // A page's weather: the week ahead in its weather zone, and a link to the zone's season of
  // weather. query goes on the link (?year=). Without a forecast (another year, time travel) only the
  // link. A compact strip with the link under it, in a section that opens and closes like the page's
  // others.
  let {
    zone,
    forecast,
    units,
    query = {},
  }: {
    zone: { id: number; name: string; location: string } | null
    forecast: ForecastDay[]
    units: Units
    query?: Record<string, string | number>
  } = $props()
</script>

{#if zone}
  <CollapsibleSection title={forecast.length ? 'Weather this week' : 'Weather'} storageKey="zone-weather">
    <div class="space-y-2">
      {#if forecast.length}<ForecastStrip days={forecast} {units} compact />{/if}
      <p class="text-right">
        <Link href={weatherZone(zone.location, { query })} class="text-sm text-brand-600 underline underline-offset-2">
          View detailed weather charts for this location →
        </Link>
      </p>
    </div>
  </CollapsibleSection>
{/if}
