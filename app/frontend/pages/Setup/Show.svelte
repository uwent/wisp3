<script lang="ts">
  import { Form, Link, page, router } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import Dialog from '@/lib/components/Dialog.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { formatDate } from '@/lib/dates'
  import { units as unitsFor } from '@/lib/units'
  import FieldForm from '@/lib/setup/FieldForm.svelte'
  import PlantingForm from '@/lib/setup/PlantingForm.svelte'
  import {
    farms as farmRoutes,
    fieldGroups,
    fields,
    groups as groupRoutes,
    newQuickSetup,
    pivots,
    plantings,
    seasonCopies,
    setup,
  } from '@/routes'
  import type { Farm, Field, Pivot, Plant, Planting, SoilType } from '@/types/serializers'

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
  const seasonPlantings = (field: Field) => field.plantings.filter((planting) => planting.year === year)
  const hasLastSeason = $derived(
    allPivots.some((p) => p.fields.some((f) => f.plantings.some((pl) => pl.year === year - 1))),
  )

  type DialogState =
    | { kind: 'farm'; farm?: Farm }
    | { kind: 'field'; pivot: Pivot; field?: Field }
    | { kind: 'planting'; field: Field; planting?: Planting }
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
    if (dialog.kind === 'field')
      return dialog.field ? `Edit ${dialog.field.name}` : `Add a field to ${dialog.pivot.name}`
    return dialog.planting
      ? `Edit ${dialog.planting.plant_name} on ${dialog.field.name}`
      : `Add a ${year} crop to ${dialog.field.name}`
  })
</script>

<svelte:head><title>Setup · WISP</title></svelte:head>

<div class="flex flex-wrap items-end justify-between gap-3">
  <div>
    <h1 class="text-2xl font-semibold">Setup</h1>
    <p class="text-sm text-ink-muted">Farms, pivots, fields and each season's crops for {group.name}</p>
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
        Growing the same crops as {year - 1}? Copy last season's crops to {year}, with the same settings and dates a
        year later.
      </p>
      <Button type="submit" variant="secondary" disabled={processing}>Copy {year - 1} crops</Button>
    {/snippet}
  </Form>
{/if}

