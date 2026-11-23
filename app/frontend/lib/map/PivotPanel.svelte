<script lang="ts">
  import { Link, page } from '@inertiajs/svelte'

  import FieldCard from '@/lib/components/FieldCard.svelte'
  import { KIND_NOUNS, systemName } from '@/lib/geo'
  import { isExample } from '@/lib/permissions'
  import type { Selection } from '@/lib/overview'
  import type { Units } from '@/lib/units'
  import { pivots } from '@/routes'

  import type { MapPivot, WeatherTotals } from './pivots'

  // The selected pivot's details over the map: its farm and irrigation group,
  // which select themselves as in the list (ScopePanel), its View and Edit links, its fields' cards,
  // each selecting its field like the list's with View and Edit links, its weather zone's rain
  // and ET, and extra lines from the overlays (the drought category there). A floating panel on wide
  // screens, a sheet along the bottom on phones.
  let {
    pivot,
    farm,
    group = null,
    today,
    units,
    notes = [],
    fieldId = null,
    onselectfield,
    onselect,
    onclose,
  }: {
    pivot: MapPivot
    farm: { id: number; name: string }
    group?: { id: number; name: string } | null
    today: string
    units: Units
    notes?: { label: string; value: string; swatch?: string }[]
    /** The field selected on the map, marked among the cards */
    fieldId?: number | null
    onselectfield: (fieldId: number) => void
    /** Selects the farm or group */
    onselect: (selection: Selection) => void
    onclose: () => void
  } = $props()

  // The selected field's card into view in the panel
  $effect(() => {
    if (fieldId === null) return
    document.querySelector(`[data-pivot-panel] [data-field="${fieldId}"]`)?.scrollIntoView({ block: 'nearest' })
  })

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

{#snippet crumb(level: 'farm' | 'group', item: { id: number; name: string }, noun: string)}
  <button
    type="button"
    class="min-w-0 truncate hover:text-ink hover:underline"
    aria-label="Show the {level === 'farm' ? 'farm' : 'irrigation group'} {item.name}"
    onclick={() => onselect({ level, id: item.id })}>{noun}: {item.name}</button
  >
{/snippet}

<section
  class="pointer-events-auto flex max-h-full flex-col overflow-hidden rounded-lg border border-line bg-surface shadow-xl
    focus-visible:outline-2 focus-visible:outline-brand-500"
  aria-labelledby="pivot-panel-title"
  tabindex="-1"
  data-pivot-panel
>
  <header class="flex items-start justify-between gap-2 border-b border-line bg-surface-raised px-3 py-2">
    <div class="min-w-0">
      <p class="flex min-w-0 items-center gap-1 text-xs text-ink-muted">
        {@render crumb('farm', farm, 'Farm')}
        {#if group}
          <span aria-hidden="true">›</span>
          {@render crumb('group', group, 'Group')}
        {/if}
      </p>
      <h2 id="pivot-panel-title" class="truncate font-medium">
        <span class="font-normal text-ink-muted">System:</span>
        {systemName(pivot)}
      </h2>
      <div class="flex items-center gap-2 text-xs font-medium">
        <Link href={pivots.show(pivot.id)} class="text-brand-600 hover:underline" aria-label="View {pivot.name}"
          >View</Link
        >
        {#if !isExample(page.props)}
          <span class="text-ink-muted" aria-hidden="true">·</span>
          <Link href={pivots.edit(pivot.id)} class="text-brand-600 hover:underline" aria-label="Edit {pivot.name}"
            >Edit</Link
          >
        {/if}
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
          <li data-field={card.id} aria-current={card.id === fieldId ? 'true' : undefined}>
            <FieldCard
              {card}
              {today}
              {units}
              compact
              links
              selected={card.id === fieldId}
              onselect={() => onselectfield(card.id)}
            />
          </li>
        {/each}
      </ul>
    {:else}
      <p class="text-sm text-ink-muted">No fields on this {KIND_NOUNS[pivot.kind]} yet. Add them in Setup.</p>
    {/if}
  </div>
</section>
