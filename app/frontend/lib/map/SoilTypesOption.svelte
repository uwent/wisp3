<script lang="ts">
  import type { SoilTypesLayer } from './soilTypes.svelte'

  // The Soil types layer's checkbox, in a map's Layers panel
  let { layer }: { layer: SoilTypesLayer } = $props()
</script>

<label class="flex items-start gap-2">
  <input type="checkbox" class="mt-1" checked={layer.on} onchange={() => layer.toggle()} />
  <span>
    Soil types
    <span class="block text-xs text-ink-muted">Shaded by each map unit's main soil, from the USDA soil survey</span>
  </span>
</label>
