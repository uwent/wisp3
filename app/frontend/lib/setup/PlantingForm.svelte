<script lang="ts">
  import { untrack } from 'svelte'
  import { Form } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { addDays, formatDate } from '@/lib/dates'
  import { clashes, cropName, formatArea, plotAcres, seasonDates, typicalEnd } from '@/lib/plantings'
  import { fetchSoilSurvey, soilOptionsByShare, soilShares } from '@/lib/soils'
  import { units as unitsFor } from '@/lib/units'
  import { plantings } from '@/routes'
  import type { Field, GenericCurve, Plant, Planting, SoilType } from '@/types/serializers'
  import { page } from '@inertiajs/svelte'

  // One planting on a field for one season. Dates default to Apr 1 – Nov 30 with emergence May 1,
  // and the root zone depth to the crop's (as in legacy WISP). A season that has ended keeps its own
  // soil and area (PLAN.md Phase 8 G.9), which can be corrected here; one still running follows its
  // field's. A planting covers the whole field or part of it (G.11): length × width or acres, on the
  // field's soil or its own. A new whole-field planting overlapping another can replace it (ending
  // it the day before). template: a new planting's dates and size ("Add the next planting").
  let {
    planting,
    field,
    year,
    plants,
    soilTypes = [],
    genericCurves = [],
    template,
    ondone,
  }: {
    planting?: Planting
    field: Field
    year: number
    plants: Plant[]
    soilTypes?: SoilType[]
    /** Curves a crop without its own can follow (G.3) */
    genericCurves?: GenericCurve[]
    template?: Partial<Planting>
    ondone: () => void
  } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const start = untrack(() => planting ?? template)
  let seasonStart = $state(untrack(() => start?.season_start ?? `${year}-04-01`))
  let emergence = $state(untrack(() => start?.emergence_date ?? `${year}-05-01`))
  let endDate = $state(untrack(() => start?.end_date ?? `${year}-11-30`))

  // Whole field or part of it, sized by length × width or by acres
  let partial = $state(untrack(() => start?.partial ?? false))
  let sizeBy = $state<'plot' | 'acres'>(
    untrack(() => (start?.partial && start.plot_length_ft === null ? 'acres' : 'plot')),
  )
  let lengthFt = $state<number | null>(untrack(() => start?.plot_length_ft ?? null))
  let widthFt = $state<number | null>(untrack(() => start?.plot_width_ft ?? null))
  let acres = $state<number | null>(untrack(() => (start?.partial ? (start.area_acres ?? null) : null)))
  const plotArea = $derived(sizeBy === 'plot' ? (lengthFt && widthFt ? plotAcres(lengthFt, widthFt) : null) : acres)
  const tooBig = $derived(plotArea !== null && field.area_acres !== null && plotArea > field.area_acres + 1e-6)

  // The plantings on this field this one would clash with, and the ones "Replace" would end
  const others = $derived(field.plantings.filter((other) => other.id !== planting?.id))
  const clashing = $derived(
    seasonStart && endDate ? clashes({ season_start: seasonStart, end_date: endDate, partial }, others) : [],
  )
  // Replace ends each the day before this one starts, after its emergence (PlantingsController)
  const replaceable = $derived(
    !planting && clashing.length > 0 && clashing.every((other) => other.emergence_date < seasonStart),
  )
  let replace = $state(false)

  // A plot follows the field's soil unless it has its own
  let ownSoil = $state(untrack(() => planting?.own_soil ?? false))
  let plotSoilId = $state(untrack(() => String(planting?.own_soil ? planting.soil_type_id : field.soil_type_id)))
  const plotSoil = $derived(soilTypes.find((s) => String(s.id) === plotSoilId))
  // On a field with an outline, the soils in it first, with their share (G.11 item 10, G.10): read
  // from the soil survey once the plot is given its own soil
  let fieldShares = $state<Map<string, number> | null>(null)
  $effect(() => {
    if (!ownSoil || !field.boundary || fieldShares) return
    const request = new AbortController()
    fetchSoilSurvey(field.boundary, request.signal)
      .then((units) => (fieldShares = soilShares(units)))
      .catch(() => {}) // the survey can't be reached: the plain list stays
    return () => request.abort()
  })
  const plotSoilOptions = $derived(
    fieldShares
      ? soilOptionsByShare(soilTypes, fieldShares)
      : soilTypes.map((s) => ({ value: String(s.id), label: s.name })),
  )

  // Form fields start from the props; the dialog mounts a new form each time it opens
  let plantId = $state(untrack(() => String(planting?.plant_id ?? '')))
  let rootDepth = $state<number | null>(untrack(() => planting?.max_root_zone_depth ?? null))
  let madFrac = $state<number | null>(untrack(() => planting?.mad_frac ?? 0.5))
  let etMethod = $state(untrack(() => planting?.et_method ?? 'pct_cover'))
  let interpolation = $state(untrack(() => planting?.canopy_interpolation ?? 'curve'))
  const plant = $derived(plants.find((p) => String(p.id) === plantId))
  // Whether the crop has a canopy curve for the chosen method (Planting#canopy_curve?)
  // A crop without its own percent cover curve follows a generic one, its default unless another is
  // picked, or none (readings only) (PLAN.md Phase 8 G.3)
  const NONE = 'none'
  const generic = $derived(plant !== undefined && !plant.has_cover_curve && etMethod === 'pct_cover')
  let curveChoice = $state(untrack(() => planting?.canopy_curve_key ?? ''))
  const curveKey = $derived(curveChoice || plant?.default_generic_curve || NONE)
  const genericCurve = $derived(genericCurves.find((c) => c.key === curveKey))
  const hasCurve = $derived(
    etMethod === 'lai' ? plant?.has_lai_curve : plant?.has_cover_curve || (generic && curveKey !== NONE),
  )
  // The typical season: the crop's own, or its generic curve's
  const seasonDays = $derived(plant?.has_cover_curve ? plant.season_days : (genericCurve?.season_days ?? null))
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
    suggestEnd()
  }

  // A new planting's harvest follows the crop's typical season from emergence (PLAN.md Phase 8 G.2)
  // until a date is typed; an existing one keeps its own
  let endChosen = untrack(() => planting !== undefined)
  function suggestEnd() {
    if (!endChosen && plant && emergence) endDate = typicalEnd(seasonDays, emergence)
  }

  let seasonSoilId = $state(untrack(() => String(planting?.soil_type_id ?? '')))
  const seasonSoil = $derived(soilTypes.find((s) => String(s.id) === seasonSoilId))
  const pct = (fraction: number | undefined) => (fraction === undefined ? '' : `${Math.round(fraction * 1000) / 10}%`)
