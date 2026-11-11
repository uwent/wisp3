<script lang="ts">
  import { untrack } from 'svelte'
  import { Form } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { plantings } from '@/routes'
  import type { Plant, Planting, SoilType } from '@/types/serializers'

  // One crop on a field for one season. Dates default to Apr 1 – Nov 30 with emergence May 1, and
  // the root zone depth to the crop's (as in legacy WISP). A season that has ended keeps its own soil
  // and area (PLAN.md Phase 8 G.9), which can be corrected here; one still running follows its field's.
  let {
    planting,
    fieldId,
    year,
    plants,
    soilTypes = [],
    ondone,
  }: {
    planting?: Planting
    fieldId: number
    year: number
    plants: Plant[]
    soilTypes?: SoilType[]
    ondone: () => void
  } = $props()

  // Form fields start from the props; the dialog mounts a new form each time it opens
  let plantId = $state(untrack(() => String(planting?.plant_id ?? '')))
  let rootDepth = $state<number | null>(untrack(() => planting?.max_root_zone_depth ?? null))
  let madFrac = $state<number | null>(untrack(() => planting?.mad_frac ?? 0.5))
  let etMethod = $state(untrack(() => planting?.et_method ?? 'pct_cover'))
  let interpolation = $state(untrack(() => planting?.canopy_interpolation ?? 'curve'))
  const plant = $derived(plants.find((p) => String(p.id) === plantId))
  // Whether the crop has a canopy curve for the chosen method (Planting#canopy_curve?)
  const hasCurve = $derived(etMethod === 'lai' ? plant?.has_lai_curve : plant?.has_cover_curve)
  // Potatoes are vine killed some weeks before harvest, and irrigated until it
  const endLabel = $derived(plant?.has_vine_kill ? 'Harvest' : 'Harvest or kill')

  // A new crop brings its default root zone depth unless one was typed
  let typedDepth = false
  function choosePlant(id: string) {
    plantId = id
    const chosen = plants.find((p) => String(p.id) === id)
    if (chosen && !typedDepth) rootDepth = chosen.default_max_root_zone_depth
    // LAI is offered only for crops with an LAI growth curve
    if (!chosen?.has_lai_curve) etMethod = 'pct_cover'
  }

  let seasonSoilId = $state(untrack(() => String(planting?.soil_type_id ?? '')))
  const seasonSoil = $derived(soilTypes.find((s) => String(s.id) === seasonSoilId))
  const pct = (fraction: number | undefined) => (fraction === undefined ? '' : `${Math.round(fraction * 1000) / 10}%`)

  const date = (name: string, label: string, value: string, error?: string | string[]) => ({
    name,
    label,
    value,
    error,
  })
</script>

<Form
  action={planting ? plantings.update(planting.id) : plantings.create({ query: { year } })}
  class="space-y-4"
  options={{ preserveScroll: true, preserveState: true }}
  onSuccess={ondone}
