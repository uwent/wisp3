<script lang="ts">
  import type { SoilTypesLayer } from './soilTypes.svelte'

  // The Soil types layer's button, beside the basemap toggle
  let { layer }: { layer: SoilTypesLayer } = $props()
</script>

<button
  type="button"
  class="rounded-md border border-line px-2.5 py-1.5 text-xs shadow
    {layer.on ? 'bg-brand-600 text-white dark:text-surface' : 'bg-surface-raised hover:bg-surface'}"
  aria-pressed={layer.on}
  title="Shade the map by soil type, from the USDA soil survey"
  onclick={() => layer.toggle()}>Soil types</button
>
