<script lang="ts">
  import type { Units } from '@/lib/units'
  import { weatherLines, type ZoneWeather } from '@/lib/weatherSummary'

  // A weather zone's last week and the week ahead in brief (weatherLines), for the map's panels;
  // empty says so when there's no weather yet, or nothing is shown
  let { weather, units, empty }: { weather: ZoneWeather | null; units: Units; empty?: string } = $props()

  const lines = $derived(weatherLines(weather, units))
</script>

{#if lines.length}
  <div class="space-y-0.5 text-xs">
    {#each lines as line (line)}<p>{line}</p>{/each}
  </div>
{:else if empty}
  <p class="text-sm text-ink-muted">{empty}</p>
{/if}
