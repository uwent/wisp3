<script lang="ts">
  import { onDestroy, tick, untrack } from 'svelte'
  import { Link, page, router } from '@inertiajs/svelte'

  import SearchFilter from '@/lib/components/SearchFilter.svelte'
  import StatusCounts from '@/lib/components/StatusCounts.svelte'
  import { formatDate } from '@/lib/dates'
  import type { LngLat } from '@/lib/geo'
  import OverviewLayers from '@/lib/map/OverviewLayers.svelte'
  import MapTree from '@/lib/map/MapTree.svelte'
  import { MapOverlays } from '@/lib/map/mapOverlays.svelte'
  import OverlayTooltip from '@/lib/map/OverlayTooltip.svelte'
  import OverviewMap from '@/lib/map/OverviewMap.svelte'
  import SystemPanel from '@/lib/map/SystemPanel.svelte'
  import ScopePanel from '@/lib/map/ScopePanel.svelte'
  import ZonePanel from '@/lib/map/ZonePanel.svelte'
  import { droughtAt, droughtBounds, type OverlayId } from '@/lib/map/overlays'
  import { groupFeatures, type MapSystem } from '@/lib/map/systems'
  import { loadPrefs, savePrefs } from '@/lib/map/prefs'
  import { buildTree, type FarmGroup, treeSystems, type Selection, treeFields, updatingIds } from '@/lib/overview'
  import { pollWeather } from '@/lib/weatherPolling.svelte'
  import { count } from '@/lib/text'
  import { currentUnits } from '@/lib/units'
  import { map as mapRoute, newQuickSetup } from '@/routes'
  import type { MapZone } from '@/types/serializers'

  // Every system on a map with its fields' status, beside a list of the operation as a tree of cards.
  // One selection, at any level, is shared by the list, the map and the
  // panel: a farm or irrigation group zooms the map to its systems; a system or field opens its
  // system's panel and is marked on the map. A click on the map selects the system or field there.
  // A season (?year=) shows that year's plantings; this year's can be narrowed to those
  // growing now. The weather zones of the operation's systems are outlined on the map; a click
  // in one (on nothing else) selects it, and its weather takes the panel. The list doesn't have them.
  let {
    today,
    year,
    years,
    farms,
    zones,
  }: { today: string; year: number; years: number[]; farms: FarmGroup<MapSystem>[]; zones: MapZone[] } = $props()

  const auth = $derived(page.props.auth)
  const units = $derived(currentUnits())
  const groupId = page.props.auth.group?.id

  let prefs = $state(loadPrefs(groupId))
  $effect(() => savePrefs(groupId, $state.snapshot(prefs)))

  let farmId = $state<number | 'all'>('all')
  /** Days ahead for "needs water within", or null for no window */
  let windowDays = $state<number | null>(null)
  let query = $state('')
  /** Only the plantings growing today (this year's season only) */
  let growing = $state(false)
  const thisYear = $derived(year === Number(today.slice(0, 4)))
  const onlyGrowing = $derived(growing && thisYear)
  let selection = $state<Selection | null>(null)
  let overview = $state<OverviewMap>()
  let mapWidth = $state(0)
  let mapHeight = $state(0)

  // Optional public layers; the drought polygons are loaded around all the operation's systems
  const overlays = new MapOverlays(() =>
    droughtBounds(farms.flatMap((farm) => farm.systems.map((system): LngLat => [system.longitude, system.latitude]))),
  )
  // The controller records each overlay's status as it goes, so it runs untracked here
  $effect(() => {
    const shown = [...(prefs.rain ? [prefs.rain] : []), ...prefs.overlays] as OverlayId[]
    const opacity = { ...prefs.opacity }
    untrack(() => overlays.sync(shown, opacity))
  })
  onDestroy(() => overlays.destroy())
  let list = $state<HTMLElement>()

  // While a system's weather is on its way, reload the systems and cards until it lands
  const weatherWait = pollWeather(() => updatingIds(farms), ['farms'])
  const weatherFor = (system: { weather_updating: boolean }) => weatherWait.state(system.weather_updating)

  // The farms shown, with only the plantings growing today when asked (fields without one go, their
  // outlines too)
  const shown = $derived(
    farms
      .filter((farm) => farmId === 'all' || farm.id === farmId)
      .map((farm) =>
        onlyGrowing
          ? {
              ...farm,
              systems: farm.systems.map((system) => {
                const fields = system.fields.flatMap((card) => {
                  const plantings = card.plantings.filter((summary) => summary.phase === 'active')
                  return plantings.length ? [{ ...card, plantings }] : []
                })
                const kept = new Set(fields.map((card) => card.id))
                return { ...system, fields, outlines: system.outlines.filter((outline) => kept.has(outline.field_id)) }
              }),
            }
          : farm,
      ),
  )
  const mapSystems = $derived(shown.flatMap((farm) => farm.systems))
  const mapGroups = $derived(groupFeatures(shown, mapSystems))
  const farmOf = $derived(new Map(farms.flatMap((farm) => farm.systems.map((system) => [system.id, farm]))))
  const systemOfField = $derived(
    new Map(
      farms.flatMap((farm) => farm.systems.flatMap((system) => system.fields.map((card) => [card.id, system.id]))),
    ),
  )
  const cards = $derived(mapSystems.flatMap((system) => system.fields))
  const tree = $derived(buildTree(shown, { order: prefs.sort, query, windowDays, growing: onlyGrowing }))
  const listedCount = $derived(treeFields(tree).length)
  // "3 farms · 8 systems · 25 fields · 40 plantings": what the list shows
  const listedSummary = $derived(
    [
      count(tree.length, 'farm'),
      count(tree.flatMap(treeSystems).length, 'system'),
      count(listedCount, 'field'),
      count(
        treeFields(tree).reduce((sum, card) => sum + card.plantings.length, 0),
        'planting',
      ),
    ].join(' · '),
  )
  // Sort and filter starts closed; it says how many of its filters are set
  let filtersOpen = $state(false)
  const filtersSet = $derived([!thisYear, farmId !== 'all', onlyGrowing, windowDays !== null].filter(Boolean).length)
  // What the list's filters leave out is muted on the map
  const filtering = $derived(windowDays !== null || query.trim() !== '')
  const highlighted = $derived(filtering ? new Set(tree.flatMap(treeSystems).map((node) => node.system.id)) : null)
  const highlightedFields = $derived(filtering ? new Set(treeFields(tree).map((card) => card.id)) : null)
  // The system and field the selection puts on the map and in the panel
  const selectedSystemId = $derived(
    selection?.level === 'system'
      ? selection.id
      : selection?.level === 'field'
        ? (systemOfField.get(selection.id) ?? null)
        : null,
  )
  const selectedFieldId = $derived(selection?.level === 'field' ? selection.id : null)
  const selectedSystem = $derived(mapSystems.find((system) => system.id === selectedSystemId) ?? null)
  const selectedFarm = $derived(selectedSystem ? farmOf.get(selectedSystem.id) : undefined)
  // A selected farm or group's card in the list, for its panel, and a group's farm
  const scopeNode = $derived.by(() => {
    if (selection?.level === 'farm') return tree.find((farm) => farm.id === selection!.id) ?? null
    if (selection?.level !== 'group') return null
    for (const farm of tree)
      for (const child of farm.children) if (child.kind === 'group' && child.id === selection.id) return child
    return null
  })
  const scopeFarm = $derived(
    selection?.level === 'group'
      ? farms.find((farm) => farm.irrigation_groups.some((g) => g.id === selection!.id))
      : undefined,
  )
  const zoneOf = (cellId: number | null) => zones.find((zone) => zone.id === cellId) ?? null
  const selectedZone = $derived(selection?.level === 'zone' ? zoneOf(selection.id) : null)
  const anySystems = $derived(farms.some((farm) => farm.systems.length))
  // The Drought Monitor's category at the selected system, when that layer is on
  const panelNotes = $derived.by(() => {
    if (!selectedSystem || !prefs.overlays.includes('drought') || !overlays.drought) return []
    const category = droughtAt(overlays.drought, [selectedSystem.longitude, selectedSystem.latitude])
    return [{ label: 'Drought Monitor', value: category?.label ?? 'None', swatch: category?.color }]
  })

  // Irrigate: fields needing water now (today), soon (within 3 days), or any
  const WINDOWS = [
    { days: null, label: 'Any', title: 'All fields' },
    { days: 3, label: 'Soon', title: 'Fields needing water within 3 days' },
    { days: 0, label: 'Now', title: 'Fields needing water today' },
  ]

  function chooseFarm(id: number | 'all') {
    farmId = id
    if (id !== 'all' && selection && selectionFarm(selection) !== id) clearSelection()
    overview?.fit(mapSystems)
  }

  /** The farm a selection is on */
  function selectionFarm({ level, id }: Selection): number | undefined {
    if (level === 'farm') return id
    if (level === 'group') return farms.find((farm) => farm.irrigation_groups.some((group) => group.id === id))?.id
    if (level === 'zone') return undefined
    return farmOf.get(level === 'system' ? id : (systemOfField.get(id) ?? -1))?.id
  }

  /** The systems a farm or group selection zooms the map to */
  function selectionSystems({ level, id }: Selection) {
    if (level === 'farm') return farms.find((farm) => farm.id === id)?.systems ?? []
    return mapSystems.filter((system) => system.irrigation_group_id === id)
  }

  function chooseWindow(days: number | null) {
    windowDays = days
    const inWindow = mapSystems.filter((system) => highlighted?.has(system.id))
    if (inWindow.length) overview?.fit(inWindow)
  }

  // From the keyboard, selecting a system moves focus to its panel, and closing the panel returns
  // focus to the marker or card that opened it (pointer users stay where they are)
  let keyboard = false
  let opener: HTMLElement | null = null

  function focusPanel() {
    if (!keyboard) return
    opener = document.activeElement instanceof HTMLElement ? document.activeElement : null
    tick().then(() => document.querySelector<HTMLElement>('[data-map-panel]')?.focus())
  }

  // From the list (or the panel's cards): a farm or group zooms the map to its systems; a system or
  // field opens its panel and flies to it
  function select(next: Selection) {
    const before = selectedSystemId
    selection = next
    if (next.level === 'farm' || next.level === 'group') {
      overview?.fit(selectionSystems(next))
      focusPanel()
      return
    }
    // Another field of the same system (in its panel, say) leaves the map where it is
    if (selectedSystemId !== before) overview?.show(selectedSystemId!)
    focusPanel()
  }

  // From the map: a system, or a field (its outline or its badges) with its system; the list
  // scrolls to its card
  function selectOnMap(systemId: number | null, fieldId: number | null = null) {
    selection =
      fieldId !== null ? { level: 'field', id: fieldId } : systemId !== null ? { level: 'system', id: systemId } : null
    if (!selection) return
    focusPanel()
    if (!prefs.listOpen) return
    const { level, id } = selection
    requestAnimationFrame(() =>
      list?.querySelector(`[data-node="${level}-${id}"]`)?.scrollIntoView({
        block: 'nearest',
        behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth',
      }),
    )
  }

  // From the map: a weather zone, where nothing else was clicked
  function selectZone(id: number) {
    selection = { level: 'zone', id }
    focusPanel()
  }

  function clearSelection() {
    const fromPanel = document.querySelector('[data-map-panel]')?.contains(document.activeElement)
    selection = null
    if (fromPanel) opener?.focus()
    opener = null
  }
