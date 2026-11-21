<script lang="ts">
  import { untrack } from 'svelte'
  import { Form } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import FieldLabel from '@/lib/components/FieldLabel.svelte'
  import FormFooter from '@/lib/components/FormFooter.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { addDays, formatDate } from '@/lib/dates'
  import type { FieldInfoKey } from '@/lib/fieldInfo'
  import {
    canReplace,
    clashes,
    cropName,
    dateProblems,
    formatArea,
    plotAcres,
    seasonDates,
    typicalEnd,
  } from '@/lib/plantings'
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
  //
  // Laid out for a first pass (G.13 part 3): a new planting shows only the crop until one is chosen,
  // then its season and size, filled in from the crop; the rest (root zone, MAD, canopy, targets) is
  // under Settings, collapsed to a line saying what's in effect, and opened when one has an error.
  // Dates are checked as they're typed (dateProblems). Defaults show as placeholders in blank boxes.
  let {
    planting,
    field,
    year,
    plants,
    soilTypes = [],
    genericCurves = [],
    template,
    ondone,
    ondelete,
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
    /** Deletes the planting (asking first); left out for a new one */
    ondelete?: () => void
  } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const start = untrack(() => planting ?? template)
  let seasonStart = $state(untrack(() => start?.season_start ?? `${year}-04-01`))
  let emergence = $state(untrack(() => start?.emergence_date ?? `${year}-05-01`))
  let endDate = $state(untrack(() => start?.end_date ?? `${year}-11-30`))

  // Whole field or part of it, sized by acres (the default) or by length × width
  let partial = $state(untrack(() => start?.partial ?? false))
  let sizeBy = $state<'plot' | 'acres'>(
    untrack(() => (start?.partial && start.plot_length_ft !== null ? 'plot' : 'acres')),
  )
  let lengthFt = $state<number | null>(untrack(() => start?.plot_length_ft ?? null))
  let widthFt = $state<number | null>(untrack(() => start?.plot_width_ft ?? null))
  let acres = $state<number | null>(untrack(() => (start?.partial ? (start.area_acres ?? null) : null)))
  const plotArea = $derived(sizeBy === 'plot' ? (lengthFt && widthFt ? plotAcres(lengthFt, widthFt) : null) : acres)
  const tooBig = $derived(
    partial && plotArea !== null && field.area_acres !== null && plotArea > field.area_acres + 1e-6,
  )

  // The plantings on this field this one would clash with, and the ones "Replace" would end
  const others = $derived(field.plantings.filter((other) => other.id !== planting?.id))
  const clashing = $derived(
    seasonStart && endDate ? clashes({ season_start: seasonStart, end_date: endDate, partial }, others) : [],
  )
  // Replace ends each the day before this one starts, still after its start and emergence
  const replaceable = $derived(
    !planting && clashing.length > 0 && clashing.every((other) => canReplace(other, seasonStart)),
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
  // Blank root zone and MAD stand for the crop's default depth and 50%, shown as placeholders and
  // submitted when blank; a planting on the defaults opens with them blank
  const DEFAULT_MAD = 0.5
  let rootDepth = $state<number | null>(
    untrack(() => {
      const crop = plants.find((p) => p.id === planting?.plant_id)
      const depth = planting?.max_root_zone_depth ?? null
      return depth !== null && crop && Math.abs(depth - crop.default_max_root_zone_depth) < 1e-9 ? null : depth
    }),
  )
  let madFrac = $state<number | null>(
    untrack(() => (planting && Math.abs(planting.mad_frac - DEFAULT_MAD) > 1e-9 ? planting.mad_frac : null)),
  )
  let targetAd = $state<number | null>(untrack(() => planting?.target_ad_pct ?? null))
  let vineKill = $state(untrack(() => planting?.vine_kill_date ?? ''))
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
  const typicalDays = $derived(plant?.has_cover_curve ? plant.season_days : (genericCurve?.season_days ?? null))
  // The planting's own season length (G.7), stretching the crop's curve; blank for the typical one
  let ownDays = $state<number | null>(untrack(() => planting?.season_days ?? null))
  const seasonDays = $derived(typicalDays ? (ownDays ?? typicalDays) : null)
  // Potatoes are vine killed some weeks before harvest, and irrigated until it
  const endLabel = $derived(plant?.has_vine_kill ? 'Harvest' : 'Harvest or kill')

  // A blank root zone follows the crop chosen; a typed one stays
  function choosePlant(id: string) {
    plantId = id
    const chosen = plants.find((p) => String(p.id) === id)
    // LAI is offered only for crops with an LAI growth curve
    if (!chosen?.has_lai_curve) etMethod = 'pct_cover'
    // A season length and a generic curve are for one crop's curve
    ownDays = null
    curveChoice = ''
    suggestEnd()
  }

  // A new planting's harvest follows the crop's typical season from emergence (PLAN.md Phase 8 G.2)
  // until a date is typed; an existing one keeps its own
  let endChosen = untrack(() => planting !== undefined)
  function suggestEnd() {
    if (!endChosen && plant && emergence) endDate = typicalEnd(seasonDays, emergence)
  }

  // Out of order dates, as they're typed (the server checks the same). A saved planting's dates
  // are held to the looser rules they were saved under until one of them changes (G.13 part 3)
  const loose = $derived(
    planting !== undefined &&
      seasonStart === planting.season_start &&
      emergence === planting.emergence_date &&
      endDate === planting.end_date,
  )
  const problems = $derived(
    dateProblems({ seasonStart, emergence, end: endDate, vineKill: plant?.has_vine_kill ? vineKill : null }, endLabel, {
      loose,
    }),
  )
  // The earliest harvest the picker offers: the day after the later of the season start and emergence
  // (the day itself under the looser rules)
  const endMin = $derived.by(() => {
    const later = [seasonStart, emergence].filter(Boolean).sort().at(-1)
    return later ? (loose ? later : addDays(later, 1)) : undefined
  })
  const datesWrong = $derived(Boolean(problems.emergence || problems.end || problems.vineKill))

  // Settings: collapsed to a line saying what's in effect; opened when one of them has an error
  let settingsOpen = $state(false)
  const SETTINGS = [
    'max_root_zone_depth',
    'mad_frac',
    'et_method',
    'canopy_curve_key',
    'canopy_interpolation',
    'target_ad_pct',
    'initial_moisture_pct',
  ]
  const settingsSummary = $derived.by(() => {
    if (!plant) return ''
    const depth = units.format('rootDepth', rootDepth ?? plant.default_max_root_zone_depth)
    const mad = `MAD ${Math.round((madFrac ?? DEFAULT_MAD) * 100)}%`
    let canopy: string
    if (etMethod === 'lai') canopy = 'leaf area index'
    else if (generic && curveKey === NONE) canopy = 'percent cover, readings only'
    else if (interpolation === 'linear') canopy = 'percent cover, straight lines between readings'
    else canopy = `percent cover, following the ${(generic ? genericCurve?.name : plant.name)?.toLowerCase()} curve`
    const target = targetAd !== null ? ` · target AD ${targetAd}%` : ''
    return `Root zone ${depth} · ${mad} · ${canopy}${target}`
  })

  let seasonSoilId = $state(untrack(() => String(planting?.soil_type_id ?? '')))
  const seasonSoil = $derived(soilTypes.find((s) => String(s.id) === seasonSoilId))

  // The error keys shown beside a control as the form is now; the server's others (and ones whose
  // control is hidden) are listed at the bottom with base, so none comes back unshown
  const shownErrorKeys = $derived.by(() => {
    const keys = ['plant']
    if (!plant) return keys
    const add = (...names: string[]) => keys.push(...names)
    add('season_start', 'emergence_date', 'end_date', 'partial', 'max_root_zone_depth', 'mad_frac', 'et_method')
    add('target_ad_pct', 'initial_moisture_pct')
    if (typicalDays) add('season_days')
    if (plant.has_vine_kill) add('vine_kill_date')
    if (generic) add('canopy_curve_key')
    if (hasCurve) add('canopy_interpolation')
    if (partial) {
      add('area_acres')
      if (sizeBy === 'plot') add('plot_length_ft', 'plot_width_ft')
      if (soilTypes.length && ownSoil) add('soil_type', 'field_capacity', 'perm_wilting_pt')
    } else if (planting?.ended && soilTypes.length) {
      add('soil_type', 'area_acres', 'field_capacity', 'perm_wilting_pt')
    }
    return keys
  })
  const firstError = (error: string | string[] | undefined) => (Array.isArray(error) ? error[0] : error)
  function otherErrors(errors: Record<string, string | string[] | undefined>): string[] {
    return Object.entries(errors)
      .filter(([key, error]) => error && !shownErrorKeys.includes(key))
      .map(([, error]) => firstError(error)!)
  }
</script>

<Form
  action={planting ? plantings.update(planting.id) : plantings.create({ query: { year } })}
  class="space-y-5"
  options={{ preserveScroll: true, preserveState: true }}
  onSuccess={ondone}
  onError={(errors) => {
    if (Object.keys(errors).some((key) => SETTINGS.includes(key))) settingsOpen = true
  }}
>
  {#snippet children({ errors, processing })}
    <input type="hidden" name="planting[field_id]" value={field.id} />
    {#snippet dateInput(
      name: string,
      label: string,
      error: string | string[] | undefined,
      value: string,
      set: (v: string) => void,
      info: FieldInfoKey | undefined,
      limits: { min?: string; max?: string; required?: boolean; optional?: boolean } = {},
    )}
      {@const message = Array.isArray(error) ? error[0] : error}
      <div class="space-y-1">
        <FieldLabel
          {label}
          {info}
          for="planting-{name}"
          missing={Boolean(limits.required ?? true) && !value}
          optional={limits.optional}
        />
        <input
          id="planting-{name}"
          type="date"
          name="planting[{name}]"
          {value}
          min={limits.min}
          max={limits.max}
          oninput={(event) => set(event.currentTarget.value)}
          required={limits.required ?? true}
          aria-invalid={message ? 'true' : undefined}
          aria-describedby={message ? `planting-${name}-error` : undefined}
          class="block w-full rounded-md text-sm {message ? 'border-status-irrigate' : ''}"
        />
        {#if message}
          <p id="planting-{name}-error" class="text-sm text-status-irrigate-ink">{message}</p>
        {/if}
      </div>
    {/snippet}
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
        info="planting.crop"
        required
      />
      <TextField
        label="Variety"
        name="planting[variety]"
        value={planting?.variety ?? ''}
        info="planting.variety"
        optional
      />
    </div>

    {#if !plant}
      <p class="text-sm text-ink-muted">Choose a crop: WISP suggests its season, root zone and canopy curve from it.</p>
    {:else}
      <section class="space-y-4" aria-labelledby="planting-season-heading">
        <h3 id="planting-season-heading" class="border-t border-line pt-4 font-display text-sm font-semibold">
          Season
        </h3>
        <div class="grid gap-4 sm:grid-cols-3">
          {@render dateInput(
            'season_start',
            'Season start',
            errors.season_start,
            seasonStart,
            (v) => (seasonStart = v),
            'planting.season_start',
          )}
          {@render dateInput(
            'emergence_date',
            'Emergence',
            problems.emergence ?? errors.emergence_date,
            emergence,
            (v) => {
              emergence = v
              suggestEnd()
            },
            'planting.emergence',
          )}
          {@render dateInput(
            'end_date',
            endLabel,
            problems.end ?? errors.end_date,
            endDate,
            (v) => {
              endDate = v
              endChosen = true
            },
            'planting.end',
            { min: endMin },
          )}
        </div>
        {#if typicalDays || plant.has_vine_kill}
          <div class="grid gap-4 sm:grid-cols-3">
            {#if typicalDays}
              <div class="sm:col-span-2" oninput={suggestEnd}>
                <NumberField
                  label="Season length"
                  name="planting[season_days]"
                  unitLabel="days"
                  bind:value={ownDays}
                  blankValue={typicalDays}
                  hint="From emergence to harvest. Blank: a typical {plant.name.toLowerCase()} season{plant.has_cover_curve
                    ? ''
                    : ` (${genericCurve?.name.toLowerCase()} curve)`}."
                  info="planting.season_length"
                  error={errors.season_days}
                  optional
                />
              </div>
            {/if}
            {#if plant.has_vine_kill}
              <div class="space-y-1">
                {@render dateInput(
                  'vine_kill_date',
                  'Vine kill',
                  problems.vineKill ?? errors.vine_kill_date,
                  vineKill,
                  (v) => (vineKill = v),
                  'planting.vine_kill',
                  { min: emergence, max: endDate, required: false, optional: true },
                )}
              </div>
            {/if}
          </div>
        {/if}
        {#if !typicalDays}<input type="hidden" name="planting[season_days]" value="" />{/if}
      </section>

      <section class="space-y-3" aria-labelledby="planting-size-heading">
        <h3 id="planting-size-heading" class="border-t border-line pt-4 font-display text-sm font-semibold">Size</h3>
        <fieldset class="space-y-3" aria-labelledby="planting-size">
          <FieldLabel as="legend" label="Planting size" labelId="planting-size" info="planting.size" />
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
          {#if errors.partial}
            <p class="text-sm text-status-irrigate-ink">{firstError(errors.partial)}</p>
          {/if}
          {#if partial}
            <div class="space-y-3 rounded-md border border-line p-3">
              <div class="flex flex-wrap gap-4 text-sm">
                <label class="flex items-center gap-2"
                  ><input type="radio" name="planting-size-by" value="acres" bind:group={sizeBy} /> Area</label
                >
                <label class="flex items-center gap-2"
                  ><input type="radio" name="planting-size-by" value="plot" bind:group={sizeBy} /> Length × width</label
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
                      hint={fieldShares ? "From the soil survey of the field's shape" : undefined}
                      error={errors.soil_type}
                    />
                    <NumberField
                      label="Field capacity"
                      name="planting[field_capacity]"
                      scale={100}
                      unitLabel="%"
                      value={planting?.own_soil ? planting.field_capacity : null}
                      blankValue={plotSoil?.field_capacity ?? null}
                      hint="Blank: the soil's"
                      info="planting.field_capacity"
                      error={errors.field_capacity}
                    />
                    <NumberField
                      label="Wilting point"
                      name="planting[perm_wilting_pt]"
                      scale={100}
                      unitLabel="%"
                      value={planting?.own_soil ? planting.perm_wilting_pt : null}
                      blankValue={plotSoil?.perm_wilting_pt ?? null}
                      hint="Blank: the soil's"
                      info="planting.wilting_point"
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
      </section>

      <!-- Kept mounted while closed, so its values are submitted -->
      <details bind:open={settingsOpen} class="group rounded-md border border-line">
        <summary class="cursor-pointer list-none px-3 py-2 text-sm">
          <span class="flex items-center justify-between gap-2">
            <span class="font-display font-semibold">Settings</span>
            <span class="text-ink-muted group-open:hidden">Change</span>
          </span>
          <span class="block text-ink-muted">{settingsSummary}</span>
        </summary>
        <div class="space-y-4 border-t border-line p-3">
          <div class="grid gap-4 sm:grid-cols-2">
            <NumberField
              label="Root zone depth"
              name="planting[max_root_zone_depth]"
              quantity="rootDepth"
              bind:value={rootDepth}
              blankValue={plant.default_max_root_zone_depth}
              submitBlankValue
              hint="Blank: typical for {plant.name.toLowerCase()}"
              info="planting.root_zone"
              error={errors.max_root_zone_depth}
            />
            <NumberField
              label="Allowable depletion fraction (MAD)"
              name="planting[mad_frac]"
              scale={100}
              unitLabel="%"
              bind:value={madFrac}
              blankValue={DEFAULT_MAD}
              submitBlankValue
              hint="Blank: 50%, right for most crops"
              info="planting.mad"
              error={errors.mad_frac}
            />
          </div>
          <fieldset class="space-y-2" aria-labelledby="planting-et-method">
            <FieldLabel as="legend" label="Canopy method" labelId="planting-et-method" info="planting.et_method" />
            <label class="flex items-start gap-3 text-sm">
              <input type="radio" name="planting[et_method]" value="pct_cover" bind:group={etMethod} class="mt-0.5" />
              <span
                >Percent cover <span class="text-ink-muted"
                  >(enter canopy cover in the daily grid about weekly until the canopy closes)</span
                ></span
              >
            </label>
            {#if plant.has_lai_curve}
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
            {#if errors.et_method}
              <p class="text-sm text-status-irrigate-ink">{firstError(errors.et_method)}</p>
            {/if}
          </fieldset>
          <!-- Blank leaves the crop's own curve or its default; a crop with its own never sends one -->
          <input type="hidden" name="planting[canopy_curve_key]" value={generic ? curveChoice : ''} />
          {#if generic}
            <fieldset class="space-y-2" aria-labelledby="planting-canopy-curve">
              <FieldLabel
                as="legend"
                label="Canopy curve"
                labelId="planting-canopy-curve"
                info="planting.canopy_curve"
              />
              <p class="text-sm text-ink-muted">WISP has no canopy curve of its own for {plant.name.toLowerCase()}.</p>
              {#each genericCurves as curve (curve.key)}
                <label class="flex items-start gap-3 text-sm">
                  <input
                    type="radio"
                    name="planting-canopy-curve"
                    checked={curveKey === curve.key}
                    onchange={() => {
                      // The default is left blank, so the crop follows it if it changes
                      curveChoice = curve.key === plant.default_generic_curve ? '' : curve.key
                      suggestEnd()
                    }}
                    class="mt-0.5"
                  />
                  <span
                    >{curve.name}{curve.key === plant.default_generic_curve ? ' (suggested)' : ''}
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
                  Irrigation scheduling works only if you enter percent cover regularly, about weekly until the canopy
                  closes. Until the first reading, WISP can't estimate this crop's water use.
                {:else}
                  An approximation for {plant.name.toLowerCase()}: your percent cover readings correct it, so enter one
                  now and then.
                {/if}
              </p>
              {#if errors.canopy_curve_key}
                <p class="text-sm text-status-irrigate-ink">{firstError(errors.canopy_curve_key)}</p>
              {/if}
            </fieldset>
          {/if}
          {#if hasCurve}
            <fieldset class="space-y-2" aria-labelledby="planting-interpolation">
              <FieldLabel
                as="legend"
                label="Between canopy readings"
                labelId="planting-interpolation"
                info="planting.interpolation"
              />
              <label class="flex items-start gap-3 text-sm">
                <input
                  type="radio"
                  name="planting[canopy_interpolation]"
                  value="curve"
                  bind:group={interpolation}
                  class="mt-0.5"
                />
                <span
                  >Follow the {generic
                    ? `${genericCurve?.name.toLowerCase()} curve`
                    : `${plant.name.toLowerCase()} curve`}
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
              {#if errors.canopy_interpolation}
                <p class="text-sm text-status-irrigate-ink">{firstError(errors.canopy_interpolation)}</p>
              {/if}
            </fieldset>
          {/if}
          <div class="grid gap-4 sm:grid-cols-2">
            <NumberField
              label="Target allowable depletion (AD)"
              name="planting[target_ad_pct]"
              unitLabel="%"
              bind:value={targetAd}
              hint="Irrigate before allowable depletion falls below this share of its maximum."
              info="planting.target_ad"
              error={errors.target_ad_pct}
              optional
            />
            <NumberField
              label="Starting soil moisture"
              name="planting[initial_moisture_pct]"
              unitLabel="%"
              value={planting?.initial_moisture_pct ?? null}
              hint="Blank: the season starts at field capacity"
              info="planting.initial_moisture"
              error={errors.initial_moisture_pct}
              optional
            />
          </div>
        </div>
      </details>

      {#if planting?.ended && soilTypes.length && !partial}
        <details class="text-sm">
          <summary class="cursor-pointer text-ink-muted">Soil and area this season</summary>
          <div class="mt-3 space-y-4">
            <p class="text-ink-muted">
              This season has ended, so it keeps the soil and area it ran with; changes to the field apply only to
              seasons that haven't ended. Correct them here for this season.
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
                blankValue={seasonSoil?.field_capacity ?? null}
                hint="Blank: {seasonSoil?.name ?? 'the soil'}'s"
                info="planting.field_capacity"
                error={errors.field_capacity}
              />
              <NumberField
                label="Wilting point"
                name="planting[perm_wilting_pt]"
                scale={100}
                unitLabel="%"
                value={planting.perm_wilting_pt}
                blankValue={seasonSoil?.perm_wilting_pt ?? null}
                hint="Blank: {seasonSoil?.name ?? 'the soil'}'s"
                info="planting.wilting_point"
                error={errors.perm_wilting_pt}
              />
            </div>
          </div>
        </details>
      {/if}

      <div class="space-y-1">
        <FieldLabel label="Notes" for="planting-notes" optional />
        <textarea id="planting-notes" name="planting[notes]" rows="2" class="block w-full rounded-md text-sm"
          >{planting?.notes ?? ''}</textarea
        >
      </div>
    {/if}
    {#each otherErrors(errors) as message, i (i)}
      <p class="text-sm text-status-irrigate-ink">{message}</p>
    {/each}
    <FormFooter {ondelete} deleteLabel="Delete this planting">
      <Button type="submit" disabled={processing || !plant || tooBig || datesWrong}
        >{planting ? 'Save planting' : 'Add planting'}</Button
      >
    </FormFooter>
  {/snippet}
</Form>
