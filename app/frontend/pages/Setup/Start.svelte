<script lang="ts">
  import { untrack } from 'svelte'
  import { Form } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import PivotShapeFields from '@/lib/components/PivotShapeFields.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { isPoint, KIND_NOUNS, shapeDraft } from '@/lib/geo'
  import { typicalEnd } from '@/lib/plantings'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
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

  let farmId = $state<string>(untrack(() => (farms[0] ? String(farms[0].id) : '')))
  let shape = $state(shapeDraft())
  // "pivot", "drip block"
  const noun = $derived(KIND_NOUNS[shape.kind])

  // A field's soil follows the soil survey's suggestion until the user picks one
  let suggestedSoilId = $state<number | null>(null)
  const defaultSoilId = () => String(suggestedSoilId ?? default_soil_type_id ?? soil_types[0]?.id ?? '')
  let nextKey = 1
  const newRow = () => ({
    key: nextKey++,
    name: '',
    area: null as number | null,
    soilTypeId: defaultSoilId(),
    soilChosen: false,
    plantId: '',
    emergence: '',
    // The harvest follows the crop and emergence (typicalEnd) until the user picks one (PLAN.md G.2)
    harvest: '',
    harvestChosen: false,
  })
  type Row = ReturnType<typeof newRow>
  function suggestHarvest(row: Row) {
    if (row.harvestChosen) return
    const plant = plants.find((p) => String(p.id) === row.plantId)
    row.harvest = plant ? typicalEnd(plant.season_days, row.emergence || `${year}-05-01`) : ''
  }
  let rows = $state([newRow()])

  const plantOptions = $derived([
    { value: '', label: 'Choose a crop' },
    ...plants.map((p) => ({ value: String(p.id), label: p.name })),
  ])
  const soilOptions = $derived(soil_types.map((s) => ({ value: String(s.id), label: s.name })))

  function suggestSoil(soil: SoilType | null) {
    suggestedSoilId = soil?.id ?? null
    for (const row of rows) if (!row.soilChosen) row.soilTypeId = defaultSoilId()
  }

  // Ask before leaving with anything entered, and before saving a pivot with no fields
  let edited = $state(false)
  let saved = $state(false)
  confirmUnsavedChanges(() => !saved && (edited || shape.latitude !== null))
  const confirmNoFields = () =>
    rows.some((row) => row.name.trim()) ||
    confirm(`You haven't added any fields to this ${noun}. You can add them later in Setup. Save it without fields?`)

  const error = (errors: Record<string, string | string[]>, key: string) => errors[key]
</script>

<svelte:head><title>Set up an irrigation system · WISP</title></svelte:head>

<div>
  <h1 class="text-2xl font-semibold">Set up an irrigation system</h1>
  <p class="text-sm text-ink-muted">
    Place the pivot, traveler, drip block or other system, then add the fields it waters with their {year} crops. You can
    fine-tune everything later in Setup.
  </p>
</div>

