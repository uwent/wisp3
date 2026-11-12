<script lang="ts">
  import BadgeRows from './BadgeRows.svelte'
  import type { FieldBadges } from './pivots'

  // An outlined field's plantings on the map (G.14): a badge each at the field's center, packed like
  // a system's marker. Hidden zoomed out (the map sets data-far), where its system's dot stands for it.
  let {
    field,
    selected,
    dimmed,
    onselect,
    onhover,
  }: {
    field: FieldBadges
    selected: boolean
    dimmed: boolean
    onselect: () => void
    onhover: (badge: { label: string; element: HTMLElement } | null) => void
  } = $props()

  const label = $derived(`Field: ${field.field_name}, ${field.badges.map((badge) => badge.label).join('; ')}`)
</script>

<button
  type="button"
  class="flex cursor-pointer transition-opacity group-data-far/map:hidden {dimmed ? 'opacity-35' : ''}"
  aria-label={label}
  aria-pressed={selected}
  onclick={(event) => {
    event.stopPropagation()
    onselect()
  }}
>
  <BadgeRows badges={field.badges} {selected} {onhover} />
</button>
