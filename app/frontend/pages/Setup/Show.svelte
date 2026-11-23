<script lang="ts">
  import { Form, Link, page, router } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import Dialog from '@/lib/components/Dialog.svelte'
  import SearchFilter from '@/lib/components/SearchFilter.svelte'
  import SeasonTimeline from '@/lib/components/SeasonTimeline.svelte'
  import { today as todayDate } from '@/lib/dates'
  import { isPoint, KIND_NOUNS, shapeAcres, systemName } from '@/lib/geo'
  import { mayDelete } from '@/lib/permissions'
  import { searchFarms } from '@/lib/search'
  import { readStored, writeStored } from '@/lib/storage'
  import { count } from '@/lib/text'
  import { currentUnits } from '@/lib/units'
  import { overlappingPairs, sharePercent } from '@/lib/outlines/overlap'
  import { outlineProblems } from '@/lib/outlines/problems'
  import FarmForm from '@/lib/setup/FarmForm.svelte'
  import FieldForm from '@/lib/setup/FieldForm.svelte'
  import IrrigationGroupForm from '@/lib/setup/IrrigationGroupForm.svelte'
  import NextSteps from '@/lib/setup/NextSteps.svelte'
  import PlantingDialog from '@/lib/setup/PlantingDialog.svelte'
  import { takeSetupRequest } from '@/lib/setup/links'
  import { farmChildren, orderFarms, orderFields, SETUP_ORDERS, type SetupOrder } from '@/lib/setup/order'
  import {
    farms as farmRoutes,
    fieldOutline,
    fields,
    groups as groupRoutes,
    newOutlineImport,
    newQuickSetup,
    irrigationGroups,
    systems,
    planting as plantingRoute,
    seasonCopies,
    seasonReport,
    setup,
  } from '@/routes'
  import type {
    Farm,
    Field,
    GenericCurve,
    IrrigationSystem,
    IrrigationGroup,
    Plant,
    SoilType,
  } from '@/types/serializers'

  let {
    year,
    years,
    farms,
    plants,
    soil_types,
    generic_curves,
    started,
  }: {
    year: number
    years: number[]
    farms: Farm[]
    plants: Plant[]
    soil_types: SoilType[]
    generic_curves: GenericCurve[]
    /** What quick setup just made, for its next steps */
    started: { farm_id: number; system_id: number | null } | null
  } = $props()

  const units = $derived(currentUnits())
  const group = $derived(page.props.auth.group!)
  // Only owners delete farms, systems and fields (Q8); plantings and groups also their creator
  const owner = $derived(page.props.auth.owner)
  const allSystems = $derived(farms.flatMap((farm) => farm.systems))
  // A system's shape in its row: "Radius 600 ft · Arc 0–270° · Area 80 ac"
  const systemSize = (system: (typeof allSystems)[number]) => {
    const acres = shapeAcres(system)
    return [
      system.kind === 'linear' && system.length_ft && system.travel_ft
        ? `${units.format('distance', system.length_ft)} long, travels ${units.format('distance', system.travel_ft)} at ${system.travel_bearing_deg}° from north`
        : system.radius_ft && `Radius ${units.format('distance', system.radius_ft)}`,
      system.arc_start_deg !== null &&
        system.arc_end_deg !== null &&
        `Arc ${system.arc_start_deg}–${system.arc_end_deg}°`,
      acres !== null && `Area ${units.format('area', acres)}`,
    ]
      .filter(Boolean)
      .join(' · ')
  }
  // A field's area in its row: "Mapped as 2.0 ac" when it's its outline's, else as entered (with the
  // outline's beside it when that differs)
  const fieldArea = (field: Field) => {
    const entered = units.format('area', field.area_acres)
    if (field.boundary_acres === null) return entered
    const mapped = units.format('area', field.boundary_acres)
    return mapped === entered ? `Mapped as ${mapped}` : `${entered} · Mapped as ${mapped}`
  }
  const seasonPlantings = (field: Field) => field.plantings.filter((planting) => planting.year === year)
  // A field listed for the season: it has a crop in it or the season before (to plan from), or no
  // crop at all yet. Fields used only in other seasons (rotated out, or set up for a later one) are
  // collapsed below the rest.
  const inSeason = (field: Field) =>
    field.plantings.length === 0 ||
    field.plantings.some((planting) => planting.year === year || planting.year === year - 1)
  // The order the page lists things in (lib/setup/order.ts), remembered in this browser
  const ORDER_KEY = 'wisp.setup.order'
  let order = $state<SetupOrder>(readStored(ORDER_KEY) === 'name' ? 'name' : 'north')
  $effect(() => {
    writeStored(ORDER_KEY, order)
  })
  // Name and crop search (this season's crops), for this visit
  let query = $state('')
  const searching = $derived(query.trim() !== '')
  const orderedFarms = $derived(orderFarms(searchFarms(farms, query, seasonPlantings), order))
  // A farm as saved, whatever the search shows: a group's form lists (and saves) all its systems
  const unfiltered = (farm: Farm) => farms.find((saved) => saved.id === farm.id) ?? farm
  const used = (system: IrrigationSystem) => orderFields(system, order).filter(inSeason)
  const unused = (system: IrrigationSystem) => orderFields(system, order).filter((field) => !inSeason(field))
  const hasSeason = $derived(allSystems.some((p) => p.fields.some((f) => seasonPlantings(f).length)))
  const hasLastSeason = $derived(
    allSystems.some((p) => p.fields.some((f) => f.plantings.some((pl) => pl.year === year - 1))),
  )

  // Fields whose outline isn't with their irrigation system, and fields whose outlines overlap (a
  // duplicate, or one drawn over its neighbor), to fix by hand
  const outlineIssues = $derived([
    ...allSystems.flatMap((system) =>
      outlineProblems(system, system.fields, page.props.auth.user?.unit_system ?? 'imperial'),
    ),
    ...overlappingPairs(
      allSystems.flatMap((system) =>
        system.fields.flatMap((field) => (field.boundary ? [{ ...field, boundary: field.boundary }] : [])),
      ),
    ).map(({ a, b, share }) => ({
      fieldId: a.id,
      message: `${a.name}'s shape overlaps ${b.name}'s (${sharePercent(share)} of the smaller)`,
    })),
  ])

  type DialogState =
    | { kind: 'farm'; farm?: Farm }
    | { kind: 'field'; system: IrrigationSystem; field?: Field }
    | { kind: 'irrigationGroup'; farm: Farm; group?: IrrigationGroup }
  // Plantings have their own dialog (also on the field page)
  let plantingDialog: PlantingDialog | undefined = $state()
  const today = todayDate()

  // ?planting=, ?field=, ?farm= or ?irrigation_group= (Edit links on the planting page and the map,
  // lib/setup/links.ts): scroll to it and open its form, once
  $effect(() => {
    if (!plantingDialog) return
    const request = takeSetupRequest()
    if (!request) return
    const { kind, id } = request
    const show = (elementId: string) => {
      const element = document.getElementById(elementId)
      // A field not used this season is in a collapsed list
      const details = element?.closest('details')
      if (details) details.open = true
      element?.scrollIntoView({ block: 'center' })
    }
    for (const farm of farms) {
      if (kind === 'farm' && farm.id === id) {
        show(`setup-farm-${farm.id}`)
        open({ kind: 'farm', farm })
        return
      }
      const irrigationGroup = farm.irrigation_groups.find((g) => g.id === id)
      if (kind === 'planting' || kind === 'field') {
        for (const system of farm.systems)
          for (const field of system.fields) {
            const found = field.plantings.find((planting) => planting.id === id)
            if (kind === 'planting' && found) {
              show(`setup-field-${field.id}`)
              plantingDialog.open(field, found)
              return
            }
            if (kind === 'field' && field.id === id) {
              show(`setup-field-${field.id}`)
              open({ kind: 'field', system, field })
              return
            }
          }
      } else if (kind === 'group' && irrigationGroup) {
        show(`setup-group-${irrigationGroup.id}`)
        open({ kind: 'irrigationGroup', farm, group: irrigationGroup })
        return
      }
    }
  })
  let dialog = $state<DialogState | null>(null)
  let dialogOpen = $state(false)
  const open = (state: DialogState) => {
    dialog = state
    dialogOpen = true
  }
  const close = () => (dialogOpen = false)

  /** Asks first, then deletes and closes the dialog it was asked from */
  function destroy(route: { url: string }, what: string) {
    if (!confirm(`Delete ${what}? This can't be undone.`)) return
    router.delete(route.url, { preserveScroll: true })
    close()
  }

  const dialogTitle = $derived.by(() => {
    if (!dialog) return ''
    if (dialog.kind === 'farm') return dialog.farm ? `Edit ${dialog.farm.name}` : 'Add a farm'
    if (dialog.kind === 'irrigationGroup')
      return dialog.group ? `Edit ${dialog.group.name}` : `Group irrigation systems on ${dialog.farm.name}`
    return dialog.field ? `Edit ${dialog.field.name}` : `Add a field to ${dialog.system.name}`
  })
