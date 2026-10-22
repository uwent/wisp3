<script lang="ts">
  import { onDestroy, tick, untrack } from 'svelte'
  import { Link, page } from '@inertiajs/svelte'

  import FieldCard from '@/lib/components/FieldCard.svelte'
  import StatusCounts from '@/lib/components/StatusCounts.svelte'
  import { formatDate } from '@/lib/dates'
  import type { LngLat } from '@/lib/geo'
  import LayersControl from '@/lib/map/LayersControl.svelte'
  import { MapOverlays } from '@/lib/map/mapOverlays.svelte'
  import OverlayTooltip from '@/lib/map/OverlayTooltip.svelte'
  import OverviewMap from '@/lib/map/OverviewMap.svelte'
  import PivotPanel from '@/lib/map/PivotPanel.svelte'
  import { droughtAt, droughtBounds, type OverlayId } from '@/lib/map/overlays'
  import type { MapPivot } from '@/lib/map/pivots'
  import { loadPrefs, savePrefs } from '@/lib/map/prefs'
  import { type FarmGroup, type ListItem, needsWaterWithin, sortItems } from '@/lib/overview'
  import { units as unitsFor } from '@/lib/units'
  import { newQuickSetup } from '@/routes'

  // Every pivot on a map with its fields' status, beside a list of the fields (PLAN.md Phase 7).
  // Selecting a field in the list or a pivot on the map selects it in both.
  let { today, farms }: { today: string; farms: FarmGroup<MapPivot>[] } = $props()

  const auth = $derived(page.props.auth)
  const units = $derived(unitsFor(auth.user?.unit_system))
  const groupId = page.props.auth.group?.id

  const prefs = $state(loadPrefs(groupId))
  $effect(() => savePrefs(groupId, $state.snapshot(prefs)))

  let farmId = $state<number | 'all'>('all')
  /** Days ahead for "needs water within", or null for no window */
  let windowDays = $state<number | null>(null)
  let query = $state('')
  let selectedPivotId = $state<number | null>(null)
  let selectedFieldId = $state<number | null>(null)
  let overview = $state<OverviewMap>()
  let mapWidth = $state(0)
  let mapHeight = $state(0)

  // Optional public layers; the drought polygons are loaded around all the operation's pivots
  const overlays = new MapOverlays(() =>
    droughtBounds(farms.flatMap((farm) => farm.pivots.map((pivot): LngLat => [pivot.longitude, pivot.latitude]))),
  )
  // The controller records each overlay's status as it goes, so it runs untracked here
  $effect(() => {
    const shown = [...(prefs.rain ? [prefs.rain] : []), ...prefs.overlays] as OverlayId[]
    const opacity = { ...prefs.opacity }
    untrack(() => overlays.sync(shown, opacity))
  })
  onDestroy(() => overlays.destroy())
  let list = $state<HTMLElement>()

  const shown = $derived(farms.filter((farm) => farmId === 'all' || farm.id === farmId))
  const mapPivots = $derived(shown.flatMap((farm) => farm.pivots))
  const farmOf = $derived(new Map(farms.flatMap((farm) => farm.pivots.map((pivot) => [pivot.id, farm]))))
  const items = $derived<ListItem[]>(
    shown.flatMap((farm) =>
      farm.pivots.flatMap((pivot) =>
        pivot.fields.map((card) => ({
          card,
          pivot: { id: pivot.id, name: pivot.name, latitude: pivot.latitude },
          farm: { id: farm.id, name: farm.name },
        })),
      ),
    ),
  )
  const matches = (item: ListItem) => {
    const text = query.trim().toLowerCase()
    return !text || `${item.card.name} ${item.pivot.name} ${item.farm.name}`.toLowerCase().includes(text)
  }
  const listed = $derived(
    sortItems(
      items.filter((item) => matches(item) && (windowDays === null || needsWaterWithin(item.card, windowDays))),
      prefs.sort,
    ),
  )
  const highlighted = $derived(
    windowDays === null
      ? null
      : new Set(items.filter((item) => needsWaterWithin(item.card, windowDays!)).map((item) => item.pivot.id)),
  )
  const selectedPivot = $derived(mapPivots.find((pivot) => pivot.id === selectedPivotId) ?? null)
  const anyPivots = $derived(farms.some((farm) => farm.pivots.length))
  // The Drought Monitor's category at the selected pivot, when that layer is on
  const panelNotes = $derived.by(() => {
    if (!selectedPivot || !prefs.overlays.includes('drought') || !overlays.drought) return []
    const category = droughtAt(overlays.drought, [selectedPivot.longitude, selectedPivot.latitude])
    return [{ label: 'Drought Monitor', value: category?.label ?? 'None', swatch: category?.color }]
  })

  const WINDOWS = [
    { days: null, label: 'Any time' },
    { days: 0, label: 'Today' },
    { days: 3, label: '3 days' },
    { days: 7, label: '7 days' },
  ]

  function chooseFarm(id: number | 'all') {
    farmId = id
    if (selectedPivotId !== null && farmOf.get(selectedPivotId)?.id !== id && id !== 'all') clearSelection()
    overview?.fit(mapPivots)
  }

  function chooseWindow(days: number | null) {
    windowDays = days
    const inWindow = mapPivots.filter((pivot) => highlighted?.has(pivot.id))
    if (inWindow.length) overview?.fit(inWindow)
  }

  // From the keyboard, selecting a pivot moves focus to its panel, and closing the panel returns
  // focus to the marker or card that opened it (pointer users stay where they are)
  let keyboard = false
  let opener: HTMLElement | null = null

  function focusPanel() {
    if (!keyboard) return
    opener = document.activeElement instanceof HTMLElement ? document.activeElement : null
    tick().then(() => document.querySelector<HTMLElement>('[data-pivot-panel]')?.focus())
  }

  function selectField(item: ListItem) {
    selectedPivotId = item.pivot.id
    selectedFieldId = item.card.id
    overview?.show(item.pivot.id)
    focusPanel()
  }

  function selectPivot(pivotId: number | null) {
    selectedPivotId = pivotId
    selectedFieldId = null
    if (pivotId !== null) focusPanel()
    if (pivotId === null || !prefs.listOpen) return
    // Bring its fields' cards into view in the list
    requestAnimationFrame(() =>
      list?.querySelector(`[data-pivot="${pivotId}"]`)?.scrollIntoView({ block: 'nearest', behavior: 'smooth' }),
    )
  }

  function clearSelection() {
    const fromPanel = document.querySelector('[data-pivot-panel]')?.contains(document.activeElement)
    selectedPivotId = null
    selectedFieldId = null
    if (fromPanel) opener?.focus()
    opener = null
  }

  const isSelected = (item: ListItem) =>
    selectedFieldId !== null ? item.card.id === selectedFieldId : item.pivot.id === selectedPivotId
