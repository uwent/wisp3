<script lang="ts">
  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import { systemName } from '@/lib/geo'
  import { type FieldCard, pivotStatus } from '@/lib/overview'

  import BadgeRows from './BadgeRows.svelte'
  import { fieldBadge, type MapPivot, STATUS_LABELS as LABELS } from './pivots'

  // What sits at an irrigation system's center (or point) on the map (PLAN.md Phase 7): a badge per
  // field without an outline (an outlined field has its own, FieldMarker), packed in rows of about
  // √n (G.14), inside the system's glyph (sized to hold them, systemLayers.ts), and its name when
  // zoomed in. Zoomed out (the map sets data-far), it's one dot in the most urgent status of all its
  // fields, outlined or not. Badges and name carry their hover label's lines (data-hover).
  let {
    pivot,
    fields,
    today,
    selected,
    dimmed,
    onselect,
  }: {
    pivot: MapPivot
    /** Its fields without an outline */
    fields: FieldCard[]
    today: string
    selected: boolean
    dimmed: boolean
    onselect: () => void
  } = $props()

  const status = $derived(pivotStatus(pivot.fields))
  const badges = $derived(fields.map((card) => fieldBadge(card, today)))
  const name = $derived(systemName(pivot))
  const label = $derived(
    `${name}: ${pivot.fields.length} field${pivot.fields.length === 1 ? '' : 's'}` +
      (status ? `, most urgent ${LABELS[status]}` : ', none in season'),
  )
  // Every field outlined: nothing to show here until zoomed out
  const farOnly = $derived(pivot.fields.length > 0 && fields.length === 0)
</script>

<button
  type="button"
  class="flex cursor-pointer flex-col items-center gap-0.5 transition-opacity {dimmed ? 'opacity-35' : ''}
    {farOnly ? 'hidden group-data-far/map:flex' : ''}"
  aria-label={label}
  aria-pressed={selected}
  onclick={(event) => {
    event.stopPropagation()
    onselect()
  }}
>
  <span class="group-data-far/map:hidden">
    {#if badges.length}
      <BadgeRows {badges} {selected} />
    {:else if !farOnly}
      <span
        class="block rounded-full bg-black/50 px-1.5 py-0.5 text-[0.65rem] text-white {selected
          ? 'ring-2 ring-white'
          : ''}"
        data-hover={`System: ${name}\nNo fields`}>No fields</span
      >
    {/if}
  </span>
  <!-- Zoomed out, the most urgent status with its icon, not color alone -->
  <span
    class="hidden rounded-full group-data-far/map:block {selected ? 'outline-2 outline-offset-2 outline-white' : ''}"
    data-hover="System: {name}"
  >
    {#if status}
      <StatusBadge {status} size="icon" title="{pivot.name}: {LABELS[status]}" tooltip={false} />
    {:else}
      <span class="block size-3.5 rounded-full bg-gray-400 ring-2 ring-white"></span>
    {/if}
  </span>
  <span
    class="max-w-40 truncate text-xs font-semibold text-white [text-shadow:0_0_3px_#000,0_0_2px_#000]
      group-data-far/map:hidden group-data-mid/map:hidden"
    data-hover="System: {name}">{pivot.name}</span
  >
</button>