</script>

<svelte:head><title>Setup · WISP</title></svelte:head>

{#snippet fieldRow(system: IrrigationSystem, field: Field)}
  <li id="setup-field-{field.id}" class="flex flex-wrap items-center gap-x-4 gap-y-2 px-3 py-2">
    <div class="min-w-40 flex-1">
      <p>
        <span class="text-ink-muted">Field:</span>
        <span class="font-medium" data-search-text>{field.name}</span>
      </p>
      <p class="text-xs text-ink-muted">
        {fieldArea(field)} · {field.soil_type_name}
        {#if field.field_capacity !== null || field.perm_wilting_pt !== null}(own field capacity and wilting point){/if}
      </p>
    </div>
    <div class="flex gap-1 text-xs">
      <Link
        href={fields.show(field.id)}
        class="rounded-md px-2 py-1 font-medium text-brand-600 hover:bg-brand-50"
        aria-label="View {field.name}">View</Link
      >
      <Button
        variant="ghost"
        class="px-2 py-1 text-xs"
        aria-label="Add a planting to {field.name}"
        onclick={() => plantingDialog?.open(field)}>Add a planting</Button
      >
      <Button
        variant="ghost"
        class="px-2 py-1 text-xs"
        aria-label="Edit {field.name}"
        onclick={() => open({ kind: 'field', system, field })}>Edit</Button
      >
    </div>
    <!-- The season's plantings on a timeline, each opening its form -->
    <div class="w-full">
      {#if seasonPlantings(field).length}
        <SeasonTimeline
          plantings={seasonPlantings(field)}
          {year}
          {today}
          {units}
          label="Plantings on {field.name}, {year}"
          href={(planting) => plantingRoute(planting.id).url}
          onselect={(planting) => plantingDialog?.open(field, planting)}
        />
      {:else}
        <p class="text-xs text-ink-muted">No {year} planting</p>
      {/if}
    </div>
  </li>
{/snippet}

{#snippet systemCard(system: IrrigationSystem)}
  <div class="rounded-md border border-line">
    <div class="flex flex-wrap items-center justify-between gap-2 border-b border-line bg-surface px-3 py-2">
      <div>
        <h3 class="font-medium">
          <span class="font-normal text-ink-muted">Irrigation system:</span>
          <span data-search-text>{systemName(system)}</span>
        </h3>
        <p class="text-xs text-ink-muted">
          {system.latitude.toFixed(4)}, {system.longitude.toFixed(4)}
          {#if systemSize(system)}
            · {systemSize(system)}{/if}
          {#if system.pump_capacity_gpm}
            · {isPoint(system.kind) ? 'Flow' : 'Pump'} {units.format('flow', system.pump_capacity_gpm)}{/if}
          {#if system.equipment}
            · {system.equipment}{/if}
        </p>
      </div>
      <div class="flex flex-wrap gap-1 text-sm">
        <Link
          href={systems.show(system.id)}
          class="rounded-md px-3 py-1.5 font-medium text-brand-600 hover:bg-brand-50"
          aria-label="View {system.name}">View</Link
        >
        <Button
          variant="ghost"
          class="px-3 py-1.5"
          aria-label="Add field to {system.name}"
          onclick={() => open({ kind: 'field', system })}>Add field</Button
        >
        <Link
          href={systems.edit(system.id)}
          class="rounded-md px-3 py-1.5 font-medium text-brand-600 hover:bg-brand-50"
          aria-label="Edit {system.name}">Edit</Link
        >
        <Link
          href={systems.new({ query: { copy_of: system.id } })}
          class="rounded-md px-3 py-1.5 font-medium text-brand-600 hover:bg-brand-50"
          aria-label="Duplicate {system.name}">Duplicate</Link
        >
      </div>
    </div>
    {#if system.fields.length === 0}
      <p class="px-3 py-3 text-sm text-ink-muted">No fields on this {KIND_NOUNS[system.kind]} yet.</p>
    {/if}
    {#if used(system).length}
      <ul class="divide-y divide-line">
        {#each used(system) as field (field.id)}
          {@render fieldRow(system, field)}
        {/each}
      </ul>
    {/if}
    {#if unused(system).length}
      <!-- Fields used only in other seasons (rotated out, or set up for a later one) -->
      <details class="border-t border-line first:border-t-0" open={searching || undefined}>
        <summary class="cursor-pointer px-3 py-2 text-xs text-ink-muted hover:text-ink">
          {count(unused(system).length, 'field')} not used in {year - 1} or {year}
        </summary>
        <ul class="divide-y divide-line border-t border-line">
          {#each unused(system) as field (field.id)}
            {@render fieldRow(system, field)}
          {/each}
        </ul>
      </details>
    {/if}
  </div>
{/snippet}

<div class="flex flex-wrap items-end justify-between gap-3">
  <div>
    <h1 class="text-2xl font-semibold">Setup</h1>
    <p class="text-sm text-ink-muted">
      Farms, irrigation systems, fields and each season's plantings for {group.name}
    </p>
  </div>
  <div class="flex flex-wrap items-center gap-2">
    <SearchFilter bind:value={query} placeholder="Search" class="w-full sm:w-48" />
    <label for="season" class="text-sm text-ink-muted">Season</label>
    <select
      id="season"
      class="rounded-md text-sm"
      value={year}
      onchange={(e) => router.get(setup.show().url, { year: e.currentTarget.value })}
    >
      {#each [...new Set([...years, year + 1])] as y (y)}<option value={y}>{y}</option>{/each}
    </select>
    <label for="setup-order" class="ml-2 text-sm text-ink-muted">Sort</label>
    <select id="setup-order" class="rounded-md text-sm" bind:value={order}>
      {#each SETUP_ORDERS as option (option.value)}<option value={option.value}>{option.label}</option>{/each}
    </select>
  </div>
</div>

{#if started}
  <NextSteps
    {started}
    {farms}
    {year}
    onaddfield={(system) => open({ kind: 'field', system })}
    onaddplanting={(field) => plantingDialog?.open(field)}
  />
{/if}

{#if outlineIssues.length}
  <section
    class="space-y-1 rounded-lg border border-status-caution bg-surface-raised px-4 py-3 text-sm"
    aria-labelledby="outline-issues"
  >
    <h2 id="outline-issues" class="font-medium">Field shapes to check</h2>
    <p class="text-ink-muted">
      A field's shape belongs under its irrigation system, which doesn't move with it, since its location sets the
      weather; and two fields' shapes shouldn't overlap. Move the shape, or the system if it's in the wrong place.
    </p>
    <ul class="list-disc pl-5">
      {#each outlineIssues as issue, position (`${position}:${issue.message}`)}
        <li>
          {issue.message}.
          <Link href={fieldOutline(issue.fieldId, { query: { from: 'setup' } })} class="underline underline-offset-2"
            >Edit the shape</Link
          >
        </li>
      {/each}
    </ul>
  </section>
{/if}

{#if hasLastSeason}
  <Form
    action={seasonCopies.create({ query: { year } })}
    class="flex flex-wrap items-center gap-3 rounded-lg border border-line bg-brand-50 px-4 py-3 text-sm"
  >
    {#snippet children({ processing })}
      <p class="flex-1">
        Growing the same crops as {year - 1}? Copy last season's plantings to {year}, with the same settings and dates a
        year later.
      </p>
      <Button type="submit" variant="secondary" disabled={processing}>Copy {year - 1} plantings</Button>
    {/snippet}
  </Form>
{/if}

{#each orderedFarms as farm (farm.id)}
  <section id="setup-farm-{farm.id}" class="space-y-4 rounded-lg border border-line bg-surface-raised p-4 sm:p-6">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <div class="min-w-0">
        <h2 class="text-lg font-medium">
          <span class="font-normal text-ink-muted">Farm:</span> <span data-search-text>{farm.name}</span>
        </h2>
        {#if !farm.use_model_precip}<p class="text-xs text-ink-muted">Rain: only what you enter</p>{/if}
        {#if farm.notes}<p class="text-sm whitespace-pre-line text-ink-muted">{farm.notes}</p>{/if}
      </div>
      <div class="flex flex-wrap gap-1 text-sm">
        <Link
          href={systems.new({ query: { farm_id: farm.id } })}
          class="rounded-md px-3 py-1.5 font-medium text-brand-600 hover:bg-brand-50"
          aria-label="Add irrigation system to {farm.name}">Add irrigation system</Link
        >
        {#if unfiltered(farm).systems.length > 1}
          <Button
            variant="ghost"
            class="px-3 py-1.5"
            aria-label="Group systems on {farm.name}"
            onclick={() => open({ kind: 'irrigationGroup', farm: unfiltered(farm) })}>Group systems</Button
          >
        {/if}
        <Button
          variant="ghost"
          class="px-3 py-1.5"
          aria-label="Edit {farm.name}"
          onclick={() => open({ kind: 'farm', farm })}>Edit</Button
        >
      </div>
    </div>

    {#if farm.systems.length === 0}
      <p class="text-sm text-ink-muted">No irrigation systems on this farm yet.</p>
    {/if}

    {#each farmChildren(farm, order) as child (child.kind === 'group' ? `group-${child.group.id}` : `system-${child.system.id}`)}
      {#if child.kind === 'group'}
        {@const irrigationGroup = child.group}
        <!-- An irrigation group: systems organized together, sharing a rain gauge in daily entry -->
        <div id="setup-group-{irrigationGroup.id}" class="space-y-3 rounded-md border border-dashed border-line p-3">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div>
              <h3 class="font-medium">
                <span class="font-normal text-ink-muted">Irrigation group:</span>
                <span data-search-text>{irrigationGroup.name}</span>
              </h3>
              <p class="text-xs text-ink-muted">
                Rain entered for the group on Daily entry fills into all its fields{irrigationGroup.use_model_precip ===
                null
                  ? ''
                  : irrigationGroup.use_model_precip
                    ? ' · modeled rain'
                    : ' · only the rain you enter'}
              </p>
            </div>
            <div class="flex gap-1 text-sm">
              <Button
                variant="ghost"
                class="px-3 py-1.5"
                aria-label="Edit {irrigationGroup.name}"
                onclick={() => open({ kind: 'irrigationGroup', farm: unfiltered(farm), group: irrigationGroup })}
                >Edit</Button
              >
            </div>
          </div>
          {#each child.systems as system (system.id)}
            {@render systemCard(system)}
          {:else}
            <p class="text-sm text-ink-muted">No irrigation systems in this group.</p>
          {/each}
        </div>
      {:else}
        {@render systemCard(child.system)}
      {/if}
    {/each}
  </section>
{:else}
  <section
    class="rounded-lg border border-dashed border-line bg-surface-raised px-6 py-10 text-center text-sm text-ink-muted"
  >
    {#if searching}
      Nothing matches "{query.trim()}".
    {:else}
      No farms yet. <Link href={newQuickSetup()} class="text-brand-600 underline underline-offset-2"
        >Set up your first irrigation system</Link
      >.
    {/if}
  </section>
{/each}

<div class="flex flex-wrap gap-3">
  <Button variant="secondary" onclick={() => open({ kind: 'farm' })}>Add a farm</Button>
  <Link
    href={groupRoutes.show()}
    class="rounded-md border border-line bg-surface-raised px-4 py-2 text-sm font-medium hover:bg-surface"
  >
    Operation settings and members
  </Link>
  {#if farms.some((farm) => farm.systems.length)}
    <Link
      href={newOutlineImport()}
      class="rounded-md border border-line bg-surface-raised px-4 py-2 text-sm font-medium hover:bg-surface"
    >
      Import field shapes
    </Link>
  {/if}
  {#if hasSeason}
    <a
      href={seasonReport({ query: { year } }).url}
      class="rounded-md border border-line bg-surface-raised px-4 py-2 text-sm font-medium hover:bg-surface"
      title="Every field's {year} season, irrigation by system and weather by zone, as one CSV"
      download
    >
      {year} season report (CSV)
    </a>
  {/if}
</div>

<PlantingDialog
  bind:this={plantingDialog}
  {year}
  {plants}
  soilTypes={soil_types}
  genericCurves={generic_curves}
  systemFields={(field) => allSystems.find((system) => system.id === field.system_id)?.fields ?? []}
/>

<Dialog bind:open={dialogOpen} title={dialogTitle} guard>
  {#if dialog?.kind === 'farm'}
    {@const farm = dialog.farm}
    <FarmForm
      {farm}
      ondone={close}
      ondelete={farm && owner
        ? () => destroy(farmRoutes.destroy(farm.id), `${farm.name} and all its irrigation systems and fields`)
        : undefined}
    />
  {:else if dialog?.kind === 'irrigationGroup'}
    {@const { farm, group } = dialog}
    <IrrigationGroupForm
      {farm}
      {group}
      ondone={close}
      ondelete={group && mayDelete(group, page.props.auth)
        ? () =>
            destroy(
              irrigationGroups.destroy(group.id),
              `the group ${group.name} (its irrigation systems stay, ungrouped)`,
            )
        : undefined}
    />
  {:else if dialog?.kind === 'field'}
    <FieldForm
      field={dialog.field}
      systemId={dialog.system.id}
      systems={allSystems}
      soilTypes={soil_types}
      ondone={close}
      ondelete={dialog.field && owner
        ? () => {
            const field = (dialog as { field: Field }).field
            destroy(fields.destroy(field.id), `${field.name} and all its plantings and entries`)
          }
        : undefined}
    />
  {/if}
</Dialog>
