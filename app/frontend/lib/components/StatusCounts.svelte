<script lang="ts">
  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import { LEAD_DAYS } from '@/lib/outlook'
  import { type FieldCard, primary, STATUSES, type StatusFilter } from '@/lib/overview'

  // How many fields are at each status (a field of plots at its most urgent planting's), and how
  // many seasons have ended (dashboard and map). With onselect (the dashboard), each count is a
  // toggle showing only the fields at that status: one at a time, clicked again or Show all to clear.
  let {
    cards,
    selected = null,
    onselect,
  }: {
    cards: FieldCard[]
    selected?: StatusFilter | null
    onselect?: (filter: StatusFilter | null) => void
  } = $props()

  const summaries = $derived(cards.map(primary))

  const counts = $derived(
    STATUSES.map((status) => ({
      status,
      count: summaries.filter((summary) => summary?.phase === 'active' && summary.status === status).length,
    })),
  )
  const ended = $derived(summaries.filter((summary) => summary?.phase === 'ended').length)

  const fieldCount = (count: number) => `${count} field${count === 1 ? '' : 's'}`
  const tips: Record<StatusFilter, (count: number) => string> = {
    irrigate: (count) => `${fieldCount(count)} at or below the irrigation point today`,
    caution: (count) => `${fieldCount(count)} running low, or projected to need irrigation within ${LEAD_DAYS} days`,
    needs_canopy: (count) =>
      `${fieldCount(count)} with no canopy curve or reading, so WISP can't estimate water use yet`,
    ok: (count) => `${fieldCount(count)} with enough water for now`,
    full: (count) => `${fieldCount(count)} near field capacity`,
    stressed: (count) => `${fieldCount(count)} of rainfed crops short of water today`,
    stress_coming: (count) =>
      `${fieldCount(count)} of rainfed crops projected to run short of water within ${LEAD_DAYS} days`,
    no_stress: (count) => `${fieldCount(count)} of rainfed crops with enough water`,
    ended: (count) => `${fieldCount(count)} whose season has ended`,
  }
  const toggle = (filter: StatusFilter) => onselect?.(selected === filter ? null : filter)
</script>

{#snippet item(filter: StatusFilter, count: number)}
  {#if filter === 'ended'}
    <span class="shrink-0 rounded-full border border-line px-2 py-0.5 text-xs text-ink-muted">Season ended</span>
  {:else}
    <StatusBadge status={filter} size="sm" />
  {/if}
  {count}<span class="sr-only">{count === 1 ? ' field' : ' fields'}</span>
{/snippet}

{#snippet entry(filter: StatusFilter, count: number)}
  {#if onselect}
    <button
      type="button"
      class="relative flex min-h-9 items-center gap-1.5 rounded-full border px-2 {selected === filter
        ? 'border-brand-600 bg-surface-raised ring-1 ring-brand-600'
        : 'border-transparent hover:border-line'}"
      title="{tips[filter](count)}. {selected === filter ? 'Show all fields' : 'Show only these'}."
      aria-pressed={selected === filter}
      onclick={() => toggle(filter)}>{@render item(filter, count)}</button
    >
  {:else}
    <span class="relative flex items-center gap-1.5" title={tips[filter](count)}>{@render item(filter, count)}</span>
  {/if}
{/snippet}

<div
  class="flex flex-wrap items-center text-sm {onselect ? 'gap-1' : 'gap-2'}"
  role="group"
  aria-label={onselect ? 'Show fields by status' : 'Fields by status'}
>
  {#each counts as { status, count } (status)}
    {#if count || selected === status}{@render entry(status, count)}{/if}
  {/each}
  {#if ended || selected === 'ended'}{@render entry('ended', ended)}{/if}
  {#if onselect && selected}
    <button
      type="button"
      class="min-h-9 px-2 text-brand-600 underline underline-offset-2 hover:decoration-2"
      onclick={() => onselect(null)}>Show all</button
    >
  {/if}
</div>
