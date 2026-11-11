<script lang="ts">
  import { Form, Link, page, router } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import Dialog from '@/lib/components/Dialog.svelte'
  import SeasonTimeline from '@/lib/components/SeasonTimeline.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { isoDate } from '@/lib/dates'
  import { units as unitsFor } from '@/lib/units'
  import FieldForm from '@/lib/setup/FieldForm.svelte'
  import PlantingDialog from '@/lib/setup/PlantingDialog.svelte'
  import {
    farms as farmRoutes,
    fieldGroups,
    fields,
    groups as groupRoutes,
    newQuickSetup,
    pivots,
    seasonCopies,
    seasonReport,
    setup,
  } from '@/routes'
  import type { Farm, Field, Pivot, Plant, SoilType } from '@/types/serializers'

  let {
    year,
    years,
    farms,
    plants,
    soil_types,
  }: { year: number; years: number[]; farms: Farm[]; plants: Plant[]; soil_types: SoilType[] } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const group = $derived(page.props.auth.group!)
  // Only owners delete farms, pivots and fields (Q8)
  const owner = $derived(page.props.auth.owner)
  const allPivots = $derived(farms.flatMap((farm) => farm.pivots))
  const pivotSize = (pivot: (typeof allPivots)[number]) =>
    pivot.kind === 'linear' && pivot.length_ft && pivot.travel_ft
      ? `linear move, ${units.format('distance', pivot.length_ft)} long, travels ${units.format('distance', pivot.travel_ft)} at ${pivot.travel_bearing_deg}° from north`
      : pivot.radius_ft
        ? `radius ${units.format('distance', pivot.radius_ft)}`
        : null
  const seasonPlantings = (field: Field) => field.plantings.filter((planting) => planting.year === year)
  // A field listed for the season: it has a crop in it or the season before (to plan from), or no
  // crop at all yet. Fields used only in other seasons (rotated out, or set up for a later one) are
  // collapsed below the rest (PLAN.md Phase 8 G.9).
  const inSeason = (field: Field) =>
    field.plantings.length === 0 ||
    field.plantings.some((planting) => planting.year === year || planting.year === year - 1)
  const used = (pivot: Pivot) => pivot.fields.filter(inSeason)
  const unused = (pivot: Pivot) => pivot.fields.filter((field) => !inSeason(field))
  const hasSeason = $derived(allPivots.some((p) => p.fields.some((f) => seasonPlantings(f).length)))
  const hasLastSeason = $derived(
    allPivots.some((p) => p.fields.some((f) => f.plantings.some((pl) => pl.year === year - 1))),
  )

  type DialogState = { kind: 'farm'; farm?: Farm } | { kind: 'field'; pivot: Pivot; field?: Field }
  // Plantings have their own dialog (also on the field page)
  let plantingDialog: PlantingDialog | undefined = $state()
  const today = isoDate(new Date())
  let dialog = $state<DialogState | null>(null)
  let dialogOpen = $state(false)
  const open = (state: DialogState) => {
    dialog = state
    dialogOpen = true
  }
  const close = () => (dialogOpen = false)

  /** Asks first; true if the delete was sent */
  function destroy(route: { url: string }, what: string): boolean {
    if (!confirm(`Delete ${what}? This can't be undone.`)) return false
    router.delete(route.url, { preserveScroll: true })
    return true
  }

  const dialogTitle = $derived.by(() => {
    if (!dialog) return ''
    if (dialog.kind === 'farm') return dialog.farm ? `Edit ${dialog.farm.name}` : 'Add a farm'
    return dialog.field ? `Edit ${dialog.field.name}` : `Add a field to ${dialog.pivot.name}`
  })
</script>

<svelte:head><title>Setup · WISP</title></svelte:head>