{#each farms as farm (farm.id)}
  <section class="space-y-4 rounded-lg border border-line bg-surface-raised p-4 sm:p-6">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <div class="min-w-0">
        <h2 class="text-lg font-medium">{farm.name}</h2>
        {#if farm.notes}<p class="text-sm whitespace-pre-line text-ink-muted">{farm.notes}</p>{/if}
      </div>
      <div class="flex gap-1 text-sm">
        <Link
          href={pivots.new({ query: { farm_id: farm.id } })}
          class="rounded-md px-3 py-1.5 text-brand-600 hover:bg-brand-50">Add pivot</Link
        >
        <Button variant="ghost" class="px-3 py-1.5" onclick={() => open({ kind: 'farm', farm })}>Edit</Button>
        {#if owner}
          <Button
            variant="danger-ghost"
            class="px-3 py-1.5"
            onclick={() => destroy(farmRoutes.destroy(farm.id), `${farm.name} and all its pivots and fields`)}
          >
            Delete
          </Button>
        {/if}
      </div>
    </div>

    {#if farm.pivots.length === 0}
      <p class="text-sm text-ink-muted">No pivots yet.</p>
    {/if}

    {#each farm.pivots as pivot (pivot.id)}
      <div class="rounded-md border border-line">
        <div class="flex flex-wrap items-center justify-between gap-2 border-b border-line bg-surface px-3 py-2">
          <div>
            <h3 class="font-medium">{pivot.name}</h3>
            <p class="text-xs text-ink-muted">
              {pivot.latitude.toFixed(4)}, {pivot.longitude.toFixed(4)}
              {#if pivot.radius_ft}
                · radius {units.format('distance', pivot.radius_ft)}{/if}
              {#if pivot.pump_capacity_gpm}
                · pump {units.format('flow', pivot.pump_capacity_gpm)}{/if}
              {#if pivot.equipment}
                · {pivot.equipment}{/if}
            </p>
          </div>
          <div class="flex flex-wrap gap-1 text-sm">
            <Link href={pivots.show(pivot.id)} class="rounded-md px-3 py-1.5 text-brand-600 hover:bg-brand-50"
              >Irrigation</Link
            >
            <Link href={pivots.edit(pivot.id)} class="rounded-md px-3 py-1.5 text-brand-600 hover:bg-brand-50"
              >Edit</Link
            >
            <Button variant="ghost" class="px-3 py-1.5" onclick={() => open({ kind: 'field', pivot })}>Add field</Button
            >
            {#if owner}
              <Button
                variant="danger-ghost"
                class="px-3 py-1.5"
                onclick={() => destroy(pivots.destroy(pivot.id), `${pivot.name} and its fields`)}
              >
                Delete
              </Button>
            {/if}
          </div>
        </div>

        {#if pivot.fields.length === 0}
          <p class="px-3 py-3 text-sm text-ink-muted">No fields yet.</p>
        {:else}
          <ul class="divide-y divide-line">
            {#each pivot.fields as field (field.id)}
              <li class="flex flex-wrap items-center gap-x-4 gap-y-2 px-3 py-2">
                <div class="min-w-40 flex-1">
                  <Link href={fields.show(field.id)} class="font-medium hover:underline">{field.name}</Link>
                  <p class="text-xs text-ink-muted">
                    {units.format('area', field.area_acres)} · {field.soil_type_name}
                    {#if field.field_capacity !== null || field.perm_wilting_pt !== null}(custom FC/PWP){/if}
                    {#if field.use_model_precip !== null}· {field.use_model_precip
                        ? 'modeled rain'
                        : 'entered rain only'}{/if}
                  </p>
                </div>
                <div class="flex flex-wrap items-center gap-2">
                  {#each seasonPlantings(field) as planting (planting.id)}
                    <button
                      type="button"
                      class="rounded-full border border-line bg-surface px-3 py-1 text-xs hover:border-brand-500"
                      onclick={() => open({ kind: 'planting', field, planting })}
                      title="Edit this crop"
                    >
                      <span class="font-medium">{planting.plant_name}</span>
                      <span class="text-ink-muted"
                        >{formatDate(planting.emergence_date)} – {formatDate(planting.end_date)}</span
                      >
                    </button>
                  {:else}
                    <span class="text-xs text-ink-muted">No {year} crop</span>
                  {/each}
                  <Button variant="ghost" class="px-2 py-1 text-xs" onclick={() => open({ kind: 'planting', field })}
                    >+ Crop</Button
                  >
                </div>
                <div class="flex gap-1 text-xs">
                  <Button
                    variant="ghost"
                    class="px-2 py-1 text-xs"
                    onclick={() => open({ kind: 'field', pivot, field })}>Edit</Button
                  >
                  {#if owner}
                    <Button
                      variant="danger-ghost"
                      class="px-2 py-1 text-xs"
                      onclick={() => destroy(fields.destroy(field.id), `${field.name} and all its records`)}
                    >
                      Delete
                    </Button>
                  {/if}
                </div>
              </li>
            {/each}
          </ul>
        {/if}
      </div>
    {/each}
  </section>
{:else}
  <section
    class="rounded-lg border border-dashed border-line bg-surface-raised px-6 py-10 text-center text-sm text-ink-muted"
  >
    No farms yet. <Link href={newQuickSetup()} class="text-brand-600 hover:underline">Set up your first pivot</Link>.
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
</div>

<Dialog bind:open={dialogOpen} title={dialogTitle} wide={dialog?.kind === 'planting'}>
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
  {:else if dialog?.kind === 'planting'}
    <PlantingForm planting={dialog.planting} fieldId={dialog.field.id} {year} {plants} ondone={close} />
    {#if dialog.planting}
      <button
        type="button"
        class="mt-4 text-sm text-status-irrigate hover:underline"
        onclick={() => {
          if (dialog?.kind !== 'planting' || !dialog.planting) return
          if (
            destroy(
              plantings.destroy(dialog.planting.id),
              `this ${dialog.planting.plant_name} crop and its canopy readings`,
            )
          )
            close()
        }}
      >
        Delete this crop
      </button>
    {/if}
  {/if}
</Dialog>
