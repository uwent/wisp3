<script lang="ts">
  import { Link } from '@inertiajs/svelte'

  import FieldCard from '@/lib/components/FieldCard.svelte'
  import type { Units } from '@/lib/units'
  import { pivots } from '@/routes'

  import type { MapPivot, WeatherTotals } from './pivots'

  // The selected pivot's details over the map (PLAN.md Phase 7): its fields' cards, its weather
  // zone's rain and ET, and extra lines from the overlays (the drought category there). A floating
  // panel on wide screens, a sheet along the bottom on phones.
  let {
    pivot,
    farmName,
    today,
    units,
    notes = [],
    onclose,
  }: {
    pivot: MapPivot
    farmName: string
    today: string
    units: Units
    notes?: { label: string; value: string; swatch?: string }[]
    onclose: () => void
  } = $props()

  const depth = (totals: WeatherTotals | null, key: 'precip' | 'et0') =>
    totals && totals[key] !== null ? units.format('depth', totals[key]) : null
  const weather = $derived(
    [
      ['Rain, last 7 days', depth(pivot.weather?.past ?? null, 'precip')],
      ['Rain forecast, next 7 days', depth(pivot.weather?.ahead ?? null, 'precip')],
      ['Reference ET, last 7 days', depth(pivot.weather?.past ?? null, 'et0')],
    ].filter((row): row is [string, string] => row[1] !== null),
  )
</script>

<section
  class="pointer-events-auto flex max-h-full flex-col overflow-hidden rounded-lg border border-line bg-surface shadow-xl"
  aria-labelledby="pivot-panel-title"
>
  <header class="flex items-start justify-between gap-2 border-b border-line bg-surface-raised px-3 py-2">
    <div class="min-w-0">
      <p class="truncate text-xs text-ink-muted">Farm: {farmName}</p>
      <h2 id="pivot-panel-title" class="truncate font-medium">
        <span class="font-normal text-ink-muted">Pivot:</span>
        {pivot.name}
      </h2>
      <div class="flex gap-3 text-xs">
        <Link href={pivots.show(pivot.id)} class="text-brand-600 hover:underline">View pivot</Link>
        <Link href={pivots.edit(pivot.id)} class="text-brand-600 hover:underline">Edit</Link>
      </div>
    </div>
    <button
      type="button"
      class="-mr-1 rounded-md px-2 py-1 text-lg leading-none text-ink-muted hover:bg-surface hover:text-ink"
      aria-label="Close"
      onclick={onclose}>×</button
    >
  </header>
  <div class="space-y-3 overflow-y-auto p-3">
    {#if weather.length || notes.length}
      <dl class="grid grid-cols-[1fr_auto] gap-x-3 gap-y-0.5 text-xs">
        {#each weather as [label, value] (label)}
          <dt class="text-ink-muted">{label}</dt>
          <dd class="text-right tabular-nums">{value}</dd>
        {/each}
        {#each notes as note (note.label)}
          <dt class="text-ink-muted">{note.label}</dt>
          <dd class="flex items-center justify-end gap-1.5 text-right">
            {#if note.swatch}<span class="size-2.5 rounded-sm border border-line" style:background={note.swatch}
              ></span>{/if}{note.value}
          </dd>
        {/each}
      </dl>
    {/if}
    {#if pivot.fields.length}
      <ul class="space-y-2">
        {#each pivot.fields as card (card.id)}
          <li><FieldCard {card} {today} {units} compact /></li>
        {/each}
      </ul>
    {:else}
      <p class="text-sm text-ink-muted">No fields on this pivot yet.</p>
    {/if}
  </div>
</section>
