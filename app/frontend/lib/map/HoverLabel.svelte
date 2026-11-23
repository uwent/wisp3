<script lang="ts">
  import type { HoverLabelState } from './hover.svelte'

  // A map's hover label, placed in the map's box (the pointer is measured from it): a setup map's
  // (MapHover.label) or the Map tab's. Pointer users only: the pages name everything for keyboards
  // and screen readers.
  let { label }: { label: HoverLabelState | null } = $props()
</script>

{#if label}
  <div
    class="pointer-events-none absolute z-10 w-max max-w-80 space-y-0.5 rounded-md bg-surface-raised px-2 py-1 text-xs
      text-ink shadow-md ring-1 ring-line {label.flip ? '-translate-x-full' : ''}"
    style:left="{label.flip ? label.x - 12 : label.x + 14}px"
    style:top="{label.y + 16}px"
    aria-hidden="true"
  >
    {#each label.lines as line, index (index)}
      <p>{line}</p>
    {/each}
    {#if label.hint}<p class="text-ink-muted">{label.hint}</p>{/if}
  </div>
{/if}
