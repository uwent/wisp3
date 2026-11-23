<script lang="ts">
  import type { MapHover } from './hover.svelte'

  // A setup map's hover label, placed in the map's box (the pointer is measured from it). Pointer
  // users only: the pages name everything for keyboards and screen readers.
  let { hover }: { hover: MapHover } = $props()
</script>

{#if hover.label}
  <div
    class="pointer-events-none absolute z-10 w-max max-w-80 space-y-0.5 rounded-md bg-surface-raised px-2 py-1 text-xs
      text-ink shadow-md ring-1 ring-line {hover.label.flip ? '-translate-x-full' : ''}"
    style:left="{hover.label.flip ? hover.label.x - 12 : hover.label.x + 14}px"
    style:top="{hover.label.y + 16}px"
    aria-hidden="true"
  >
    {#each hover.label.lines as line, index (index)}
      <p>{line}</p>
    {/each}
    {#if hover.label.hint}<p class="text-ink-muted">{hover.label.hint}</p>{/if}
  </div>
{/if}