</script>

<svelte:head><title>Map · WISP</title></svelte:head>
<svelte:window
  onkeydown={(event) => {
    keyboard = true
    if (event.key === 'Escape') clearSelection()
  }}
  onpointerdown={() => (keyboard = false)}
/>

{#if !anyPivots}
  <div class="mx-auto w-full max-w-6xl px-4 py-6">
    <section class="rounded-lg border border-dashed border-line bg-surface-raised px-6 py-12 text-center">
      <h1 class="text-lg font-medium">No pivots to show yet</h1>
      <p class="mx-auto mt-2 max-w-md text-sm text-ink-muted">
        Place your first pivot on the map and add its fields and crops. The map then shows each field's water status
        where it is.
      </p>
      <Link
        href={newQuickSetup()}
        class="mt-6 inline-block rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 dark:text-surface"
      >
        Get started
      </Link>
    </section>
  </div>
{:else}
  <div class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2 border-b border-line px-4 py-2">
    <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
      <h1 class="text-xl font-semibold">Map</h1>
      <p class="text-sm text-ink-muted">{auth.group?.name} · {formatDate(today, { weekday: true, year: true })}</p>
      <StatusCounts cards={items.map((item) => item.card)} />
    </div>
    <div class="flex flex-wrap items-center gap-2 text-sm">
      {#if farms.length > 1}
        <label class="sr-only" for="farm-filter">Farm</label>
        <select
          id="farm-filter"
          class="rounded-md py-1 text-sm"
          value={farmId}
          onchange={(event) => {
            const value = event.currentTarget.value
            chooseFarm(value === 'all' ? 'all' : Number(value))
          }}
        >
          <option value="all">All farms</option>
          {#each farms as farm (farm.id)}<option value={farm.id}>{farm.name}</option>{/each}
        </select>
      {/if}
      <div class="flex items-center gap-1.5" role="group" aria-labelledby="window-label">
        <span id="window-label" class="text-ink-muted">Needs water</span>
        <div class="flex overflow-hidden rounded-md border border-line bg-surface-raised text-xs">
          {#each WINDOWS as option (option.label)}
            <button
              type="button"
              class="px-2.5 py-1.5 {windowDays === option.days
                ? 'bg-brand-600 text-white dark:text-surface'
                : 'hover:bg-surface'}"
              aria-pressed={windowDays === option.days}
              aria-label={option.days ? `Within ${option.label}` : option.label}
              onclick={() => chooseWindow(option.days)}
              >{#if option.days !== null && option.days > 0}<span class="hidden sm:inline">{'Within '}</span
                >{/if}{option.label}</button
            >
          {/each}
        </div>
      </div>
    </div>
  </div>

  <div class="flex min-h-0 flex-1 flex-col md:flex-row">
    <aside
      class="order-2 flex min-h-0 flex-col border-line bg-surface md:order-1 md:border-r
        {prefs.listOpen ? 'max-h-[45%] border-t md:max-h-none md:w-80 md:border-t-0' : 'md:hidden'}"
      aria-label="Fields"
    >
      <div class="flex flex-wrap items-center gap-2 border-b border-line px-3 py-2">
        <h2 class="mr-auto text-sm font-medium">
          Fields <span class="font-normal text-ink-muted">({listed.length})</span>
        </h2>
        <label class="sr-only" for="list-sort">Order</label>
        <select id="list-sort" class="rounded-md py-1 text-xs" bind:value={prefs.sort}>
          <option value="urgent">Most urgent first</option>
          <option value="north">North to south</option>
        </select>
        <button
          type="button"
          class="rounded-md px-2 py-1 text-xs text-ink-muted hover:bg-surface-raised hover:text-ink md:hidden"
          aria-expanded={prefs.listOpen}
          onclick={() => (prefs.listOpen = !prefs.listOpen)}>{prefs.listOpen ? 'Hide' : 'Show'}</button
        >
      </div>
      <div class="border-b border-line px-3 py-2">
        <input
          type="search"
          bind:value={query}
          placeholder="Filter by field, pivot or farm"
          aria-label="Filter fields"
          class="block w-full rounded-md py-1 text-sm"
        />
      </div>
      <ul bind:this={list} class="min-h-0 flex-1 space-y-2 overflow-y-auto p-3">
        {#each listed as item (item.card.id)}
          <li data-pivot={item.pivot.id}>
            <FieldCard
              card={item.card}
              {today}
              {units}
              compact
              pivotName={item.pivot.name}
              selected={isSelected(item)}
              onselect={() => selectField(item)}
            />
          </li>
        {:else}
          <li class="px-1 py-4 text-sm text-ink-muted">
            {#if windowDays !== null}
              No fields need water {windowDays === 0 ? 'today' : `within ${windowDays} days`}.
            {:else if query.trim()}
              No fields match "{query.trim()}".
            {:else}
              No fields yet.
            {/if}
          </li>
        {/each}
      </ul>
    </aside>

    {#if !prefs.listOpen}
      <button
        type="button"
        class="order-3 border-t border-line bg-surface px-3 py-2 text-left text-sm font-medium md:hidden"
        aria-expanded="false"
        onclick={() => (prefs.listOpen = true)}>Show the fields ({listed.length})</button
      >
    {/if}

    <div
      class="relative order-1 min-h-[50%] flex-1 md:order-2 md:min-h-0"
      bind:clientWidth={mapWidth}
      bind:clientHeight={mapHeight}
    >
      <OverviewMap
        bind:this={overview}
        pivots={mapPivots}
        selectedId={selectedPivotId}
        {highlighted}
        basemap={prefs.basemap}
        view={prefs.view}
        unitSystem={auth.user?.unit_system}
        onselect={selectPivot}
        onbasemap={(basemap) => (prefs.basemap = basemap)}
        onviewchange={(view) => (prefs.view = view)}
        onload={(map) => overlays.attach(map)}
      >
        {#snippet toolbar()}
          <LayersControl {prefs} {overlays} {units} />
        {/snippet}
        <button
          type="button"
          class="absolute top-1/2 left-0 hidden -translate-y-1/2 rounded-r-md border border-l-0 border-line bg-surface-raised
            px-1 py-4 text-ink-muted shadow hover:text-ink md:block"
          aria-label={prefs.listOpen ? 'Hide the field list' : 'Show the field list'}
          aria-expanded={prefs.listOpen}
          onclick={() => (prefs.listOpen = !prefs.listOpen)}>{prefs.listOpen ? '‹' : '›'}</button
        >
        {#if overlays.probe}
          <OverlayTooltip probe={overlays.probe} {units} width={mapWidth} height={mapHeight} />
        {/if}
        {#if overlays.notice}
          <div
            class="absolute top-14 left-1/2 z-20 flex w-[min(24rem,calc(100%-1rem))] -translate-x-1/2 items-start gap-2
              rounded-md border border-line bg-surface-raised px-3 py-2 text-sm shadow-lg"
            role="status"
          >
            <span aria-hidden="true" class="text-status-caution-ink">!</span>
            <p class="flex-1">{overlays.notice}</p>
            <button
              type="button"
              class="text-ink-muted hover:text-ink"
              aria-label="Dismiss"
              onclick={() => overlays.dismiss()}>×</button
            >
          </div>
        {/if}
        {#if selectedPivot}
          <div
            class="pointer-events-none absolute inset-x-2 bottom-8 z-10 flex max-h-[60%] flex-col sm:inset-x-auto sm:top-2
              sm:right-12 sm:bottom-auto sm:max-h-[calc(100%-3rem)] sm:w-80"
          >
            <PivotPanel
              pivot={selectedPivot}
              farmName={farmOf.get(selectedPivot.id)?.name ?? ''}
              {today}
              {units}
              notes={panelNotes}
              onclose={clearSelection}
            />
          </div>
        {/if}
      </OverviewMap>
    </div>
  </div>
{/if}
