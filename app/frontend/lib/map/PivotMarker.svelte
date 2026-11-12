<script lang="ts">
  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import { systemName } from '@/lib/geo'
  import { type FieldCard, pivotStatus, primary, summaryActive } from '@/lib/overview'

  import BadgeRows from './BadgeRows.svelte'
  import { type Badge, type MapPivot, STATUS_LABELS as LABELS, statusText } from './pivots'

  // What sits at an irrigation system's center (or point) on the map (PLAN.md Phase 7): a badge per
  // field without an outline (an outlined field has its own, FieldMarker), packed in rows of about
  // √n (G.14), and its name when zoomed in. Zoomed out (the map sets data-far), it's one dot in the
  // most urgent status of all its fields, outlined or not. Where those fields are under the pivot
  // isn't known without outlines, so they aren't drawn as areas.
  let {
    pivot,
    fields,
    selected,
    dimmed,
    onselect,
    onhover,
  }: {
    pivot: MapPivot
    /** Its fields without an outline */
    fields: FieldCard[]
    selected: boolean
    dimmed: boolean
    onselect: () => void
    onhover: (badge: { label: string; element: HTMLElement } | null) => void
  } = $props()

  const status = $derived(pivotStatus(pivot.fields))
  const badges = $derived<Badge[]>(
    fields.map((card) => {
      const summary = primary(card)
      return {
        key: card.id,
        status: summaryActive(summary) ? summary!.status! : null,
        label: `Field: ${card.name} · ${statusText(summary)}`,
      }
    }),
  )
  const name = $derived(systemName(pivot))
  const label = $derived(
    `${name}: ${pivot.fields.length} field${pivot.fields.length === 1 ? '' : 's'}` +
      (status ? `, most urgent ${LABELS[status]}` : ', none in season'),
  )
  // Every field outlined: nothing to show here until zoomed out
  const farOnly = $derived(pivot.fields.length > 0 && fields.length === 0)
  const hoverName = (event: MouseEvent) =>
    onhover({ label: `System: ${name}`, element: event.currentTarget as HTMLElement })
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
      <BadgeRows {badges} {selected} {onhover} />
    {:else if !farOnly}
      <!-- Hover only, for the map's label: the button names it -->
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <span
        class="block rounded-full bg-black/50 px-1.5 py-0.5 text-[0.65rem] text-white {selected
          ? 'ring-2 ring-white'
          : ''}"
        onmouseenter={hoverName}
        onmouseleave={() => onhover(null)}>No fields</span
      >
    {/if}
  </span>
  <!-- Zoomed out, the most urgent status with its icon, not color alone -->
  <!-- Hover only, for the map's label: the button names it -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <span
    class="hidden rounded-full group-data-far/map:block {selected ? 'outline-2 outline-offset-2 outline-white' : ''}"
    onmouseenter={hoverName}
    onmouseleave={() => onhover(null)}
  >
    {#if status}
      <StatusBadge {status} size="icon" title="{pivot.name}: {LABELS[status]}" tooltip={false} />
    {:else}
      <span class="block size-3.5 rounded-full bg-gray-400 ring-2 ring-white"></span>
    {/if}
  </span>
  <!-- Hover only, for the map's label: the button names it -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <span
    class="max-w-40 truncate text-xs font-semibold text-white [text-shadow:0_0_3px_#000,0_0_2px_#000]
      group-data-far/map:hidden group-data-mid/map:hidden"
    onmouseenter={hoverName}
    onmouseleave={() => onhover(null)}>{pivot.name}</span
  >
</button>
