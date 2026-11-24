<script lang="ts">
  import { Link, page } from '@inertiajs/svelte'

  import FieldCard from '@/lib/components/FieldCard.svelte'
  import { KIND_NOUNS, systemName } from '@/lib/geo'
  import { isExample } from '@/lib/permissions'
  import type { Selection } from '@/lib/overview'
  import type { Units } from '@/lib/units'
  import type { ZoneWeather } from '@/lib/weatherSummary'
  import { systems } from '@/routes'

  import MapPanel from './MapPanel.svelte'
  import type { MapSystem } from './systems'
  import WeatherLines from './WeatherLines.svelte'

  // The selected system's details over the map: its farm and irrigation group, which select
  // themselves as in the list (ScopePanel), its View and Edit links, its weather zone's last week
  // and the week ahead in brief (weatherLines), extra lines from the overlays (the drought category
  // there), and its fields' cards, each selecting its field like the list's with View and Edit
  // links.
  let {
    system,
    farm,
    group = null,
    today,
    units,
    weather = null,
    notes = [],
    fieldId = null,
    onselectfield,
    onselect,
    onclose,
  }: {
    system: MapSystem
    farm: { id: number; name: string }
    group?: { id: number; name: string } | null
    today: string
    units: Units
    /** Its weather zone's weather */
    weather?: ZoneWeather | null
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
    document.querySelector(`[data-map-panel] [data-field="${fieldId}"]`)?.scrollIntoView({ block: 'nearest' })
  })
</script>

{#snippet crumb(level: 'farm' | 'group', item: { id: number; name: string }, noun: string)}
  <button
    type="button"
    class="min-w-0 truncate hover:text-ink hover:underline"
    aria-label="Show the {level === 'farm' ? 'farm' : 'irrigation group'} {item.name}"
    onclick={() => onselect({ level, id: item.id })}
  >
    {noun}: {item.name}
  </button>
{/snippet}

<MapPanel titleId="system-panel-title" {onclose}>
  {#snippet header()}
    <p class="flex min-w-0 items-center gap-1 text-xs text-ink-muted">
      {@render crumb('farm', farm, 'Farm')}
      {#if group}
        <span aria-hidden="true">›</span>
        {@render crumb('group', group, 'Group')}
      {/if}
    </p>
    <h2 id="system-panel-title" class="truncate font-medium">
      <span class="font-normal text-ink-muted">System:</span>
      {systemName(system)}
    </h2>
    <div class="flex items-center gap-2 text-xs font-medium">
      <Link href={systems.show(system.id)} class="text-brand-600 hover:underline" aria-label="View {system.name}">
        View
      </Link>
      {#if !isExample(page.props)}
        <span class="text-ink-muted" aria-hidden="true">·</span>
        <Link href={systems.edit(system.id)} class="text-brand-600 hover:underline" aria-label="Edit {system.name}">
          Edit
        </Link>
      {/if}
    </div>
  {/snippet}
  <WeatherLines {weather} {units} />
  {#if notes.length}
    <dl class="grid grid-cols-[1fr_auto] gap-x-3 gap-y-0.5 text-xs">
      {#each notes as note (note.label)}
        <dt class="text-ink-muted">{note.label}</dt>
        <dd class="flex items-center justify-end gap-1.5 text-right">
          {#if note.swatch}<span class="size-2.5 rounded-sm border border-line" style:background={note.swatch}
            ></span>{/if}{note.value}
        </dd>
      {/each}
    </dl>
  {/if}
  {#if system.fields.length}
    <ul class="space-y-2">
      {#each system.fields as card (card.id)}
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
    <p class="text-sm text-ink-muted">No fields on this {KIND_NOUNS[system.kind]} yet. Add them in Setup.</p>
  {/if}
</MapPanel>