<Form action={quickSetups.create()} class="space-y-6" onBefore={confirmNoFields} onSuccess={() => (saved = true)}>
  {#snippet children({ errors, processing })}
    {@const e = errors as Record<string, string | string[]>}
    <div class="space-y-6" oninput={() => (edited = true)} onchange={() => (edited = true)}>
      <section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
        <div>
          <h2 class="text-lg font-medium">1. Farm</h2>
          <p class="text-sm text-ink-muted">
            A farm groups irrigation systems you want to view and manage together, such as one location or one
            operation.
          </p>
        </div>
        {#if farms.length}
          <SelectField
            label="Farm"
            name="setup[farm_id]"
            bind:value={farmId}
            options={[
              ...farms.map((f) => ({ value: String(f.id), label: f.name })),
              { value: '', label: 'A new farm…' },
            ]}
          />
        {/if}
        {#if !farmId}
          <TextField
            label="Farm name"
            name="setup[farm][name]"
            placeholder="e.g. Hancock Sands"
            error={error(e, 'farm.name')}
          />
        {/if}
      </section>

      <section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
        <div>
          <h2 class="text-lg font-medium">2. Irrigation system</h2>
          <p class="text-sm text-ink-muted">
            Weather comes from its location, so place it where it really is. You can move it or change any of this later
            in Setup.
          </p>
        </div>
        <TextField
          label="Name"
          name="setup[pivot][name]"
          placeholder={shape.kind === 'center' ? 'e.g. North 160' : 'e.g. Home garden'}
          error={error(e, 'pivot.name')}
        />
        <PivotShapeFields
          bind:shape
          prefix="setup[pivot]"
          error={(attribute) => error(e, `pivot.${attribute}`)}
          soilTypes={soil_types}
          onsuggest={suggestSoil}
        />
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <NumberField
            label={isPoint(shape.kind) ? 'Flow' : 'Pump capacity'}
            name="setup[pivot][pump_capacity_gpm]"
            quantity="flow"
            value={null}
            hint="Optional. With it, you can enter irrigation as hours the {noun} ran."
            error={error(e, 'pivot.pump_capacity_gpm')}
          />
        </div>
      </section>

      <section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
        <div>
          <h2 class="text-lg font-medium">3. Fields</h2>
          <p class="text-sm text-ink-muted">
            Add each field it waters, with what's planted on it this season; a pivot split between two fields you manage
            separately is two fields. If you leave the emergence date blank, WISP uses May 1. The harvest date follows
            from the crop's typical season; change it if yours ends sooner or later. You can add fields and more
            plantings later.
          </p>
        </div>
        {#if error(e, 'fields')}<p class="text-sm text-status-irrigate-ink">{error(e, 'fields')}</p>{/if}
        {#each rows as row, i (row.key)}
          <fieldset
            class="grid gap-3 border-t border-line pt-4 first-of-type:border-0 first-of-type:pt-0 sm:grid-cols-4 lg:grid-cols-7"
          >
            <legend class="sr-only">Field {i + 1}</legend>
            <div class="sm:col-span-2">
              <TextField
                label="Field name"
                name="setup[fields][{i}][name]"
                bind:value={row.name}
                placeholder={rows.length > 1 ? `e.g. ${i ? 'South' : 'North'} half` : 'e.g. North 160'}
                error={error(e, `fields.${i}.name`)}
              />
            </div>
            <NumberField
              label="Area"
              name="setup[fields][{i}][area_acres]"
              quantity="area"
              bind:value={row.area}
              error={error(e, `fields.${i}.area_acres`)}
            />
            <SelectField
              label="Soil"
              name="setup[fields][{i}][soil_type_id]"
              bind:value={row.soilTypeId}
              onchange={() => (row.soilChosen = true)}
              options={soilOptions}
              hint={!row.soilChosen && suggestedSoilId !== null ? 'From the soil survey' : undefined}
            />
            <SelectField
              label="Crop"
              name="setup[fields][{i}][plant_id]"
              bind:value={row.plantId}
              onchange={() => suggestHarvest(row)}
              hint={plants.find((p) => String(p.id) === row.plantId && !p.has_cover_curve)
                ? 'No curve of its own: a generic one, corrected by your readings'
                : undefined}
              options={plantOptions}
              error={error(e, `fields.${i}.plant_id`)}
            />
            <div class="space-y-1">
              <label class="block text-sm font-medium" for="emergence-{row.key}">Emergence</label>
              <input
                id="emergence-{row.key}"
                type="date"
                name="setup[fields][{i}][emergence_date]"
                min="{year}-01-01"
                max="{year}-12-31"
                bind:value={row.emergence}
                oninput={() => suggestHarvest(row)}
                class="block w-full rounded-md shadow-sm sm:text-sm"
              />
              {#if error(e, `fields.${i}.emergence_date`)}<p class="text-sm text-status-irrigate-ink">
                  {error(e, `fields.${i}.emergence_date`)}
                </p>{/if}
            </div>
            <div class="space-y-1">
              <label class="block text-sm font-medium" for="harvest-{row.key}">Harvest (expected)</label>
              <input
                id="harvest-{row.key}"
                type="date"
                name="setup[fields][{i}][end_date]"
                min="{year}-01-01"
                bind:value={row.harvest}
                oninput={() => (row.harvestChosen = true)}
                class="block w-full rounded-md shadow-sm sm:text-sm"
              />
              {#if error(e, `fields.${i}.end_date`)}<p class="text-sm text-status-irrigate-ink">
                  {error(e, `fields.${i}.end_date`)}
                </p>{/if}
            </div>
            {#if rows.length > 1}
              <div class="sm:col-span-4 lg:col-span-7">
                <button
                  type="button"
                  class="text-sm text-status-irrigate-ink hover:underline"
                  onclick={() => (rows = rows.filter((r) => r.key !== row.key))}
                >
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
        {#if Object.keys(e).length}<p class="text-sm text-status-irrigate-ink">
            Please correct the highlighted entries.
          </p>{/if}
      </div>
    </div>
  {/snippet}
</Form>
