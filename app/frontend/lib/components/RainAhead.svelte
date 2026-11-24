<script lang="ts">
  import { Link } from '@inertiajs/svelte'

  import CollapsibleSection from './CollapsibleSection.svelte'
  import Term from './Term.svelte'
  import { formatDate, today as todayDate } from '../dates'
  import { dayName } from '../forecast'
  import { noRain, ODDS_WORDS, rainOdds, rainSummary, type RainOdds } from '../rain'
  import type { Units } from '../units'
  import { weatherZone } from '@/lib/weatherZones'
  import type { ForecastDay } from '@/types/serializers'

  // The week's rain in each weather zone (the dashboard): a row of days
  // per zone (north to south, from the server), each with its chance and rain, likely and possible
  // days filled (lib/rain.ts). Closed to start, then as last left in this browser; closed, its
  // title says when rain comes, to which fields and how much.
  export type RainZone = {
    id: number
    name: string
    coordinates: string
    location: string
    systems: string[]
    system_ids: number[]
    days: ForecastDay[]
  }
  let { zones, units, today = todayDate() }: { zones: RainZone[]; units: Units; today?: string } = $props()

  let open = $state(false)

  // Closed: when rain comes first, to all the zones' fields or some, and how much (lib/rain.ts)
  const summary = $derived(rainSummary(zones, today, units))

  const FILL: Record<RainOdds | 'none', string> = {
    likely: 'border-chart-rain/60 bg-chart-rain/20',
    possible: 'border-chart-rain/40 bg-chart-rain/8',
    none: 'border-line bg-surface-raised',
  }
  const amount = (inches: number | null) =>
    inches !== null && inches < 0.005 ? `0 ${units.label('depth')}` : units.format('depth', inches)
</script>

{#if zones.length}
  <CollapsibleSection
    title={open || !summary ? 'Rain ahead' : `Rain ahead · ${summary}`}
    storageKey="rain-ahead"
    bind:open
  >
    <p class="text-xs text-ink-muted">
      Each day's <Term id="rain_chance">chance of rain</Term> of 0.1 in or more, and the forecast amount. Shaded days: rain
      likely (dark) or possible (light).
    </p>
    <!-- Zones as close together as the days (a phone, with each zone's name above its days, spaces them more) -->
    <div class="space-y-3 sm:space-y-1">
      {#each zones as zone (zone.id)}
        <div class="space-y-1 sm:grid sm:grid-cols-[minmax(0,14rem)_1fr] sm:items-center sm:space-y-0 sm:gap-x-3">
          <div class="min-w-0 leading-tight">
            <Link href={weatherZone(zone.location)} class="text-sm text-brand-600 underline underline-offset-2">
              {zone.coordinates}
            </Link>
            <span class="block truncate text-xs text-ink-muted" title={zone.systems.join(', ')}>
              {zone.systems.join(', ')}
            </span>
          </div>
          <ol class="grid grid-cols-7 gap-1" aria-label="Rain ahead at {zone.name}">
            {#each zone.days as day (day.date)}
              {@const odds = rainOdds(day)}
              <li class="rounded-md border px-0.5 py-1 text-center text-xs/snug {FILL[odds ?? 'none']}">
                <span class="block font-medium">
                  {dayName(day.date, today, { short: true })}<span class="sr-only">{`, ${formatDate(day.date)}`}</span>
                </span>
                <span class="block tabular-nums {odds ? 'font-medium' : 'text-ink-muted'}">
                  {#if noRain(day)}No rain{:else}{#if day.precip_chance !== null}{day.precip_chance}%<span
                        class="sr-only"
                      >
                        {' chance'}
                      </span>{' · '}{/if}<span class="sr-only">rain </span>{amount(day.precip_in)}{/if}
                </span>
                {#if odds}<span class="sr-only">{`, ${ODDS_WORDS[odds].toLowerCase()}`}</span>{/if}
              </li>
            {/each}
          </ol>
        </div>
      {/each}
    </div>
  </CollapsibleSection>
{/if}
