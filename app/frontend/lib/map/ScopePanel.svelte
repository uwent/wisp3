<script lang="ts">
  import { Link } from '@inertiajs/svelte'

  import KindIcon from '@/lib/components/KindIcon.svelte'
  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import { systemName } from '@/lib/geo'
  import { type FarmNode, type GroupNode, pivotStatus, type Selection, type SystemNode } from '@/lib/overview'
  import { editLink } from '@/lib/setup/links'

  import type { MapPivot } from './pivots'

  // A selected farm or irrigation group over the map (Ben, 2026-11-17), as PivotPanel is a system's:
  // its Edit link (farms and groups have no page of their own to view), and what's in it as in the
  // list (groups and systems), each selecting itself. A group names its farm, which selects it.
  let {
    node,
    farm,
    onselect,
    onclose,
  }: {
    node: FarmNode<MapPivot> | GroupNode<MapPivot>
    /** The group's farm (for a group) */
    farm?: { id: number; name: string }
    onselect: (selection: Selection) => void
    onclose: () => void
  } = $props()

  const level = $derived(node.kind === 'farm' ? 'farm' : 'group')
  const noun = $derived(node.kind === 'farm' ? 'Farm' : 'Group')
  const fieldCount = (system: SystemNode<MapPivot>) =>
    system.fields.length === 1 ? '1 field' : `${system.fields.length} fields`
  const row =
    'flex w-full min-w-0 items-center gap-1.5 rounded-md border border-line bg-surface-raised px-2.5 py-1.5 text-left ' +
    'text-sm hover:border-brand-500 focus-visible:outline-2 focus-visible:outline-brand-500'
</script>

{#snippet systemRow(system: SystemNode<MapPivot>)}
  {@const status = pivotStatus(system.fields)}
  <button
    type="button"
    class={row}
    aria-label="Show system {systemName(system.pivot)} on the map"
    onclick={() => onselect({ level: 'system', id: system.pivot.id })}
  >
    <KindIcon kind={system.pivot.kind} />
    <span class="min-w-0 flex-1 truncate">
      <span class="text-ink-muted">System:</span>
      <span class="font-medium">{systemName(system.pivot)}</span>
    </span>
    <span class="shrink-0 text-xs text-ink-muted">{fieldCount(system)}</span>
    {#if status}<StatusBadge {status} size="icon" />{/if}
  </button>
{/snippet}

<section
  class="pointer-events-auto flex max-h-full flex-col overflow-hidden rounded-lg border border-line bg-surface shadow-xl
    focus-visible:outline-2 focus-visible:outline-brand-500"
  aria-labelledby="scope-panel-title"
  tabindex="-1"
  data-pivot-panel
>
  <header class="flex items-start justify-between gap-2 border-b border-line bg-surface-raised px-3 py-2">
    <div class="min-w-0">
      {#if farm}
        <button
          type="button"
          class="block max-w-full truncate text-xs text-ink-muted hover:text-ink hover:underline"
          aria-label="Show the farm {farm.name}"
          onclick={() => onselect({ level: 'farm', id: farm.id })}>Farm: {farm.name}</button
        >
      {/if}
      <h2 id="scope-panel-title" class="truncate font-medium">
        <span class="font-normal text-ink-muted">{noun}:</span>
        {node.name}
      </h2>
      <div class="flex gap-3 text-xs">
        <Link href={editLink(level, node.id)} class="text-brand-600 hover:underline" aria-label="Edit {node.name}"
          >Edit</Link
        >
      </div>
    </div>
    <button
      type="button"
      class="-mr-1 rounded-md px-2 py-1 text-lg leading-none text-ink-muted hover:bg-surface hover:text-ink"
      aria-label="Close"
      onclick={onclose}>×</button
    >
  </header>
  <div class="overflow-y-auto p-3">
    <ul class="space-y-1.5">
      {#if node.kind === 'farm'}
        {#each node.children as child (`${child.kind}-${child.kind === 'group' ? child.id : child.pivot.id}`)}
          <li>
            {#if child.kind === 'group'}
              <button
                type="button"
                class="{row} border-dashed"
                aria-label="Show the irrigation group {child.name}"
                onclick={() => onselect({ level: 'group', id: child.id })}
              >
                <span class="min-w-0 flex-1 truncate">
                  <span class="text-ink-muted">Group:</span>
                  <span class="font-medium">{child.name}</span>
                </span>
                <span class="shrink-0 text-xs text-ink-muted"
                  >{child.systems.length === 1 ? '1 system' : `${child.systems.length} systems`}</span
                >
              </button>
            {:else}
              {@render systemRow(child)}
            {/if}
          </li>
        {:else}
          <li class="text-sm text-ink-muted">No irrigation systems shown.</li>
        {/each}
      {:else}
        {#each node.systems as system (system.pivot.id)}
          <li>{@render systemRow(system)}</li>
        {/each}
      {/if}
    </ul>
  </div>
</section>
