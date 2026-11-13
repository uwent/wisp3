<script lang="ts">
  import { SOIL_COLORS } from '@/lib/soils'

  import type { SoilTypesLayer } from './soilTypes.svelte'

  // The Soil types layer's legend, under the map while it's on
  let {
    layer,
    soilTypes,
    zoomHint,
  }: {
    layer: SoilTypesLayer
    soilTypes: { key: string; name: string }[]
    /** What to do when there's nothing to load yet ("zoom in to see them") */
    zoomHint: string
  } = $props()
</script>

{#if layer.on}
  <div class="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs" aria-live="polite">
    <span class="font-medium">Soil types:</span>
    {#if layer.status === 'loading'}
      <span class="text-ink-muted">loading from the soil survey…</span>
    {:else if layer.status === 'error'}
      <span class="text-ink-muted">the soil survey can't be reached right now.</span>
    {:else if layer.status === 'zoom'}
      <span class="text-ink-muted">{zoomHint}</span>
    {:else}
      {#each soilTypes.filter((type) => layer.keys.includes(type.key)) as type (type.key)}
        <span class="flex items-center gap-1"
          ><span class="size-3 rounded-sm border border-line" style:background={SOIL_COLORS[type.key]}
          ></span>{type.name}</span
        >
      {:else}
        <span class="text-ink-muted">no soil types matched here.</span>
      {/each}
      <span class="text-ink-muted"
        >From each map unit's main soil in the <a
          href="https://websoilsurvey.nrcs.usda.gov/"
          target="_blank"
          rel="noopener"
          class="text-brand-600 hover:underline">USDA soil survey</a
        >.</span
      >
    {/if}
  </div>
{/if}