</script>

<!-- A compact pill menu with its label: "Irrigate  Any | Soon | Now" -->
{#snippet pills(label: string, options: { label: string; title: string; pressed: boolean; onclick: () => void }[])}
  <div class="flex items-center gap-1.5 text-sm" role="group" aria-label={label}>
    <span class="text-ink-muted" aria-hidden="true">{label}</span>
    <div class="flex overflow-hidden rounded-md border border-line bg-surface-raised text-xs">
      {#each options as option (option.label)}
        <button
          type="button"
          class="px-2.5 py-1 {option.pressed ? 'bg-brand-600 text-white dark:text-surface' : 'hover:bg-surface'}"
          aria-pressed={option.pressed}
          title={option.title}
          onclick={option.onclick}>{option.label}</button
        >
      {/each}
    </div>
  </div>
{/snippet}

<svelte:head><title>Map · WISP</title></svelte:head>
<svelte:window
  onkeydown={(event) => {
    keyboard = true
    // Escape clears the selection unless something else used it (a menu, the place search, a dialog)
    // or it was typed in a box
    const target = event.target as HTMLElement | null
    if (
      event.key === 'Escape' &&
      !event.defaultPrevented &&
      !target?.closest('input, textarea, select, [role="dialog"], [role="menu"]')
    )
      clearSelection()
  }}
  onpointerdown={() => (keyboard = false)}
/>

{#if !anySystems}
  <div class="mx-auto w-full max-w-6xl px-4 py-6">
    <section class="rounded-lg border border-dashed border-line bg-surface-raised px-6 py-12 text-center">
      <h1 class="text-lg font-medium">No irrigation systems to show yet</h1>
      <p class="mx-auto mt-2 max-w-md text-sm text-ink-muted">
        Place your first irrigation system on the map and add its fields and crops. The map then shows each field's
        water status where it is.
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
      <StatusCounts {cards} />
    </div>
  </div>

  <div class="flex min-h-0 flex-1 flex-col md:flex-row">
    <aside
      class="order-2 min-h-0 flex-col border-line bg-surface md:order-1 md:border-r
        {prefs.listOpen ? 'flex max-h-[45%] border-t md:max-h-none md:w-80 md:border-t-0' : 'hidden'}"
      aria-label="Fields"
    >
      <div class="flex items-center gap-2 border-b border-line px-3 py-2">
        <button
          type="button"
          class="mr-auto flex items-center gap-1.5 rounded-md text-sm font-medium hover:text-brand-600"
          aria-expanded={filtersOpen}
          aria-controls="map-sort-filter"
          onclick={() => (filtersOpen = !filtersOpen)}
        >
          <span aria-hidden="true" class="inline-block w-3 text-ink-muted">{filtersOpen ? '▾' : '▸'}</span>
          Sort and filter
          {#if filtersSet}<span class="font-normal text-ink-muted">{` · ${filtersSet} set`}</span>{/if}
        </button>
        <button
          type="button"
          class="flex items-center gap-1 rounded-md px-2 py-1 text-xs text-ink-muted hover:bg-surface-raised hover:text-ink md:hidden"
          aria-expanded="true"
          onclick={() => (prefs.listOpen = false)}
        >
          Hide <span aria-hidden="true">▾</span>
        </button>
      </div>
      <div class="space-y-2 border-b border-line px-3 py-2">
        <!-- What the map and list show (season, farm, plantings), then the list's filters and order -->
        <div id="map-sort-filter" class="space-y-2" hidden={!filtersOpen}>
          <div class="flex flex-wrap items-center gap-x-3 gap-y-2 text-xs">
            <label class="flex items-center gap-1.5">
              <span class="text-ink-muted">Season</span>
              <select
                class="rounded-md py-1 text-xs"
                value={year}
                onchange={(event) =>
                  router.get(
                    mapRoute.show({ query: { year: event.currentTarget.value } }).url,
                    {},
                    { preserveState: true },
                  )}
              >
                {#each years as option (option)}<option value={option}>{option}</option>{/each}
              </select>
            </label>
            {#if farms.length > 1}
              <label class="flex min-w-0 items-center gap-1.5">
                <span class="text-ink-muted">Farm</span>
                <select
                  class="min-w-0 rounded-md py-1 text-xs"
                  value={farmId}
                  onchange={(event) => {
                    const value = event.currentTarget.value
                    chooseFarm(value === 'all' ? 'all' : Number(value))
                  }}
                >
                  <option value="all">All farms</option>
                  {#each farms as farm (farm.id)}<option value={farm.id}>{farm.name}</option>{/each}
                </select>
              </label>
            {/if}
          </div>
          {#if thisYear}
            {@render pills('Plantings', [
              {
                label: 'All',
                title: "All this season's plantings",
                pressed: !growing,
                onclick: () => (growing = false),
              },
              {
                label: 'Current',
                title: 'Only plantings growing today',
                pressed: growing,
                onclick: () => (growing = true),
              },
            ])}
          {/if}
          {@render pills(
            'Irrigate',
            WINDOWS.map((option) => ({
              label: option.label,
              title: option.title,
              pressed: windowDays === option.days,
              onclick: () => chooseWindow(option.days),
            })),
          )}
          <label class="flex items-center gap-1.5 text-xs">
            <span class="text-ink-muted">Sort</span>
            <select class="rounded-md py-1 text-xs" bind:value={prefs.sort}>
              <option value="urgent">Most urgent first</option>
              <option value="north">North to south</option>
            </select>
          </label>
        </div>
        <SearchFilter bind:value={query} compact class="w-full" />
        <h2 class="text-xs text-ink-muted">{listedSummary}</h2>
      </div>
      <div bind:this={list} class="min-h-0 flex-1 overflow-y-auto p-2">
        {#if tree.length}
          <MapTree {tree} {selection} {today} {units} weatherFor={(system) => weatherFor(system)} onselect={select} />
        {:else}
          <p class="px-1 py-4 text-sm text-ink-muted">
            {#if windowDays !== null}
              No fields need water {windowDays === 0 ? 'today' : `within ${windowDays} days`}.
            {:else if onlyGrowing && !query.trim()}
              Nothing is growing today.
            {:else if query.trim()}
              Nothing matches "{query.trim()}".
            {:else}
              No fields yet. Add them in Setup.
            {/if}
          </p>
        {/if}
      </div>
    </aside>

    {#if !prefs.listOpen}
      <button
        type="button"
        class="order-3 flex items-center gap-2 border-t border-line bg-surface px-3 py-2 text-left md:hidden"
        aria-expanded="false"
        onclick={() => (prefs.listOpen = true)}
      >
        <span class="mr-auto min-w-0 truncate text-xs text-ink-muted">{listedSummary}</span>
        <span class="flex shrink-0 items-center gap-1 text-xs font-medium">
          Show <span aria-hidden="true">▴</span>
        </span>
      </button>
    {/if}

    <div
      class="relative order-1 min-h-[50%] flex-1 md:order-2 md:min-h-0"
      bind:clientWidth={mapWidth}
      bind:clientHeight={mapHeight}
    >
      <OverviewMap
        bind:this={overview}
        systems={mapSystems}
        groups={mapGroups}
        {today}
        selectedId={selectedSystemId}
        {selectedFieldId}
        {highlighted}
        {highlightedFields}
        showSystems={prefs.systems}
        {zones}
        showZones={prefs.zones}
        selectedZoneId={selectedZone?.id ?? null}
        onselectzone={selectZone}
        layersCount={(prefs.rain ? 1 : 0) + prefs.overlays.length}
        basemap={prefs.basemap}
        view={prefs.view}
        unitSystem={auth.user?.unit_system}
        onselect={selectOnMap}
        onbasemap={(basemap) => (prefs.basemap = basemap)}
        onviewchange={(view) => {
          prefs.view = view
        }}
        onload={(map) => overlays.attach(map)}
      >
        {#snippet layers()}
          <OverviewLayers bind:prefs {overlays} {units} />
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
        {#if scopeNode || selectedSystem || selectedZone}
          <div
            class="pointer-events-none absolute inset-x-2 bottom-8 z-10 flex max-h-[60%] flex-col sm:inset-x-auto sm:top-2
              sm:right-12 sm:bottom-auto sm:max-h-[calc(100%-3rem)] sm:w-80"
          >
            {#if selectedZone}
              <ZonePanel zone={selectedZone} {today} {units} onclose={clearSelection} />
            {:else if scopeNode}
              <ScopePanel node={scopeNode} farm={scopeFarm} onselect={select} onclose={clearSelection} />
            {:else if selectedSystem && selectedFarm}
              <SystemPanel
                system={selectedSystem}
                farm={selectedFarm}
                group={selectedFarm.irrigation_groups.find(
                  (group) => group.id === selectedSystem.irrigation_group_id,
                ) ?? null}
                {today}
                {units}
                weather={zoneOf(selectedSystem.weather_cell_id)?.weather ?? null}
                fieldId={selectedFieldId}
                onselectfield={(id) => select({ level: 'field', id })}
                onselect={select}
                notes={panelNotes}
                onclose={clearSelection}
              />
            {/if}
          </div>
        {/if}
      </OverviewMap>
    </div>
  </div>
{/if}
