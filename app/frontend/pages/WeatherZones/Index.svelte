<script lang="ts">
  import { Link, page, router } from '@inertiajs/svelte'
  import { systemName } from '@/lib/geo'

  import ForecastStrip from '@/lib/components/ForecastStrip.svelte'
  import GlossaryText from '@/lib/components/GlossaryText.svelte'
  import Spinner from '@/lib/components/Spinner.svelte'
  import { poll, weatherUpdate } from '@/lib/poll'
  import { units as unitsFor } from '@/lib/units'
  import { setup, weatherZones } from '@/routes'
  import type { ForecastDay, WeatherZone } from '@/types/serializers'

  // The operation's weather zones (G.12), each with its irrigation systems and the week ahead beside
  // them (below them on narrow screens). One zone goes straight to it (the controller).
  let {
    zones,
    updating_pivot_ids,
  }: {
    zones: (WeatherZone & { forecast: ForecastDay[] })[]
    updating_pivot_ids: number[]
  } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))

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
            <Link href={weatherZones.show(zone.id)} class="text-brand-600 underline underline-offset-2"
              >{zone.name}</Link
            >
          </h2>
          <p class="text-xs text-ink-muted">{zone.coordinates}</p>
          <p class="text-sm text-ink-muted">
            {zone.pivots.map(systemName).join(', ')}
          </p>
          {#if weatherState === 'updating' && updating(zone)}
            <p role="status" class="flex items-center gap-1.5 text-sm text-ink-muted"><Spinner />Updating weather…</p>
          {/if}
        </div>
        <div class="min-w-0 flex-1">
          <ForecastStrip days={zone.forecast} {units} label="Forecast for {zone.name}" />
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
