<script lang="ts" module>
  // A correction WISP applies to Open-Meteo's weather (PLAN.md D12, §8.5), from
  // db/reference/weather_corrections/corrections.yml (Weather::Corrections.summaries)
  export type WeatherCorrection = {
    id: string
    label: string
    variable: string
    method: string
    fitted_against: string
    effect: string
    evidence: string
    version: string
    fitted: string
    source: string | null
  }
</script>

<script lang="ts">
  // The corrections as a table, for the About page and the admin weather page
  let { corrections }: { corrections: WeatherCorrection[] } = $props()
</script>

<!-- Focusable so keyboard users can scroll it (WCAG 2.1.1) -->
<!-- svelte-ignore a11y_no_noninteractive_tabindex -->
<div
  class="not-prose overflow-x-auto rounded-lg border border-line bg-surface-raised"
  tabindex="0"
  role="region"
  aria-label="Weather corrections"
>
  <table class="w-full text-sm">
    <thead class="border-b border-line text-left text-xs text-ink-muted">
      <tr>
        <th class="px-3 py-2 font-medium">What</th>
        <th class="px-3 py-2 font-medium">How</th>
        <th class="px-3 py-2 font-medium">Fitted against</th>
        <th class="px-3 py-2 font-medium">Version</th>
      </tr>
    </thead>
    <tbody class="divide-y divide-line align-top">
      {#each corrections as correction (correction.id)}
        <tr>
          <th scope="row" class="px-3 py-2 text-left font-medium">
            {correction.variable}
            <div class="mt-1 text-xs font-normal text-ink-muted">{correction.effect}</div>
          </th>
          <td class="min-w-60 px-3 py-2">{correction.method}</td>
          <td class="min-w-48 px-3 py-2">
            {correction.fitted_against}
            <a
              href={correction.evidence}
              target="_blank"
              rel="noopener"
              class="relative mt-1 block text-xs text-brand-600 underline underline-offset-2"
              >Evidence<span class="sr-only"> for the {correction.variable.toLowerCase()} correction</span></a
            >
          </td>
          <td class="px-3 py-2 whitespace-nowrap">
            <code class="text-xs">{correction.label}</code>
            <div class="text-xs text-ink-muted">{correction.fitted}</div>
          </td>
        </tr>
      {/each}
    </tbody>
  </table>
</div>
