<script lang="ts">
  import type { Snippet } from 'svelte'
  import { slide } from 'svelte/transition'

  import type { Units } from '../units'
  import ChartCard from './ChartCard.svelte'
  import { weatherChartOption, type WeatherPanel } from './weatherCharts'
  import type { WeatherPanelDay } from '@/types/serializers'

  // The weather panels for a pivot's cell (on a field's page or the pivot's), with a show/hide
  // toggle; they're long on a phone, so they start collapsed there
  let {
    title = 'Weather at this pivot',
    panels,
    days,
    units,
    children,
  }: { title?: string; panels: WeatherPanel[]; days: WeatherPanelDay[]; units: Units; children?: Snippet } = $props()

  let open = $state(typeof matchMedia === 'undefined' || matchMedia('(min-width: 768px)').matches)
</script>

{#if days.length}
  <section class="space-y-3">
    <div class="flex items-center justify-between">
      <h2 class="font-medium">{title}</h2>
      <button
        type="button"
        class="text-sm text-brand-600 hover:underline"
        onclick={() => (open = !open)}
        aria-expanded={open}
      >
        {open ? 'Hide' : 'Show'}
      </button>
    </div>
    {#if open}
      <div class="space-y-3" transition:slide={{ duration: 200 }}>
        <p class="text-xs text-ink-muted">
          Modeled by Open-Meteo for the pivot's grid cell, with the forecast shaded. Scroll or pinch a chart to see more
          of the season; the (i) on each chart explains what it shows. {@render children?.()}
        </p>
        <div class="grid gap-3 md:grid-cols-2">
          {#each panels as panel (panel.key)}
            <ChartCard
              title={panel.title}
              info={panel.info}
              height={panel.totals ? '17rem' : '12rem'}
              build={(palette, view) => weatherChartOption(panel, days, units, palette, view)}
            >
              {#snippet subtitle()}<span class="font-normal text-ink-muted">({panel.unit(units)})</span>{/snippet}
            </ChartCard>
          {/each}
        </div>
      </div>
    {/if}
  </section>
{/if}
