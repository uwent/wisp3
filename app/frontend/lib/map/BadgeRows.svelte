<script lang="ts">
  import StatusBadge from '@/lib/components/StatusBadge.svelte'

  import { type Badge, packRows } from './pivots'

  // Badges packed in rows of about √n (G.14: three make a triangle, four a square), on a dark
  // backing. Each names itself through the map's hover label (onhover) and to screen readers.
  let {
    badges,
    selected = false,
    onhover,
  }: {
    badges: Badge[]
    selected?: boolean
    /** The badge under the pointer, or null when it leaves */
    onhover: (badge: { label: string; element: HTMLElement } | null) => void
  } = $props()

  const rows = $derived(packRows(badges))
  const enter = (event: MouseEvent, label: string) => onhover({ label, element: event.currentTarget as HTMLElement })
</script>

<span
  class="flex flex-col items-center gap-0.5 bg-black/50 p-0.5 {rows.length > 1 ? 'rounded-xl' : 'rounded-full'}
    {selected ? 'ring-2 ring-white' : ''}"
>
  {#each rows as row, index (index)}
    <span class="flex gap-0.5">
      {#each row as badge (badge.key)}
        <!-- Hover only, for the map's label: the button names it -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <span class="flex" onmouseenter={(event) => enter(event, badge.label)} onmouseleave={() => onhover(null)}>
          {#if badge.status}
            <StatusBadge status={badge.status} size="icon" title={badge.label} tooltip={false} />
          {:else}
            <span class="inline-flex size-5 rounded-full border-2 border-white/80 bg-gray-400/70"
              ><span class="sr-only">{badge.label}</span></span
            >
          {/if}
        </span>
      {/each}
    </span>
  {/each}
</span>
