<script lang="ts">
  import { Link, page } from '@inertiajs/svelte'
  import { systemName } from '@/lib/geo'
  import { isExample } from '@/lib/permissions'

  import FieldCard from '@/lib/components/FieldCard.svelte'
  import FieldRow from '@/lib/components/FieldRow.svelte'
  import GettingStarted from '@/lib/components/GettingStarted.svelte'
  import LogIrrigationDialog from '@/lib/components/LogIrrigationDialog.svelte'
  import RainAhead, { type RainZone } from '@/lib/components/RainAhead.svelte'
  import StatusCounts from '@/lib/components/StatusCounts.svelte'
  import { formatDate } from '@/lib/dates'
  import type { LogSystemProps } from '@/lib/logIrrigation'
  import {
    filterByStatus,
    needsWaterFirst,
    updatingIds,
    type FarmGroup,
    type FieldCard as Card,
    type OverviewSystem,
    type StatusFilter,
  } from '@/lib/overview'
  import { readStored, writeStored } from '@/lib/storage'
  import { pollWeather } from '@/lib/weatherPolling.svelte'
  import { currentUnits } from '@/lib/units'
  import { dailyEntries, pivots, setup } from '@/routes'

  let {
    today,
    farms,
    getting_started,
    rain,
    log_dates,
  }: {
    today: string
    /** Each system with what logging its irrigation needs (DashboardController#log_props) */
    farms: FarmGroup<OverviewSystem & LogSystemProps>[]
    /** Until the operation has any planting: what's set up so far */
    getting_started: { farms: number; systems: number; fields: number } | null
    /** The week's rain in each weather zone of the operation's systems */
    rain: RainZone[]
    /** The day the log irrigation dialog starts on, and the first and last it offers */
    log_dates: { default: string; from: string; to: string }
  } = $props()

  const units = $derived(currentUnits())
  let farmId = $state<number | 'all'>('all')

  // Cards or a list, by farm and system or most urgent first: remembered in this browser (a phone
  // can keep the list, a desktop the cards). The status filter lasts for this visit.
  const VIEW_KEY = 'wisp:dashboard-view'
  const ORDER_KEY = 'wisp:dashboard-order'
  type View = 'cards' | 'list'
  type Order = 'system' | 'urgent'
  let view = $state<View>(readStored(VIEW_KEY) === 'list' ? 'list' : 'cards')
  let order = $state<Order>(readStored(ORDER_KEY) === 'urgent' ? 'urgent' : 'system')
  let statusFilter = $state<StatusFilter | null>(null)
  const VIEWS: { key: View; name: string }[] = [
    { key: 'cards', name: 'Cards' },
    { key: 'list', name: 'List' },
  ]
  function chooseView(next: View) {
    view = next
    writeStored(VIEW_KEY, next)
  }

  // While a pivot's weather is on its way, reload the cards until it lands
  const weatherWait = pollWeather(() => updatingIds(farms), ['farms', 'rain'])
  const weatherFor = (pivot: { weather_updating: boolean }) => weatherWait.state(pivot.weather_updating)

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
  const filtered = $derived(filterByStatus(shown, statusFilter))
  const flat = $derived(order === 'urgent' ? needsWaterFirst(filtered) : [])
  // Where a field is, when the list isn't under its farm and system
  const place = (pivot: OverviewSystem, farm: FarmGroup) =>
    farms.length > 1 && farmId === 'all' ? `${systemName(pivot)} · ${farm.name}` : systemName(pivot)
  // The zones of the farm chosen's systems
  const rainZones = $derived.by(() => {
    const systemIds = new Set(shown.flatMap((farm) => farm.pivots.map((pivot) => pivot.id)))
    return rain.filter((zone) => zone.pivot_ids.some((id) => systemIds.has(id)))
  })
  // Log irrigation: one dialog, for the system (and field) it was opened
  // for, found in the unfiltered farms so it has all the system's fields
  let logOpen = $state(false)
  let logging = $state<{ systemId: number; fieldId: number | null } | null>(null)
  const logSystem = $derived(
    logging && farms.flatMap((farm) => farm.pivots).find((pivot) => pivot.id === logging!.systemId),
  )
  const logRain = $derived((logging && rain.find((zone) => zone.pivot_ids.includes(logging!.systemId))?.days) ?? [])
  function logIrrigation(systemId: number, fieldId: number | null = null) {
    logging = { systemId, fieldId }
    logOpen = true
  }
  const readOnly = $derived(isExample(page.props))
  // "Irrigated since …?" due on one of the card's plantings
  const irrigationDue = (card: Card) =>
    card.plantings.some(
      (summary) =>
        summary.phase === 'active' && summary.tasks.some((task) => task.kind === 'irrigation_check' && task.due),
    )

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
      <label class="sr-only" for="dashboard-order">Order</label>
      <select
        id="dashboard-order"
        class="rounded-md text-sm"
        bind:value={order}
        onchange={() => writeStored(ORDER_KEY, order)}
      >
        <option value="system">By system</option>
        <option value="urgent">Needs water first</option>
      </select>
      <div class="flex overflow-hidden rounded-md border border-line text-sm" role="group" aria-label="View">
        {#each VIEWS as { key, name } (key)}
          <button
            type="button"
            class="px-3 py-1.5 {view === key
              ? 'bg-brand-600 text-white dark:text-surface'
              : 'bg-surface-raised hover:bg-surface'}"
            aria-pressed={view === key}
            onclick={() => chooseView(key)}>{name}</button
          >
        {/each}
      </div>
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
{#snippet systemHeading(pivot: OverviewSystem)}
  <!-- The links wrap under the name rather than squeezing it (a phone) -->
  <div class="flex flex-wrap items-center justify-between gap-x-3 gap-y-1">
    <h3 id="pivot-{pivot.id}" class="min-w-0 flex-1 basis-56 truncate font-medium">
      <span class="font-normal text-ink-muted">Irrigation system:</span>
      <Link
        href={pivots.show(pivot.id)}
        class="underline decoration-ink-muted/50 underline-offset-4 hover:decoration-current">{systemName(pivot)}</Link
      >
    </h3>
    <div class="flex shrink-0 items-center gap-2 text-sm">
      {#if !readOnly}
        <button
          type="button"
          class="text-brand-600 hover:underline"
          aria-label="Log irrigation on {pivot.name}"
          onclick={() => logIrrigation(pivot.id)}>Log irrigation</button
        >
        <span class="text-ink-muted" aria-hidden="true">·</span>
      {/if}
      <Link href={pivots.show(pivot.id)} class="text-brand-600 hover:underline" aria-label="View {pivot.name}"
        >View</Link
      >
      {#if !readOnly}
        <span class="text-ink-muted" aria-hidden="true">·</span>
        <Link href={pivots.edit(pivot.id)} class="text-brand-600 hover:underline" aria-label="Edit {pivot.name}"
          >Edit</Link
        >
      {/if}
    </div>
  </div>
{/snippet}

<!-- Needs water first has no system headings: a field asked "Irrigated since …?" offers the dialog under it -->
{#snippet logFromCard(card: Card, pivot: OverviewSystem, padding: string)}
  {#if !readOnly && irrigationDue(card)}
    <p class="text-xs {padding}">
      <button
        type="button"
        class="text-brand-600 underline underline-offset-2"
        aria-label="Log irrigation on {systemName(pivot)} for {card.name}"
        onclick={() => logIrrigation(pivot.id, card.id)}>Log irrigation on {systemName(pivot)}</button
      >
    </p>
  {/if}
{/snippet}

{#snippet noFields()}
  <p class="text-sm text-ink-muted">
    No fields yet. <Link href={setup.show()} class="text-brand-600 underline underline-offset-2">Add them in setup</Link
    >.
  </p>
{/snippet}

{#if farms.length}
  {#if anyFields && !getting_started}
    <RainAhead zones={rainZones} {units} {today} />
    <StatusCounts {cards} selected={statusFilter} onselect={(filter) => (statusFilter = filter)} />
  {/if}

  {#if statusFilter && !filtered.length}
    <p class="text-sm text-ink-muted">No fields at this status.</p>
  {:else if order === 'urgent'}
    <!-- Needs water first: every field in one list or grid, each naming its system -->
    <section aria-label="Fields, most urgent first">
      {#if view === 'list'}
        <ul class="divide-y divide-line overflow-hidden rounded-lg border border-line bg-surface-raised">
          {#each flat as { card, pivot, farm } (card.id)}
            <li>
              <FieldRow {card} {today} {units} weather={weatherFor(pivot)} context={place(pivot, farm)} />
              {@render logFromCard(card, pivot, 'px-3 pb-2')}
            </li>
          {/each}
        </ul>
      {:else}
        <ul class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {#each flat as { card, pivot, farm } (card.id)}
            <li class="space-y-1">
              <FieldCard {card} {today} {units} weather={weatherFor(pivot)} context={place(pivot, farm)} />
              {@render logFromCard(card, pivot, 'px-1')}
            </li>
          {/each}
        </ul>
      {/if}
    </section>
  {:else}
    {#each filtered as farm (farm.id)}
      <section class="space-y-3" aria-labelledby="farm-{farm.id}">
        <h2 id="farm-{farm.id}" class="text-lg font-medium">
          <span class="font-normal text-ink-muted">Farm:</span>
          {farm.name}
        </h2>
        {#each farm.pivots as pivot (pivot.id)}
          {#if view === 'list'}
            <!-- The list: systems as plain headings over their rows -->
            <section class="space-y-2" aria-labelledby="pivot-{pivot.id}">
              {@render systemHeading(pivot)}
              {#if pivot.fields.length === 0}
                {@render noFields()}
              {:else}
                <ul class="divide-y divide-line overflow-hidden rounded-lg border border-line bg-surface-raised">
                  {#each pivot.fields as card (card.id)}
                    <li><FieldRow {card} {today} {units} weather={weatherFor(pivot)} /></li>
                  {/each}
                </ul>
              {/if}
            </section>
          {:else}
            <section
              class="space-y-3 rounded-lg border border-line bg-surface p-3 sm:p-4"
              aria-labelledby="pivot-{pivot.id}"
            >
              {@render systemHeading(pivot)}
              {#if pivot.fields.length === 0}
                {@render noFields()}
              {:else}
                <ul class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
                  {#each pivot.fields as card (card.id)}
                    <li><FieldCard {card} {today} {units} weather={weatherFor(pivot)} /></li>
                  {/each}
                </ul>
              {/if}
            </section>
          {/if}
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
{/if}

{#if logSystem}
  <LogIrrigationDialog
    bind:open={logOpen}
    system={logSystem}
    field={logging?.fieldId ?? null}
    rain={logRain}
    dates={log_dates}
    {today}
    {units}
  />
{/if}
