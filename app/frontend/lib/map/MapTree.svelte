<script lang="ts">
  import FieldCard from '@/lib/components/FieldCard.svelte'
  import { systemName } from '@/lib/geo'
  import KindIcon from '@/lib/components/KindIcon.svelte'
  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import type { WeatherUpdate } from '@/lib/poll'
  import { type FarmNode, type GroupNode, systemStatus, type Selection, type SystemNode } from '@/lib/overview'
  import type { Units } from '@/lib/units'

  import type { MapSystem } from './systems'

  // The map's list: farm › irrigation group › system › field as nested
  // cards, each inset in its parent, as on the dashboard and Setup. Every card selects its item: a
  // farm or group zooms the map to its systems, a system or field opens its panel. Each card carries
  // data-node="{level}-{id}" for the page to scroll the selection into view.
  let {
    tree,
    selection,
    today,
    units,
    weatherFor,
    onselect,
  }: {
    tree: FarmNode<MapSystem>[]
    selection: Selection | null
    today: string
    units: Units
    weatherFor: (system: MapSystem) => WeatherUpdate
    onselect: (selection: Selection) => void
  } = $props()

  const isSelected = (level: Selection['level'], id: number) => selection?.level === level && selection.id === id
  const frame = (level: Selection['level'], id: number) =>
    isSelected(level, id) ? 'border-brand-600 ring-2 ring-brand-500' : 'border-line'
  const header =
    'flex w-full min-w-0 items-center gap-1.5 rounded-t-lg px-2.5 py-1.5 text-left text-sm hover:bg-brand-50 ' +
    'focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-brand-500'
</script>

{#snippet systemCard(node: SystemNode<MapSystem>)}
  {@const { system } = node}
  {@const status = systemStatus(system.fields)}
  <li class="rounded-lg border bg-surface {frame('system', system.id)}" data-node="system-{system.id}">
    <button
      type="button"
      class={header}
      aria-pressed={isSelected('system', system.id)}
      aria-label="Show system {systemName(system)} on the map"
      onclick={() => onselect({ level: 'system', id: system.id })}
    >
      <KindIcon kind={system.kind} />
      <span class="min-w-0 flex-1 truncate">
        <span class="text-ink-muted">System:</span>
        <span class="font-medium" data-search-text>{systemName(system)}</span>
      </span>
      {#if status}<StatusBadge {status} size="icon" />{/if}
    </button>
    {#if node.fields.length}
      <ul class="space-y-1.5 p-1.5 pt-0">
        {#each node.fields as card (card.id)}
          <li data-node="field-{card.id}">
            <FieldCard
              {card}
              {today}
              {units}
              compact
              weather={weatherFor(system)}
              selected={isSelected('field', card.id)}
              onselect={() => onselect({ level: 'field', id: card.id })}
            />
          </li>
        {/each}
      </ul>
    {:else}
      <p class="px-2.5 pb-2 text-xs text-ink-muted">No fields yet. Add them in Setup.</p>
    {/if}
  </li>
{/snippet}

{#snippet groupCard(node: GroupNode<MapSystem>)}
  <li class="rounded-lg border border-dashed bg-surface-raised {frame('group', node.id)}" data-node="group-{node.id}">
    <button
      type="button"
      class={header}
      aria-pressed={isSelected('group', node.id)}
      aria-label="Zoom the map to the irrigation group {node.name}"
      onclick={() => onselect({ level: 'group', id: node.id })}
    >
      <span class="min-w-0 flex-1 truncate">
        <span class="text-ink-muted">Group:</span>
        <span class="font-medium" data-search-text>{node.name}</span>
      </span>
    </button>
    <ul class="space-y-1.5 p-1.5 pt-0">
      {#each node.systems as system (system.system.id)}
        {@render systemCard(system)}
      {/each}
    </ul>
  </li>
{/snippet}

<ul class="space-y-2">
  {#each tree as farm (farm.id)}
    <li class="rounded-lg border bg-surface-raised {frame('farm', farm.id)}" data-node="farm-{farm.id}">
      <button
        type="button"
        class={header}
        aria-pressed={isSelected('farm', farm.id)}
        aria-label="Zoom the map to the farm {farm.name}"
        onclick={() => onselect({ level: 'farm', id: farm.id })}
      >
        <span class="min-w-0 flex-1 truncate">
          <span class="text-ink-muted">Farm:</span>
          <span class="font-medium" data-search-text>{farm.name}</span>
        </span>
      </button>
      {#if farm.children.length}
        <ul class="space-y-1.5 p-1.5 pt-0">
          {#each farm.children as child (`${child.kind}-${child.kind === 'group' ? child.id : child.system.id}`)}
            {#if child.kind === 'group'}
              {@render groupCard(child)}
            {:else}
              {@render systemCard(child)}
            {/if}
          {/each}
        </ul>
      {:else}
        <p class="px-2.5 pb-2 text-xs text-ink-muted">No irrigation systems yet. Add one in Setup.</p>
      {/if}
    </li>
  {/each}
</ul>
