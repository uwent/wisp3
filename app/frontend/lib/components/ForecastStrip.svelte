<script lang="ts">
  import { formatDate } from '../dates'
  import { dayName, skyFor } from '../forecast'
  import type { Units } from '../units'
  import WeatherIcon from './WeatherIcon.svelte'
  import type { ForecastDay } from '@/types/serializers'

  // The week ahead for a weather zone (ForecastDays, G.12): each day's sky, high and low,
  // precipitation with its chance, and reference ET. Seven across when there's room, else four to a
  // row. label names the list for screen readers.
  let {
    days,
    units,
    label = 'Forecast for the week ahead',
    today = new Date().toLocaleDateString('en-CA'),
  }: { days: ForecastDay[]; units: Units; label?: string; today?: string } = $props()

  const degrees = (f: number | null) => (f === null ? '—' : `${units.format('temperature', f, { unit: false })}°`)
</script>

{#if days.length}
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
