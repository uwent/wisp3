<script lang="ts">
  import { untrack } from 'svelte'
  import { Form, page } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import PivotMap from '@/lib/components/PivotMap.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { DEFAULT_RADIUS_FT, pivotAcres } from '@/lib/geo'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { units as unitsFor } from '@/lib/units'
  import { quickSetups } from '@/routes'
  import type { Plant, SoilType } from '@/types/serializers'

  let {
    farms,
    plants,
    soil_types,
    default_soil_type_id,
    year,
  }: {
    farms: { id: number; name: string }[]
    plants: Plant[]
    soil_types: SoilType[]
    default_soil_type_id: number | null
    year: number
  } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))

  let farmId = $state<string>(untrack(() => (farms[0] ? String(farms[0].id) : '')))
  let latitude = $state<number | null>(null)
  let longitude = $state<number | null>(null)
  let radiusFt = $state<number | null>(DEFAULT_RADIUS_FT)

  let nextKey = 1
  const newRow = () => ({ key: nextKey++, name: '', area: null as number | null })
  let rows = $state([newRow()])

  const plantOptions = $derived([{ value: '', label: 'Choose a crop' }, ...plants.map((p) => ({ value: p.id, label: p.name }))])
  const soilOptions = $derived(soil_types.map((s) => ({ value: s.id, label: s.name })))
  const pivotArea = $derived(radiusFt ? pivotAcres(radiusFt) : null)

  // Ask before leaving with anything entered, and before saving a pivot with no fields
  let edited = $state(false)
  let saved = $state(false)
  confirmUnsavedChanges(() => !saved && (edited || latitude !== null))
  const confirmNoFields = () =>
    rows.some((row) => row.name.trim()) ||
    confirm("You haven't added any fields to this pivot. You can add them later in Setup. Save the pivot without fields?")

  const error = (errors: Record<string, string | string[]>, key: string) => errors[key]
</script>

<svelte:head><title>Set up a pivot · WISP</title></svelte:head>

<div>
  <h1 class="text-2xl font-semibold">Set up a pivot</h1>
  <p class="text-sm text-ink-muted">
    Place the pivot, then add the fields under it with their {year} crops. You can fine-tune everything later in Setup.
  </p>
</div>

<Form action={quickSetups.create()} class="space-y-6" onBefore={confirmNoFields} onSuccess={() => (saved = true)}>
  {#snippet children({ errors, processing })}
    {@const e = errors as Record<string, string | string[]>}
    <div class="space-y-6" oninput={() => (edited = true)} onchange={() => (edited = true)}>
      <section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
        <div>
          <h2 class="text-lg font-medium">1. Farm</h2>
          <p class="text-sm text-ink-muted">A farm groups pivots you want to view and manage together, such as one location or one operation.</p>
        </div>
        {#if farms.length}
          <SelectField
            label="Farm"
            name="setup[farm_id]"
            bind:value={farmId}
            options={[...farms.map((f) => ({ value: String(f.id), label: f.name })), { value: '', label: 'A new farm…' }]}
          />
        {/if}
        {#if !farmId}
          <TextField label="Farm name" name="setup[farm][name]" placeholder="e.g. Hancock Sands" error={error(e, 'farm.name')} />
        {/if}
      </section>

      <section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
        <div>
          <h2 class="text-lg font-medium">2. Pivot</h2>
          <p class="text-sm text-ink-muted">
            Weather comes from the pivot's location, so place it where it really is. You can move it or change any of this
            later in Setup.
          </p>
        </div>
        <TextField label="Pivot name" name="setup[pivot][name]" placeholder="e.g. North 160" error={error(e, 'pivot.name')} />
        <PivotMap bind:latitude bind:longitude bind:radiusFt />
        <div class="grid gap-4 sm:grid-cols-4">
          <NumberField label="Latitude" name="setup[pivot][latitude]" bind:value={latitude} error={error(e, 'pivot.latitude')} />
          <NumberField label="Longitude" name="setup[pivot][longitude]" bind:value={longitude} error={error(e, 'pivot.longitude')} />
          <NumberField
            label="Radius"
            name="setup[pivot][radius_ft]"
            quantity="distance"
            bind:value={radiusFt}
            error={error(e, 'pivot.radius_ft')}
            hint={pivotArea ? `About ${units.format('area', pivotArea)}` : undefined}
          />
          <NumberField
            label="Pump capacity"
            name="setup[pivot][pump_capacity_gpm]"
            quantity="flow"
            value={null}
            hint="Optional; lets you enter irrigation as run hours"
            error={error(e, 'pivot.pump_capacity_gpm')}
          />
        </div>
      </section>

      <section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
        <div>
          <h2 class="text-lg font-medium">3. Fields</h2>
          <p class="text-sm text-ink-muted">
            One field per crop under the pivot; a pivot split between two crops is two fields. Emergence defaults to May 1.
            You can also add fields later.
          </p>
        </div>
        {#if error(e, 'fields')}<p class="text-sm text-status-irrigate">{error(e, 'fields')}</p>{/if}
        {#each rows as row, i (row.key)}
          <fieldset class="grid gap-3 border-t border-line pt-4 first-of-type:border-0 first-of-type:pt-0 sm:grid-cols-6">
            <legend class="sr-only">Field {i + 1}</legend>
            <div class="sm:col-span-2">
              <TextField
                label="Field name"
                name="setup[fields][{i}][name]"
                bind:value={row.name}
                placeholder={rows.length > 1 ? `e.g. North ${i ? 'corn' : 'potatoes'}` : 'e.g. North 160'}
                error={error(e, `fields.${i}.name`)}
              />
            </div>
            <NumberField label="Area" name="setup[fields][{i}][area_acres]" quantity="area" bind:value={row.area} error={error(e, `fields.${i}.area_acres`)} />
            <SelectField label="Soil" name="setup[fields][{i}][soil_type_id]" value={default_soil_type_id ?? soil_types[0]?.id} options={soilOptions} />
            <SelectField label="Crop" name="setup[fields][{i}][plant_id]" value="" options={plantOptions} error={error(e, `fields.${i}.plant_id`)} />
            <div class="space-y-1">
              <label class="block text-sm font-medium" for="emergence-{row.key}">Emergence</label>
              <input
                id="emergence-{row.key}"
                type="date"
                name="setup[fields][{i}][emergence_date]"
                min="{year}-01-01"
                max="{year}-12-31"
                class="block w-full rounded-md shadow-sm sm:text-sm"
              />
              {#if error(e, `fields.${i}.emergence_date`)}<p class="text-sm text-status-irrigate">{error(e, `fields.${i}.emergence_date`)}</p>{/if}
            </div>
            {#if rows.length > 1}
              <div class="sm:col-span-6">
                <button type="button" class="text-sm text-status-irrigate hover:underline" onclick={() => (rows = rows.filter((r) => r.key !== row.key))}>
                  Remove this field
                </button>
              </div>
            {/if}
          </fieldset>
        {/each}
        <Button variant="secondary" onclick={() => rows.push(newRow())}>Add another field</Button>
      </section>

      <div class="flex items-center gap-3">
        <Button type="submit" disabled={processing}>Save and start tracking</Button>
        {#if Object.keys(e).length}<p class="text-sm text-status-irrigate">Please fix the highlighted fields.</p>{/if}
      </div>
    </div>
  {/snippet}
</Form>
