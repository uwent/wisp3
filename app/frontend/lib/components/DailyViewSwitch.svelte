<script lang="ts" module>
  /** The daily entry view last chosen in this browser: 'week' takes /daily (the nav's link) to the week */
  export const DAILY_VIEW_KEY = 'wisp:daily-view'
</script>

<script lang="ts">
  import { Link } from '@inertiajs/svelte'

  import { dailyEntries, dailyEntryWeeks } from '@/routes'

  // Daily entry's Day | Week switch, keeping the date: the day shown, or the week's last
  // day. The Day link says view=day, which the day page remembers (and never sends on to the week).
  let { view, date }: { view: 'day' | 'week'; date: string } = $props()

  const options = $derived([
    { key: 'day', name: 'Day', href: dailyEntries.show({ query: { date, view: 'day' } }) },
    { key: 'week', name: 'Week', href: dailyEntryWeeks.show({ query: { date } }) },
  ])
</script>

<div class="flex overflow-hidden rounded-md border border-line text-sm" role="group" aria-label="View">
  {#each options as option (option.key)}
    <Link
      href={option.href}
      class="px-3 py-1.5 {view === option.key
        ? 'bg-brand-600 text-white dark:text-surface'
        : 'bg-surface-raised hover:bg-surface'}"
      aria-current={view === option.key ? 'page' : undefined}>{option.name}</Link
    >
  {/each}
</div>
