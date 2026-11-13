<script lang="ts">
  import type { SoilTypesLayer } from './soilTypes.svelte'

  // The soil type under the pointer; placed in the map's container (the pointer is measured from it)
  let { layer }: { layer: SoilTypesLayer } = $props()
</script>

{#if layer.hover}
  <div
    class="pointer-events-none absolute z-10 max-w-60 rounded-md border border-line bg-surface-raised px-2.5 py-1.5 text-xs shadow-lg"
    style:left="{layer.hover.x + 14}px"
    style:top="{layer.hover.y + 14}px"
  >
    <p class="font-medium">{layer.hover.type}</p>
    <p class="text-ink-muted">{layer.hover.unit}</p>
  </div>
{/if}
