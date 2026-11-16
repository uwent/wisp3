<script lang="ts">
  import { formatDate } from '../dates'
  import { dayName, skyFor } from '../forecast'
  import type { Units } from '../units'
  import WeatherIcon from './WeatherIcon.svelte'
  import type { ForecastDay } from '@/types/serializers'

  // The week ahead for a weather zone (ForecastDays, G.12): each day's sky, high and low,
  // precipitation with its chance, and reference ET. Seven across when there's room, else four to a
  // row. label names the list for screen readers. compact: a line or two a day (field, planting and
  // system pages, G.6): the sky as an icon (its name for screen readers), high and low, precipitation.
  let {
    days,
    units,
    label = 'Forecast for the week ahead',
    today = new Date().toLocaleDateString('en-CA'),
    compact = false,
  }: { days: ForecastDay[]; units: Units; label?: string; today?: string; compact?: boolean } = $props()

  const degrees = (f: number | null) => (f === null ? '—' : `${units.format('temperature', f, { unit: false })}°`)
</script>

{#if days.length && compact}
  <!-- As many across as fit (all seven on a wide page), so a narrow phone wraps rather than scrolling sideways -->
  <ol class="grid grid-cols-[repeat(auto-fit,minmax(7.5rem,1fr))] gap-1.5" aria-label={label}>
    {#each days as day (day.date)}
      {@const sky = skyFor(day)}
      {@const wet = (day.precip_in ?? 0) > 0}
      <li class="flex items-center gap-1.5 rounded-md border border-line bg-surface-raised px-2 py-1 text-xs">
        {#if sky}<WeatherIcon sky={sky.sky} class="size-6" />{/if}
        <span class="min-w-0 leading-tight">
          <span class="block whitespace-nowrap">
            <span class="font-medium"
              >{dayName(day.date, today, { short: true })}<span class="sr-only"
                >{`, ${formatDate(day.date)}${sky ? `, ${sky.label}` : ''}`}</span
              ></span
            >{' '}<span class="font-semibold"><span class="sr-only">high </span>{degrees(day.tmax_f)}</span><span
              class="text-ink-muted"
              ><span class="sr-only">, low </span><span aria-hidden="true">/</span>{degrees(day.tmin_f)}</span
            >
          </span>
          <span class="block whitespace-nowrap {wet ? '' : 'text-ink-muted'}">
            <span class="sr-only">Precipitation </span>{units.format(
              'depth',
              day.precip_in,
            )}{#if day.precip_chance !== null}<span class="text-ink-muted"
                >{` · ${day.precip_chance}%`}<span class="sr-only"> chance</span></span
              >{/if}
          </span>
        </span>
      </li>
    {/each}
  </ol>
{:else if days.length}
  <ol class="grid grid-cols-4 gap-1.5 sm:grid-cols-7" aria-label={label}>
    {#each days as day (day.date)}
      {@const sky = skyFor(day)}
      {@const wet = (day.precip_in ?? 0) > 0}
      <li
        class="relative flex flex-col items-center gap-0.5 rounded-md border border-line bg-surface-raised px-1 py-2 text-center"
      >
        <span class="text-sm font-medium">
          {dayName(day.date, today)}<span class="sr-only">{`, ${formatDate(day.date)}`}</span>
        </span>
        <span class="text-xs text-ink-muted" aria-hidden="true">{formatDate(day.date)}</span>
        {#if sky}
          <WeatherIcon sky={sky.sky} class="my-0.5 size-8" />
          <span class="text-xs leading-tight">{sky.label}</span>
        {/if}
        <span class="text-sm">
          <span class="font-semibold"><span class="sr-only">High </span>{degrees(day.tmax_f)}</span>
          <span class="text-ink-muted"><span class="sr-only">, low </span>{degrees(day.tmin_f)}</span>
        </span>
        <span class="text-xs {wet ? '' : 'text-ink-muted'}">
          <span class="sr-only">Precipitation </span>{units.format(
            'depth',
            day.precip_in,
          )}{#if day.precip_chance !== null}<span class="text-ink-muted"
              >{` · ${day.precip_chance}%`}<span class="sr-only"> chance</span></span
            >{/if}
        </span>
        <span class="text-xs text-ink-muted">
          <abbr title="Reference evapotranspiration" class="no-underline">ET</abbr>
          {units.format('depth', day.et0_in)}
        </span>
      </li>
    {/each}
  </ol>
{:else}
  <p class="text-sm text-ink-muted">No forecast yet for this location.</p>
{/if}