{#snippet fieldRow(pivot: Pivot, field: Field)}
  <li class="flex flex-wrap items-center gap-x-4 gap-y-2 px-3 py-2">
    <div class="min-w-40 flex-1">
      <p>
        <span class="text-ink-muted">Field:</span>
        <Link href={fields.show(field.id)} class="font-medium hover:underline">{field.name}</Link>
      </p>
      <p class="text-xs text-ink-muted">
        {units.format('area', field.area_acres)} · {field.soil_type_name}
        {#if field.field_capacity !== null || field.perm_wilting_pt !== null}(own field capacity and wilting point){/if}
        {#if field.use_model_precip !== null}· {field.use_model_precip
            ? 'modeled rain'
            : 'only the rain you enter'}{/if}
      </p>
    </div>
    <Button
      variant="ghost"
      class="px-2 py-1 text-xs"
      aria-label="Add a planting to {field.name}"
      onclick={() => plantingDialog?.open(field)}>Add a planting</Button
    >
    <div class="flex gap-1 text-xs">
      <Button
        variant="ghost"
        class="px-2 py-1 text-xs"
        aria-label="Edit {field.name}"
        onclick={() => open({ kind: 'field', pivot, field })}>Edit</Button
      >
      {#if owner}
        <Button
          variant="danger-ghost"
          class="px-2 py-1 text-xs"
          aria-label="Delete {field.name}"
          onclick={() => destroy(fields.destroy(field.id), `${field.name} and all its plantings and entries`)}
        >
          Delete
        </Button>
      {/if}
    </div>
    <!-- The season's plantings on a timeline, each opening its form (PLAN.md Phase 8 G.11) -->
    <div class="w-full">
      {#if seasonPlantings(field).length}
        <SeasonTimeline
          plantings={seasonPlantings(field)}
          {year}
          {today}
          {units}
          label="Plantings on {field.name}, {year}"
          onselect={(planting) => plantingDialog?.open(field, planting)}
        />
      {:else}
        <p class="text-xs text-ink-muted">No {year} planting</p>
      {/if}
    </div>
  </li>
{/snippet}

<div class="flex flex-wrap items-end justify-between gap-3">
  <div>
    <h1 class="text-2xl font-semibold">Setup</h1>
    <p class="text-sm text-ink-muted">Farms, pivots, fields and each season's plantings for {group.name}</p>
  </div>
  <div class="flex flex-wrap items-center gap-2">
    <label for="season" class="text-sm text-ink-muted">Season</label>
    <select
      id="season"
      class="rounded-md text-sm"
      value={year}
      onchange={(e) => router.get(setup.show().url, { year: e.currentTarget.value })}
    >
      {#each [...new Set([...years, year + 1])] as y (y)}<option value={y}>{y}</option>{/each}
    </select>
    <Link
      href={newQuickSetup()}
      class="rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 dark:text-surface"
    >
      Set up a pivot
    </Link>
  </div>
</div>

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

{#each farms as farm (farm.id)}
  <section class="space-y-4 rounded-lg border border-line bg-surface-raised p-4 sm:p-6">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <div class="min-w-0">
        <h2 class="text-lg font-medium"><span class="font-normal text-ink-muted">Farm:</span> {farm.name}</h2>
        {#if farm.notes}<p class="text-sm whitespace-pre-line text-ink-muted">{farm.notes}</p>{/if}
      </div>
      <div class="flex gap-1 text-sm">
        <Link
          href={pivots.new({ query: { farm_id: farm.id } })}
          class="rounded-md px-3 py-1.5 text-brand-600 hover:bg-brand-50"
          aria-label="Add pivot to {farm.name}">Add pivot</Link
        >
        <Button
          variant="ghost"
          class="px-3 py-1.5"
          aria-label="Edit {farm.name}"
          onclick={() => open({ kind: 'farm', farm })}>Edit</Button
        >
        {#if owner}
          <Button
            variant="danger-ghost"
            class="px-3 py-1.5"
            aria-label="Delete {farm.name}"
            onclick={() => destroy(farmRoutes.destroy(farm.id), `${farm.name} and all its pivots and fields`)}
          >
            Delete
          </Button>
        {/if}
      </div>
    </div>

    {#if farm.pivots.length === 0}
      <p class="text-sm text-ink-muted">No pivots on this farm yet.</p>
    {/if}

    {#each farm.pivots as pivot (pivot.id)}
      <div class="rounded-md border border-line">
        <div class="flex flex-wrap items-center justify-between gap-2 border-b border-line bg-surface px-3 py-2">
          <div>
            <h3 class="font-medium">
              <span class="font-normal text-ink-muted">Irrigation system:</span>
              <Link href={pivots.show(pivot.id)} class="hover:underline">{pivot.name}</Link>
            </h3>
            <p class="text-xs text-ink-muted">
              {pivot.latitude.toFixed(4)}, {pivot.longitude.toFixed(4)}
              {#if pivotSize(pivot)}
                · {pivotSize(pivot)}{/if}
              {#if pivot.pump_capacity_gpm}
                · pump {units.format('flow', pivot.pump_capacity_gpm)}{/if}
              {#if pivot.equipment}
                · {pivot.equipment}{/if}
            </p>
          </div>
          <div class="flex flex-wrap gap-1 text-sm">
            <Link
              href={pivots.show(pivot.id)}
              class="rounded-md px-3 py-1.5 text-brand-600 hover:bg-brand-50"
              aria-label="Irrigation, {pivot.name}">Irrigation</Link
            >
            <Link
              href={pivots.edit(pivot.id)}
              class="rounded-md px-3 py-1.5 text-brand-600 hover:bg-brand-50"
              aria-label="Edit {pivot.name}">Edit</Link
            >
            <Button
              variant="ghost"
              class="px-3 py-1.5"
              aria-label="Add field to {pivot.name}"
              onclick={() => open({ kind: 'field', pivot })}>Add field</Button
            >
            {#if owner}
              <Button
                variant="danger-ghost"
                class="px-3 py-1.5"
                aria-label="Delete {pivot.name}"
                onclick={() => destroy(pivots.destroy(pivot.id), `${pivot.name} and its fields`)}
              >
                Delete
              </Button>
            {/if}
          </div>
        </div>
        {#if pivot.fields.length === 0}
          <p class="px-3 py-3 text-sm text-ink-muted">No fields on this pivot yet.</p>
        {/if}
        {#if used(pivot).length}
          <ul class="divide-y divide-line">
            {#each used(pivot) as field (field.id)}
              {@render fieldRow(pivot, field)}
            {/each}
          </ul>
        {/if}
        {#if unused(pivot).length}
          <!-- Fields used only in other seasons (rotated out, or set up for a later one) -->
          <details class="border-t border-line first:border-t-0">
            <summary class="cursor-pointer px-3 py-2 text-xs text-ink-muted hover:text-ink">
              {unused(pivot).length === 1 ? '1 field' : `${unused(pivot).length} fields`} not used in {year - 1} or {year}
            </summary>
            <ul class="divide-y divide-line border-t border-line">
              {#each unused(pivot) as field (field.id)}
                {@render fieldRow(pivot, field)}
              {/each}
            </ul>
          </details>
        {/if}
      </div>
    {/each}
  </section>
{:else}
  <section
    class="rounded-lg border border-dashed border-line bg-surface-raised px-6 py-10 text-center text-sm text-ink-muted"
  >
    No farms yet. <Link href={newQuickSetup()} class="text-brand-600 underline underline-offset-2"
      >Set up your first pivot</Link
    >.
  </section>
{/each}

<div class="flex flex-wrap gap-3">
  <Button variant="secondary" onclick={() => open({ kind: 'farm' })}>Add a farm</Button>
  <Link
    href={fieldGroups.index()}
    class="rounded-md border border-line bg-surface-raised px-4 py-2 text-sm font-medium hover:bg-surface"
  >
    Field groups
  </Link>
  <Link
    href={groupRoutes.show()}
    class="rounded-md border border-line bg-surface-raised px-4 py-2 text-sm font-medium hover:bg-surface"
  >
    Operation settings and members
  </Link>
  {#if hasSeason}
    <a
      href={seasonReport({ query: { year } }).url}
      class="rounded-md border border-line bg-surface-raised px-4 py-2 text-sm font-medium hover:bg-surface"
      title="Every field's {year} season, irrigation by pivot and weather by zone, as one CSV"
      download
    >
      {year} season report (CSV)
    </a>
  {/if}
</div>

<PlantingDialog bind:this={plantingDialog} {year} {plants} soilTypes={soil_types} />

<Dialog bind:open={dialogOpen} title={dialogTitle}>
  {#if dialog?.kind === 'farm'}
    <Form
      action={dialog.farm ? farmRoutes.update(dialog.farm.id) : farmRoutes.create()}
      class="space-y-4"
      options={{ preserveScroll: true, preserveState: true }}
      onSuccess={close}
    >
      {#snippet children({ errors, processing })}
        <TextField
          label="Farm name"
          name="farm[name]"
          value={dialog?.kind === 'farm' ? (dialog.farm?.name ?? '') : ''}
          hint="A farm groups pivots you want to view and manage together"
          error={errors.name}
          required
        />
        <div class="space-y-1">
          <label for="farm-notes" class="block text-sm font-medium">Notes</label>
          <textarea id="farm-notes" name="farm[notes]" rows="2" class="block w-full rounded-md text-sm"
            >{dialog?.kind === 'farm' ? (dialog.farm?.notes ?? '') : ''}</textarea
          >
        </div>
        <Button type="submit" disabled={processing}>Save</Button>
      {/snippet}
    </Form>
  {:else if dialog?.kind === 'field'}
    <FieldForm
      field={dialog.field}
      pivotId={dialog.pivot.id}
      pivots={allPivots}
      soilTypes={soil_types}
      ondone={close}
    />
  {/if}
</Dialog>
