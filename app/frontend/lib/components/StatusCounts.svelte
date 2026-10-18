<script lang="ts">
  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import { LEAD_DAYS } from '@/lib/outlook'
  import { type FieldCard, STATUSES } from '@/lib/overview'

  // How many fields are at each status, and how many seasons have ended (dashboard and map)
  let { cards }: { cards: FieldCard[] } = $props()

  const counts = $derived(
    STATUSES.map((status) => ({
      status,
      count: cards.filter((card) => card.summary?.phase === 'active' && card.summary.status === status).length,
    })),
  )
  const ended = $derived(cards.filter((card) => card.summary?.phase === 'ended').length)

  const fieldCount = (count: number) => `${count} field${count === 1 ? '' : 's'}`
  const tips = {
    irrigate: (count: number) => `${fieldCount(count)} at or below the irrigation point today`,
    caution: (count: number) =>
      `${fieldCount(count)} running low, or projected to need irrigation within ${LEAD_DAYS} days`,
    ok: (count: number) => `${fieldCount(count)} with enough water for now`,
    full: (count: number) => `${fieldCount(count)} near field capacity`,
  }
</script>

<div class="flex flex-wrap gap-2 text-sm" aria-label="Fields by status">
  {#each counts as { status, count } (status)}
    {#if count}
      <span class="flex items-center gap-1.5" title={tips[status](count)}
        ><StatusBadge {status} size="sm" /> {count}</span
      >
    {/if}
  {/each}
  {#if ended}
    <span class="flex items-center gap-1.5" title="{fieldCount(ended)} whose season has ended"
      ><span class="shrink-0 rounded-full border border-line px-2 py-0.5 text-xs text-ink-muted">Season ended</span>
      {ended}</span
    >
  {/if}
</div>
