<script lang="ts">
  import { Link, page } from '@inertiajs/svelte'

  import FieldCard from '@/lib/components/FieldCard.svelte'
  import StatusCounts from '@/lib/components/StatusCounts.svelte'
  import { formatDate } from '@/lib/dates'
  import type { FarmGroup, FieldCard as Card } from '@/lib/overview'
  import { units as unitsFor } from '@/lib/units'
  import { dailyEntries, newQuickSetup, pivots, setup } from '@/routes'

  let { today, farms }: { today: string; farms: FarmGroup[] } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  let farmId = $state<number | 'all'>('all')

  // Fields whose season has ended go after the rest, and so do pivots and farms with only ended fields
  // (the sort is stable, so names stay in order otherwise)
  const ended = (card: Card) => card.summary?.phase === 'ended'
  const allEnded = (cards: Card[]) => cards.length > 0 && cards.every(ended)
  const endedLast = <T,>(items: T[], isEnded: (item: T) => boolean) =>
    items.toSorted((a, b) => Number(isEnded(a)) - Number(isEnded(b)))
  const sorted = $derived(
    endedLast(
      farms.map((farm) => ({
        ...farm,
        pivots: endedLast(
          farm.pivots.map((pivot) => ({ ...pivot, fields: endedLast(pivot.fields, ended) })),
          (pivot) => allEnded(pivot.fields),
        ),
      })),
      (farm) => allEnded(farm.pivots.flatMap((pivot) => pivot.fields)),
    ),
  )

  const shown = $derived(sorted.filter((farm) => farmId === 'all' || farm.id === farmId))
  const cards = $derived(shown.flatMap((farm) => farm.pivots.flatMap((pivot) => pivot.fields)))
  const anyFields = $derived(farms.some((farm) => farm.pivots.some((pivot) => pivot.fields.length)))
</script>

<svelte:head><title>Dashboard · WISP</title></svelte:head>

<div class="flex flex-wrap items-end justify-between gap-3">
  <div>
    <h1 class="text-2xl font-semibold">Dashboard</h1>
    <p class="text-sm text-ink-muted">
      {page.props.auth.group?.name} · {formatDate(today, { weekday: true, year: true })}
    </p>
  </div>
  {#if anyFields}
    <div class="flex flex-wrap items-center gap-2">
      {#if farms.length > 1}
        <label class="sr-only" for="farm-filter">Farm</label>
        <select id="farm-filter" class="rounded-md text-sm" bind:value={farmId}>
          <option value="all">All farms</option>
          {#each farms as farm (farm.id)}<option value={farm.id}>{farm.name}</option>{/each}
        </select>
      {/if}
      <Link
        href={dailyEntries.show()}
        class="rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 dark:text-surface"
      >
        Enter rain and irrigation
      </Link>
    </div>
  {/if}
</div>

{#if farms.length === 0}
  <section class="rounded-lg border border-dashed border-line bg-surface-raised px-6 py-12 text-center">
    <h2 class="text-lg font-medium">Set up your first pivot</h2>
    <p class="mx-auto mt-2 max-w-md text-sm text-ink-muted">
      Place it on the map and add its fields and crops. It takes a few minutes, and WISP starts tracking each field's
      soil water straight away.
    </p>
    <Link
      href={newQuickSetup()}
      class="mt-6 inline-block rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 dark:text-surface"
    >
      Get started
    </Link>
  </section>
{:else}
  {#if !anyFields}
    <section class="rounded-lg border border-dashed border-line bg-surface-raised px-6 py-8 text-center">
      <h2 class="text-lg font-medium">No fields yet</h2>
      <p class="mt-2 text-sm text-ink-muted">Add fields to your pivots to see their water status here.</p>
      <Link href={setup.show()} class="mt-4 inline-block text-sm text-brand-600 hover:underline">Go to setup</Link>
    </section>
  {:else}
    <StatusCounts {cards} />
  {/if}

  {#each shown as farm (farm.id)}
    <section class="space-y-3" aria-labelledby="farm-{farm.id}">
      <h2 id="farm-{farm.id}" class="text-lg font-medium">
        <span class="font-normal text-ink-muted">Farm:</span>
        {farm.name}
      </h2>
      {#each farm.pivots as pivot (pivot.id)}
        <section
          class="space-y-3 rounded-lg border border-line bg-surface p-3 sm:p-4"
          aria-labelledby="pivot-{pivot.id}"
        >
          <div class="flex items-center justify-between gap-3">
            <h3 id="pivot-{pivot.id}" class="min-w-0 truncate font-medium">
              <span class="font-normal text-ink-muted">Pivot:</span>
              {pivot.name}
            </h3>
            <div class="flex shrink-0 gap-3 text-sm">
              <Link href={pivots.show(pivot.id)} class="text-brand-600 hover:underline" aria-label="View {pivot.name}"
                >View</Link
              >
              <Link href={pivots.edit(pivot.id)} class="text-brand-600 hover:underline" aria-label="Edit {pivot.name}"
                >Edit</Link
              >
            </div>
          </div>
          {#if pivot.fields.length === 0}
            <p class="text-sm text-ink-muted">
              No fields yet. <Link href={setup.show()} class="text-brand-600 hover:underline">Add them in setup</Link>.
            </p>
          {:else}
            <ul class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {#each pivot.fields as card (card.id)}
                <li><FieldCard {card} {today} {units} /></li>
              {/each}
            </ul>
          {/if}
        </section>
      {/each}
      {#if farm.pivots.length === 0}
        <p class="text-sm text-ink-muted">
          No pivots yet. <Link href={setup.show()} class="text-brand-600 hover:underline">Add one in setup</Link>.
        </p>
      {/if}
    </section>
  {/each}
{/if}