</script>

<Form
  action={planting ? plantings.update(planting.id) : plantings.create({ query: { year } })}
  class="space-y-4"
  options={{ preserveScroll: true, preserveState: true }}
  onSuccess={ondone}
>
  {#snippet children({ errors, processing })}
    <input type="hidden" name="planting[field_id]" value={field.id} />
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
      {#snippet dateInput(
        name: string,
        label: string,
        error: string | string[] | undefined,
        value: string,
        set: (v: string) => void,
      )}
        <div class="space-y-1">
          <label class="block text-sm font-medium" for="planting-{name}">{label}</label>
          <input
            id="planting-{name}"
            type="date"
            name="planting[{name}]"
            {value}
            oninput={(event) => set(event.currentTarget.value)}
            required
            class="block w-full rounded-md text-sm {error ? 'border-status-irrigate' : ''}"
          />
          {#if error}<p class="text-sm text-status-irrigate-ink">{Array.isArray(error) ? error[0] : error}</p>{/if}
        </div>
      {/snippet}
      {@render dateInput('season_start', 'Season start', errors.season_start, seasonStart, (v) => (seasonStart = v))}
      {@render dateInput('emergence_date', 'Emergence', errors.emergence_date, emergence, (v) => {
        emergence = v
        suggestEnd()
      })}
      {@render dateInput('end_date', endLabel, errors.end_date, endDate, (v) => {
        endDate = v
        endChosen = true
      })}
    </div>
    {#if plant && seasonDays}
      <p class="-mt-2 text-sm text-ink-muted">
        A {plant.name.toLowerCase()} season typically runs about {seasonDays} days from emergence to harvest{plant.has_cover_curve
          ? '.'
          : ` (${genericCurve?.name.toLowerCase()} curve).`}
      </p>
    {/if}

    <fieldset class="space-y-3">
      <legend class="text-sm font-medium">Planting size</legend>
      <input type="hidden" name="planting[partial]" value={String(partial)} />
      <div
        class="flex flex-col overflow-hidden rounded-md border border-line text-sm sm:w-fit sm:flex-row"
        role="radiogroup"
      >
        {#each [[false, `Whole field (${formatArea(units, field.area_acres)})`], [true, 'Part of the field']] as const as [value, label] (label)}
          <label
            class="flex flex-1 cursor-pointer items-center gap-2 px-3 py-1.5 whitespace-nowrap has-checked:bg-brand-600 has-checked:text-white
              has-focus-visible:outline-2 has-focus-visible:outline-brand-500 dark:has-checked:text-surface"
          >
            <input
              type="radio"
              class="sr-only"
              name="planting-size"
              checked={partial === value}
              onchange={() => (partial = value)}
            />
            {label}
          </label>
        {/each}
      </div>
      {#if partial}
        <div class="space-y-3 rounded-md border border-line p-3">
          <div class="flex flex-wrap gap-4 text-sm">
            <label class="flex items-center gap-2"
              ><input type="radio" name="planting-size-by" value="plot" bind:group={sizeBy} /> Length × width</label
            >
            <label class="flex items-center gap-2"
              ><input type="radio" name="planting-size-by" value="acres" bind:group={sizeBy} /> Area</label
            >
          </div>
          {#if sizeBy === 'plot'}
            <div class="grid gap-4 sm:grid-cols-3">
              <NumberField
                label="Length"
                name="planting[plot_length_ft]"
                quantity="distance"
                bind:value={lengthFt}
                required
                error={errors.plot_length_ft}
              />
              <NumberField
                label="Width"
                name="planting[plot_width_ft]"
                quantity="distance"
                bind:value={widthFt}
                required
                error={errors.plot_width_ft}
              />
              <div class="space-y-1 text-sm">
                <p class="font-medium">Area</p>
                <p class="py-2 tabular-nums" aria-live="polite">{plotArea ? formatArea(units, plotArea) : '—'}</p>
              </div>
            </div>
          {:else}
            <input type="hidden" name="planting[plot_length_ft]" value="" />
            <input type="hidden" name="planting[plot_width_ft]" value="" />
            <div class="sm:w-1/2">
              <NumberField
                label="Area"
                name="planting[area_acres]"
                quantity="area"
                bind:value={acres}
                required
                error={errors.area_acres}
              />
            </div>
          {/if}
          {#if tooBig}
            <p class="text-sm text-status-irrigate-ink">
              That's more than the field's {formatArea(units, field.area_acres)}.
            </p>
          {:else if sizeBy === 'plot' && errors.area_acres}
            <p class="text-sm text-status-irrigate-ink">{errors.area_acres}</p>
          {/if}
          {#if soilTypes.length}
            <label class="flex items-start gap-2 text-sm">
              <input
                type="checkbox"
                class="mt-0.5"
                checked={!ownSoil}
                onchange={(e) => (ownSoil = !e.currentTarget.checked)}
              />
              <span>Use the field's soil ({field.soil_type_name})</span>
            </label>
            <input type="hidden" name="planting[own_soil]" value={String(ownSoil)} />
            {#if ownSoil}
              <div class="grid gap-4 sm:grid-cols-3">
                <SelectField
                  label="Soil"
                  name="planting[soil_type_id]"
                  bind:value={plotSoilId}
                  options={plotSoilOptions}
                  hint={fieldShares ? "From the soil survey of the field's outline" : undefined}
                  error={errors.soil_type}
                />
                <NumberField
                  label="Field capacity"
                  name="planting[field_capacity]"
                  scale={100}
                  unitLabel="%"
                  value={planting?.own_soil ? planting.field_capacity : null}
                  hint="Blank: {pct(plotSoil?.field_capacity)}"
                  error={errors.field_capacity}
                />
                <NumberField
                  label="Wilting point"
                  name="planting[perm_wilting_pt]"
                  scale={100}
                  unitLabel="%"
                  value={planting?.own_soil ? planting.perm_wilting_pt : null}
                  hint="Blank: {pct(plotSoil?.perm_wilting_pt)}"
                  error={errors.perm_wilting_pt}
                />
              </div>
            {/if}
          {/if}
        </div>
      {/if}
      {#if clashing.length}
        <div
          role="status"
          class="space-y-2 rounded-md border border-status-caution/60 bg-status-caution/10 px-3 py-2 text-sm"
        >
          <p>
            {partial ? 'This overlaps a planting covering the whole field' : 'This overlaps'}:
            {clashing.map((other) => `${cropName(other)} (${seasonDates(other)})`).join(', ')}.
            {#if partial}Make that one part of the field too, or change the dates.{:else}Choose Part of the field if
              they grow side by side{replaceable ? ', or replace it.' : '.'}{/if}
          </p>
          {#if replaceable && !partial}
            <label class="flex items-start gap-2">
              <input type="checkbox" class="mt-0.5" bind:checked={replace} />
              {#if replace}<input type="hidden" name="replace" value="1" />{/if}
              <span>
                Replace: end {clashing.map((other) => other.plant_name).join(' and ')} on {formatDate(
                  addDays(seasonStart, -1),
                )}
              </span>
            </label>
          {/if}
        </div>
      {/if}
    </fieldset>
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
    <!-- Blank leaves the crop's own curve or its default; a crop with its own never sends one -->
    <input type="hidden" name="planting[canopy_curve_key]" value={generic ? curveChoice : ''} />
    {#if generic}
      <fieldset class="space-y-2">
        <legend class="text-sm font-medium">Canopy curve</legend>
        <p class="text-sm text-ink-muted">WISP has no canopy curve of its own for {plant!.name.toLowerCase()}.</p>
        {#each genericCurves as curve (curve.key)}
          <label class="flex items-start gap-3 text-sm">
            <input
              type="radio"
              name="planting-canopy-curve"
              checked={curveKey === curve.key}
              onchange={() => {
                // The default is left blank, so the crop follows it if it changes
                curveChoice = curve.key === plant!.default_generic_curve ? '' : curve.key
                suggestEnd()
              }}
              class="mt-0.5"
            />
            <span
              >{curve.name}{curve.key === plant!.default_generic_curve ? ' (suggested)' : ''}
              <span class="block text-ink-muted">{curve.basis}</span></span
            >
          </label>
        {/each}
        <label class="flex items-start gap-3 text-sm">
          <input
            type="radio"
            name="planting-canopy-curve"
            checked={curveKey === NONE}
            onchange={() => {
              curveChoice = NONE
              suggestEnd()
            }}
            class="mt-0.5"
          />
          <span>No curve: readings only</span>
        </label>
        <p role="status" class="rounded-md border border-line px-3 py-2 text-sm">
          {#if curveKey === NONE}
            Irrigation scheduling works only if you enter percent cover regularly, about weekly until the canopy closes.
            Until the first reading, WISP can't estimate this crop's water use.
          {:else}
            An approximation for {plant!.name.toLowerCase()}: your percent cover readings correct it, so enter one now
            and then.
          {/if}
        </p>
      </fieldset>
    {/if}
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
            >Follow the {generic ? `${genericCurve?.name.toLowerCase()} curve` : `${plant!.name.toLowerCase()} curve`}
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
    {#if planting?.ended && soilTypes.length && !partial}
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
    <Button type="submit" disabled={processing || tooBig}>{planting ? 'Save planting' : 'Add planting'}</Button>
  {/snippet}
</Form>
