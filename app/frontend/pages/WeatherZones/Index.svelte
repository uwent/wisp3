<script lang="ts">
  import { Link } from '@inertiajs/svelte'
  import { systemName } from '@/lib/geo'

  import ForecastStrip from '@/lib/components/ForecastStrip.svelte'
  import GlossaryText from '@/lib/components/GlossaryText.svelte'
  import Spinner from '@/lib/components/Spinner.svelte'
  import { pollWeather } from '@/lib/weatherPolling.svelte'
  import { currentUnits } from '@/lib/units'
  import { fields, pivots, setup } from '@/routes'
  import { weatherZone } from '@/lib/weatherZones'
  import type { ForecastDay, WeatherZone } from '@/types/serializers'

  // The operation's weather zones, each with its irrigation systems and the week ahead beside
  // them (below them on narrow screens). One zone goes straight to it (the controller).
  let {
    zones,
    updating_pivot_ids,
  }: {
    zones: (WeatherZone & { forecast: ForecastDay[] })[]
    updating_pivot_ids: number[]
  } = $props()

  const units = $derived(currentUnits())

  const weatherWait = pollWeather(() => updating_pivot_ids)
  const weatherState = $derived(weatherWait.state(updating_pivot_ids.length > 0))
  const updating = (zone: WeatherZone) => zone.pivots.some((pivot) => updating_pivot_ids.includes(pivot.id))
</script>

<svelte:head><title>Weather · WISP</title></svelte:head>

<div>
  <h1 class="text-2xl font-semibold">Weather</h1>
  <GlossaryText
    class="text-sm text-ink-muted"
    paragraphs={[
      'Irrigation systems close together share a weather zone. Open one for its season of weather: rain, ET, temperatures, wind and soil.',
    ]}
  />
</div>

{#if weatherState === 'failed'}
  <p role="status" class="text-sm text-status-irrigate-ink">Weather update failed. Refresh the page to try again.</p>
{/if}

{#if zones.length}
  <ul class="space-y-3">
    {#each zones as zone (zone.id)}
      <li
        class="flex flex-col gap-3 rounded-lg border border-line bg-surface-raised p-4 lg:flex-row lg:items-start"
        aria-labelledby="zone-{zone.id}"
      >
        <div class="space-y-1 lg:w-56 lg:shrink-0">
          <h2 id="zone-{zone.id}" class="font-medium">
            <Link href={weatherZone(zone.location)} class="text-brand-600 underline underline-offset-2"
              >{zone.coordinates}</Link
            >
          </h2>
          <!-- Its systems and their fields, each a link to its page -->
          {#if zone.pivots.length}
            <p class="text-sm">
              <span class="text-ink-muted">Systems:</span>
              {#each zone.pivots as pivot, i (pivot.id)}{i ? ', ' : ''}<Link
                  href={pivots.show(pivot.id)}
                  class="text-brand-600 underline underline-offset-2">{systemName(pivot)}</Link
                >{/each}
            </p>
          {/if}
          {#if zone.fields.length}
            <p class="text-sm">
              <span class="text-ink-muted">Fields:</span>
              {#each zone.fields as field, i (field.id)}{i ? ', ' : ''}<Link
                  href={fields.show(field.id)}
                  class="text-brand-600 underline underline-offset-2">{field.name}</Link
                >{/each}
            </p>
          {/if}
          {#if weatherState === 'updating' && updating(zone)}
            <p role="status" class="flex items-center gap-1.5 text-sm text-ink-muted"><Spinner />Updating weather…</p>
          {/if}
        </div>
        <div class="min-w-0 flex-1">
          <ForecastStrip days={zone.forecast} {units} label="Forecast for {zone.coordinates}" />
        </div>
      </li>
    {/each}
  </ul>
{:else}
  <p class="text-sm text-ink-muted">
    Weather comes with your irrigation systems. <Link
      href={setup.show()}
      class="text-brand-600 underline underline-offset-2">Add one in Setup</Link
    > to see its weather here.
  </p>
{/if}
