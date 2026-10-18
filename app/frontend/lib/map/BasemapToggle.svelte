<script lang="ts">
  import { BASEMAPS, type Basemap } from './basemaps'

  // Satellite / Map, for the pivot picker and the map page
  let { value, onchange }: { value: Basemap; onchange: (basemap: Basemap) => void } = $props()
</script>

<div
  class="flex overflow-hidden rounded-md border border-line bg-surface-raised text-xs shadow"
  role="group"
  aria-label="Basemap"
>
  {#each BASEMAPS as { key, name } (key)}
    <button
      type="button"
      class="px-2.5 py-1.5 {value === key ? 'bg-brand-600 text-white dark:text-surface' : 'hover:bg-surface'}"
      aria-pressed={value === key}
      onclick={() => value !== key && onchange(key)}>{name}</button
    >
  {/each}
</div>
