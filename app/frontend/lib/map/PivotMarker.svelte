<script lang="ts">
  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import { type FieldCard, isActive, pivotStatus, type Status } from '@/lib/overview'

  import type { MapPivot } from './pivots'

  // What sits at a pivot's center on the map (PLAN.md Phase 7): a badge per field in season, a gray
  // dot per field that isn't, and the pivot's name when zoomed in. Zoomed out (the map sets
  // data-far), it's one dot in the most urgent status's color. Where its fields are under the pivot
  // isn't known, so they aren't drawn as areas.
  let {
    pivot,
    selected,
    dimmed,
    onselect,
  }: { pivot: MapPivot; selected: boolean; dimmed: boolean; onselect: () => void } = $props()

  const LABELS: Record<Status, string> = { irrigate: 'Irrigate', caution: 'Caution', ok: 'OK', full: 'Full' }
  const DOTS: Record<Status | 'none', string> = {
    irrigate: 'bg-status-irrigate',
    caution: 'bg-status-caution',
    ok: 'bg-status-ok',
    full: 'bg-status-full',
    none: 'bg-gray-400',
  }

  const status = $derived(pivotStatus(pivot.fields))
  const idle = (card: FieldCard) => {
    const summary = card.summary
    if (!summary) return 'no crop this season'
    if (summary.phase === 'upcoming') return 'season not started'
    if (summary.phase === 'ended') return 'season ended'
    return 'waiting for weather'
  }
  const label = $derived(
    `Pivot ${pivot.name}: ${pivot.fields.length} field${pivot.fields.length === 1 ? '' : 's'}` +
      (status ? `, most urgent ${LABELS[status]}` : ', none in season'),
  )
</script>

<button
  type="button"
  class="flex cursor-pointer flex-col items-center gap-0.5 transition-opacity {dimmed ? 'opacity-35' : ''}"
  aria-label={label}
  aria-pressed={selected}
  title={pivot.name}
  onclick={(event) => {
    event.stopPropagation()
    onselect()
  }}
>
  <span
    class="flex max-w-36 flex-wrap justify-center gap-0.5 rounded-full bg-black/50 p-0.5 group-data-far/map:hidden
      {selected ? 'ring-2 ring-white' : ''}"
  >
    {#each pivot.fields as card (card.id)}
      {#if isActive(card)}
        <StatusBadge status={card.summary!.status} size="icon" title="{card.name}: {LABELS[card.summary!.status!]}" />
      {:else}
        <span
          class="inline-flex size-5 rounded-full border-2 border-white/80 bg-gray-400/70"
          title="{card.name}: {idle(card)}"><span class="sr-only">{card.name}: {idle(card)}</span></span
        >
      {/if}
    {:else}
      <span class="px-1.5 text-[0.65rem] text-white">No fields</span>
    {/each}
  </span>
  <span
    class="hidden size-3.5 rounded-full ring-2 ring-white group-data-far/map:block {DOTS[status ?? 'none']}
      {selected ? 'outline-2 outline-offset-2 outline-white' : ''}"
  ></span>
  <span
    class="max-w-40 truncate text-xs font-semibold text-white [text-shadow:0_0_3px_#000,0_0_2px_#000]
      group-data-far/map:hidden group-data-mid/map:hidden">{pivot.name}</span
  >
</button>
