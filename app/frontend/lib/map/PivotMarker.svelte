<script lang="ts">
  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import { type FieldCard, isActive, pivotStatus, primary, type Status } from '@/lib/overview'

  import { badgeRows, type MapPivot } from './pivots'

  // What sits at an irrigation system's center (or point) on the map (PLAN.md Phase 7): a badge per
  // field in season, a gray dot per field that isn't, packed in rows of about √n (G.14), and its
  // name when zoomed in. Zoomed out (the map sets data-far), it's one dot in the most urgent status's
  // color. Where its fields are under the pivot isn't known without outlines, so they aren't drawn
  // as areas.
  let {
    pivot,
    selected,
    dimmed,
    onselect,
  }: { pivot: MapPivot; selected: boolean; dimmed: boolean; onselect: () => void } = $props()

  const LABELS: Record<Status, string> = {
    irrigate: 'Irrigate',
    caution: 'Caution',
    needs_canopy: 'No canopy data',
    ok: 'OK',
    full: 'Full',
  }

  const status = $derived(pivotStatus(pivot.fields))
  // The fields in rows: 3 over 2 for five
  const rows = $derived(
    badgeRows(pivot.fields.length).map((size, row, sizes) => {
      const start = sizes.slice(0, row).reduce((sum, n) => sum + n, 0)
      return pivot.fields.slice(start, start + size)
    }),
  )
  const idle = (card: FieldCard) => {
    const summary = primary(card)
    if (!summary) return 'no crop this season'
    if (summary.phase === 'upcoming') return 'season not started'
    if (summary.phase === 'ended') return 'season ended'
    return 'waiting for weather'
  }
  const label = $derived(
    `${pivot.kind_name} ${pivot.name}: ${pivot.fields.length} field${pivot.fields.length === 1 ? '' : 's'}` +
      (status ? `, most urgent ${LABELS[status]}` : ', none in season'),
  )
</script>

<button
  type="button"
  class="flex cursor-pointer flex-col items-center gap-0.5 transition-opacity {dimmed ? 'opacity-35' : ''}"
  aria-label={label}
  aria-pressed={selected}
  title="{pivot.kind_name}: {pivot.name}"
  onclick={(event) => {
    event.stopPropagation()
    onselect()
  }}
>
  <span
    class="flex flex-col items-center gap-0.5 bg-black/50 p-0.5 group-data-far/map:hidden
      {rows.length > 1 ? 'rounded-xl' : 'rounded-full'} {selected ? 'ring-2 ring-white' : ''}"
  >
    {#each rows as row, index (index)}
      <span class="flex gap-0.5">
        {#each row as card (card.id)}
          {#if isActive(card)}
            <StatusBadge
              status={primary(card)!.status}
              size="icon"
              title="{card.name}: {LABELS[primary(card)!.status!]}"
            />
          {:else}
            <span
              class="inline-flex size-5 rounded-full border-2 border-white/80 bg-gray-400/70"
              title="{card.name}: {idle(card)}"><span class="sr-only">{card.name}: {idle(card)}</span></span
            >
          {/if}
        {/each}
      </span>
    {:else}
      <span class="px-1.5 text-[0.65rem] text-white">No fields</span>
    {/each}
  </span>
  <!-- Zoomed out, the most urgent status with its icon, not color alone -->
  <span
    class="hidden rounded-full group-data-far/map:block {selected ? 'outline-2 outline-offset-2 outline-white' : ''}"
  >
    {#if status}
      <StatusBadge {status} size="icon" title="{pivot.name}: {LABELS[status]}" />
    {:else}
      <span class="block size-3.5 rounded-full bg-gray-400 ring-2 ring-white"></span>
    {/if}
  </span>
  <span
    class="max-w-40 truncate text-xs font-semibold text-white [text-shadow:0_0_3px_#000,0_0_2px_#000]
      group-data-far/map:hidden group-data-mid/map:hidden">{pivot.name}</span
  >
</button>