>
  {#snippet children({ errors, processing })}
    <input type="hidden" name="planting[field_id]" value={fieldId} />
    <div class="grid gap-4 sm:grid-cols-2">
      <SelectField
        label="Crop"
        name="planting[plant_id]"
        value={plantId}
        onchange={(event) => choosePlant(event.currentTarget.value)}
        options={[
          { value: '', label: 'Choose a crop' },
          ...plants.map((p) => ({ value: String(p.id), label: p.name })),
        ]}
        error={errors.plant}
        required
      />
      <TextField label="Variety" name="planting[variety]" value={planting?.variety ?? ''} />
    </div>
    <div class="grid gap-4 sm:grid-cols-3">
      {#each [date('season_start', 'Season start', planting?.season_start ?? `${year}-04-01`, errors.season_start), date('emergence_date', 'Emergence', planting?.emergence_date ?? `${year}-05-01`, errors.emergence_date), date('end_date', endLabel, planting?.end_date ?? `${year}-11-30`, errors.end_date)] as d (d.name)}
        <div class="space-y-1">
          <label class="block text-sm font-medium" for="planting-{d.name}">{d.label}</label>
          <input
            id="planting-{d.name}"
            type="date"
            name="planting[{d.name}]"
            value={d.value}
            required
            class="block w-full rounded-md text-sm {d.error ? 'border-status-irrigate' : ''}"
          />
          {#if d.error}<p class="text-sm text-status-irrigate-ink">
              {Array.isArray(d.error) ? d.error[0] : d.error}
            </p>{/if}
        </div>
      {/each}
    </div>
    {#if plant?.has_vine_kill}
      <div class="space-y-1 sm:w-1/3">
        <label class="block text-sm font-medium" for="planting-vine_kill_date">Vine kill</label>
        <input
          id="planting-vine_kill_date"
          type="date"
          name="planting[vine_kill_date]"
          value={planting?.vine_kill_date ?? ''}
          aria-describedby="planting-vine_kill_date-hint"
          class="block w-full rounded-md text-sm {errors.vine_kill_date ? 'border-status-irrigate' : ''}"
        />
        {#if errors.vine_kill_date}<p class="text-sm text-status-irrigate-ink">{errors.vine_kill_date}</p>{/if}
        <p id="planting-vine_kill_date-hint" class="text-sm text-ink-muted">
          Optional. From this date the canopy ramps down to nothing over two weeks, and WISP keeps the water balance
          going until harvest.
        </p>
      </div>
    {/if}
    <div class="grid gap-4 sm:grid-cols-2">
      <div oninput={() => (typedDepth = true)}>
        <NumberField
          label="Root zone depth"
          name="planting[max_root_zone_depth]"
          quantity="rootDepth"
          bind:value={rootDepth}
          error={errors.max_root_zone_depth}
        />
      </div>
      <NumberField
        label="Allowable depletion fraction (MAD)"
        name="planting[mad_frac]"
        scale={100}
        unitLabel="%"
        bind:value={madFrac}
        hint="How much of the available water the crop can use before you irrigate. 50% suits most crops."
        error={errors.mad_frac}
      />
    </div>
    <fieldset class="space-y-2">
      <legend class="text-sm font-medium">Canopy method</legend>
      <label class="flex items-start gap-3 text-sm">
        <input type="radio" name="planting[et_method]" value="pct_cover" bind:group={etMethod} class="mt-0.5" />
        <span
          >Percent cover <span class="text-ink-muted"
            >(enter canopy cover in the daily grid about weekly until the canopy closes)</span
          ></span
        >
      </label>
      {#if plant?.has_lai_curve}
        <label class="flex items-start gap-3 text-sm">
          <input type="radio" name="planting[et_method]" value="lai" bind:group={etMethod} class="mt-0.5" />
          <span>
            Leaf area index
            <span class="text-ink-muted"
              >(follows the {plant.name.toLowerCase()} growth curve unless you enter readings)</span
            >
          </span>
        </label>
      {/if}
    </fieldset>
    {#if hasCurve}
      <fieldset class="space-y-2">
        <legend class="text-sm font-medium">Between canopy readings</legend>
        <label class="flex items-start gap-3 text-sm">
          <input
            type="radio"
            name="planting[canopy_interpolation]"
            value="curve"
            bind:group={interpolation}
            class="mt-0.5"
          />
          <span
            >Follow the {plant!.name.toLowerCase()} curve
            <span class="text-ink-muted"
              >(fitted to your readings and passing through each one, including its late-season decline)</span
            ></span
          >
        </label>
        <label class="flex items-start gap-3 text-sm">
          <input
            type="radio"
            name="planting[canopy_interpolation]"
            value="linear"
            bind:group={interpolation}
            class="mt-0.5"
          />
          <span>Straight lines <span class="text-ink-muted">(keeping the last reading after it)</span></span>
        </label>
      </fieldset>
    {/if}
    <div class="grid gap-4 sm:grid-cols-2">
      <NumberField
        label="Target allowable depletion (AD)"
        name="planting[target_ad_pct]"
        unitLabel="%"
        value={planting?.target_ad_pct ?? null}
        hint="Optional. Irrigate before allowable depletion falls below this share of its maximum."
        error={errors.target_ad_pct}
      />
      <NumberField
        label="Starting soil moisture"
        name="planting[initial_moisture_pct]"
        unitLabel="%"
        value={planting?.initial_moisture_pct ?? null}
        hint="Leave blank to start the season at field capacity"
        error={errors.initial_moisture_pct}
      />
    </div>
    {#if planting?.ended && soilTypes.length}
      <details class="text-sm">
        <summary class="cursor-pointer text-ink-muted">Soil and area this season</summary>
        <div class="mt-3 space-y-4">
          <p class="text-ink-muted">
            This season has ended, so it keeps the soil and area it ran with; changes to the field apply only to seasons
            that haven't ended. Correct them here for this season.
          </p>
          <div class="grid gap-4 sm:grid-cols-2">
            <SelectField
              label="Soil"
              name="planting[soil_type_id]"
              bind:value={seasonSoilId}
              options={soilTypes.map((s) => ({ value: String(s.id), label: s.name }))}
              error={errors.soil_type}
            />
            <NumberField
              label="Area"
              name="planting[area_acres]"
              quantity="area"
              value={planting.area_acres}
              error={errors.area_acres}
            />
            <NumberField
              label="Field capacity"
              name="planting[field_capacity]"
              scale={100}
              unitLabel="%"
              value={planting.field_capacity}
              hint="Leave blank to use {seasonSoil?.name ?? 'the soil'} ({pct(seasonSoil?.field_capacity)})"
              error={errors.field_capacity}
            />
            <NumberField
              label="Wilting point"
              name="planting[perm_wilting_pt]"
              scale={100}
              unitLabel="%"
              value={planting.perm_wilting_pt}
              hint="Leave blank to use {seasonSoil?.name ?? 'the soil'} ({pct(seasonSoil?.perm_wilting_pt)})"
              error={errors.perm_wilting_pt}
            />
          </div>
        </div>
      </details>
    {/if}
    <div class="space-y-1">
      <label for="planting-notes" class="block text-sm font-medium">Notes</label>
      <textarea id="planting-notes" name="planting[notes]" rows="2" class="block w-full rounded-md text-sm"
        >{planting?.notes ?? ''}</textarea
      >
    </div>
    {#if errors.base}<p class="text-sm text-status-irrigate-ink">{errors.base}</p>{/if}
    <Button type="submit" disabled={processing}>{planting ? 'Save crop' : 'Add crop'}</Button>
  {/snippet}
</Form>
