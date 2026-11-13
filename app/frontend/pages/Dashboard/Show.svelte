<script lang="ts">
  import { Link, page, router } from '@inertiajs/svelte'
  import { systemName } from '@/lib/geo'

  import FieldCard from '@/lib/components/FieldCard.svelte'
  import GettingStarted from '@/lib/components/GettingStarted.svelte'
  import StatusCounts from '@/lib/components/StatusCounts.svelte'
  import { formatDate } from '@/lib/dates'
  import { anyUpdating, updatingIds, type FarmGroup, type FieldCard as Card } from '@/lib/overview'
  import { poll, weatherUpdate } from '@/lib/poll'
  import { units as unitsFor } from '@/lib/units'
  import { dailyEntries, pivots, setup } from '@/routes'

  let {
    today,
    farms,
    getting_started,
  }: {
    today: string
    farms: FarmGroup[]
    /** Until the operation has any planting: what's set up so far (PLAN.md G.6) */
    getting_started: { farms: number; systems: number; fields: number } | null
  } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  let farmId = $state<number | 'all'>('all')

  // While a pivot's weather is on its way, reload the cards until it lands
  const updating = $derived(anyUpdating(farms))
  let timedOut = $state(false)
  $effect(() => {
    if (!updating) return
    timedOut = false
    return poll(
      () => updatingIds(farms),
      (done) => router.reload({ only: ['farms'], onFinish: done }),
      { ongiveup: () => (timedOut = true) },
    )
  })
  const weatherFor = (pivot: { weather_updating: boolean }) => weatherUpdate(pivot.weather_updating, timedOut)

  // Fields whose season has ended go after the rest, and so do pivots and farms with only ended fields
  // (the sort is stable, so names stay in order otherwise)
  const ended = (card: Card) =>
    card.plantings.length > 0 && card.plantings.every((summary) => summary.phase === 'ended')
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

{#if getting_started}
  <GettingStarted progress={getting_started} year={Number(today.slice(0, 4))} />
{/if}
{#if farms.length}
  {#if anyFields && !getting_started}
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
              <span class="font-normal text-ink-muted">Irrigation system:</span>
              <Link
                href={pivots.show(pivot.id)}
                class="underline decoration-ink-muted/50 underline-offset-4 hover:decoration-current"
                >{systemName(pivot)}</Link
              >
            </h3>
            <div class="flex shrink-0 gap-3 text-sm">
              <Link
                href={pivots.show(pivot.id)}
                class="text-brand-600 hover:underline"
                aria-label="Irrigation on {pivot.name}">Irrigation</Link
              >
              <Link href={pivots.edit(pivot.id)} class="text-brand-600 hover:underline" aria-label="Edit {pivot.name}"
                >Edit</Link
              >
            </div>
          </div>
          {#if pivot.fields.length === 0}
            <p class="text-sm text-ink-muted">
              No fields yet. <Link href={setup.show()} class="text-brand-600 underline underline-offset-2"
                >Add them in setup</Link
              >.
            </p>
          {:else}
            <ul class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {#each pivot.fields as card (card.id)}
                <li><FieldCard {card} {today} {units} weather={weatherFor(pivot)} /></li>
              {/each}
            </ul>
          {/if}
        </section>
      {/each}
      {#if farm.pivots.length === 0}
        <p class="text-sm text-ink-muted">
          No irrigation systems yet. <Link href={setup.show()} class="text-brand-600 underline underline-offset-2"
            >Add one in setup</Link
          >.
        </p>
      {/if}
    </section>
  {/each}
{/if}
