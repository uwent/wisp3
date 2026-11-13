<script lang="ts">
  import { tick, untrack } from 'svelte'
  import { Form, page } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import PivotShapeFields from '@/lib/components/PivotShapeFields.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import {
    isPoint,
    KIND_NOUNS,
    MAX_LATITUDE,
    MAX_LINEAR_LENGTH_FT,
    MAX_LINEAR_TRAVEL_FT,
    MAX_LONGITUDE,
    MAX_RADIUS_FT,
    MIN_LATITUDE,
    MIN_LONGITUDE,
    shapeDraft,
  } from '@/lib/geo'
  import { soilFit, soilOptionsByShare } from '@/lib/soils'
  import { units as unitsFor } from '@/lib/units'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { quickSetups } from '@/routes'
  import type { SoilType } from '@/types/serializers'

  // The guided first-run setup (PLAN.md G.6): a farm, an irrigation system and the fields it waters.
  // The system and the fields can each be left for later; plantings come next, in Setup.
  let {
    farms,
    soil_types,
    default_soil_type_id,
  }: {
    farms: { id: number; name: string }[]
    soil_types: SoilType[]
    default_soil_type_id: number | null
  } = $props()

  let farmId = $state<string>(untrack(() => (farms[0] ? String(farms[0].id) : '')))
  let shape = $state(shapeDraft())
  // "pivot", "drip block"
  const noun = $derived(KIND_NOUNS[shape.kind])
  // Steps left for later: their inputs aren't sent. Only a new farm can be saved alone.
  let systemChosenLater = $state(false)
  const systemLater = $derived(systemChosenLater && !farmId)
  let fieldsLater = $state(false)

  // A field's soil follows the soil survey's suggestion until the user picks one
  let suggestedSoilId = $state<number | null>(null)
  // Each soil type's share under the system, once the survey answers (G.6)
  let surveyShares = $state<Map<string, number> | null>(null)
  const shares = $derived(shape.latitude !== null ? surveyShares : null)
  const surveyed = $derived(isPoint(shape.kind) ? `the area around the ${noun}` : `the ${noun}`)
  const near = $derived(isPoint(shape.kind) ? `around the ${noun}` : `under the ${noun}`)
  const fit = (soilTypeId: string) => {
    const soil = soil_types.find((s) => String(s.id) === soilTypeId)
    return soil && shares ? soilFit(soil, shares, soil_types, near) : null
  }
  const defaultSoilId = () => String(suggestedSoilId ?? default_soil_type_id ?? soil_types[0]?.id ?? '')
  let nextKey = 1
  const newRow = () => ({
    key: nextKey++,
    name: '',
    area: null as number | null,
    soilTypeId: defaultSoilId(),
    soilChosen: false,
  })
  let rows = $state([newRow()])
  const soilOptions = $derived(
    shares
      ? soilOptionsByShare(soil_types, shares, surveyed)
      : soil_types.map((s) => ({ value: String(s.id), label: s.name })),
  )

  function suggestSoil(soil: SoilType | null, found: Map<string, number>) {
    suggestedSoilId = soil?.id ?? null
    surveyShares = found
    for (const row of rows) if (!row.soilChosen) row.soilTypeId = defaultSoilId()
  }

  // Ask before leaving with anything entered
  let edited = $state(false)
  let saved = $state(false)
  confirmUnsavedChanges(() => !saved && (edited || shape.latitude !== null))

  // What the server would reject, checked here so the save waits until it's all in (the server
  // still checks everything). Ranges mirror Pivot's, through lib/geo.ts.
  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  let farmName = $state('')
  let systemName = $state('')
  const within = (value: number | null, min: number, max: number) => value !== null && value >= min && value <= max
  const size = (value: number | null, max: number) => value !== null && value > 0 && value <= max
  const upTo = (max: number) => `up to ${units.format('distance', max)}`
  const missing = $derived.by(() => {
    const needs: string[] = []
    if (!farmId && !farmName.trim()) needs.push('a farm name')
    if (systemLater) return needs
    if (!systemName.trim()) needs.push(`the ${noun}'s name`)
    if (shape.latitude === null || shape.longitude === null) needs.push(`its location (click the map)`)
    else if (
      !within(shape.latitude, MIN_LATITUDE, MAX_LATITUDE) ||
      !within(shape.longitude, MIN_LONGITUDE, MAX_LONGITUDE)
    )
      needs.push('a location in the US or Canada')
    else if (shape.kind === 'center') {
      if (!size(shape.radiusFt, MAX_RADIUS_FT)) needs.push(`a radius ${upTo(MAX_RADIUS_FT)}`)
      if (shape.partial && (!within(shape.arcStart, 0, 360) || !within(shape.arcEnd, 0, 360)))
        needs.push('where the arc starts and ends (0° to 360°)')
    } else if (shape.kind === 'linear') {
      if (!size(shape.lengthFt, MAX_LINEAR_LENGTH_FT)) needs.push(`a machine length ${upTo(MAX_LINEAR_LENGTH_FT)}`)
      if (!size(shape.travelFt, MAX_LINEAR_TRAVEL_FT)) needs.push(`a travel distance ${upTo(MAX_LINEAR_TRAVEL_FT)}`)
      if (!within(shape.travelBearing, 0, 179) || !Number.isInteger(shape.travelBearing))
        needs.push('a direction of travel, a whole number from 0° to 179°')
    }
    if (!fieldsLater && rows.some((row) => !row.name.trim() && row.area !== null)) needs.push('a name for each field')
    return needs
  })
  const listed = (items: string[]) =>
    items.length < 2 ? items.join('') : `${items.slice(0, -1).join(', ')} and ${items.at(-1)}`

  // When the server finds a problem, stay put and go to the first input it marked
  async function focusFirstError() {
    await tick()
    const invalid = document.querySelector<HTMLElement>('main [aria-invalid="true"]')
    invalid?.scrollIntoView({ block: 'center' })
    invalid?.focus({ preventScroll: true })
  }

  const submitLabel = $derived(systemLater ? 'Save the farm' : 'Save and continue')
  const error = (errors: Record<string, string | string[]>, key: string) => errors[key]
</script>

<svelte:head><title>Get started · WISP</title></svelte:head>

<div>
  <h1 class="text-2xl font-semibold">{farms.length ? 'Set up an irrigation system' : 'Set up your farm'}</h1>
  <p class="max-w-3xl text-sm text-ink-muted">
    A farm, the irrigation system that waters it, and that system's fields. After saving, you'll add what's planted on
    each field this season, and WISP starts tracking its soil water. You can change any of this later in Setup.
  </p>
</div>

<Form
  action={quickSetups.create()}
  class="space-y-6"
  options={{ preserveScroll: 'errors' }}
  onBefore={() => missing.length === 0}
  onError={focusFirstError}
  onSuccess={() => (saved = true)}
>
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
            bind:value={farmName}
            placeholder="e.g. Hancock Sands"
            error={error(e, 'farm.name')}
          />
        {/if}
      </section>

      <section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
        <div>
          <h2 class="text-lg font-medium">2. Irrigation system</h2>
          <p class="text-sm text-ink-muted">
            Farms need one or more irrigation systems for WISP to work. Each system can water one or more fields, which
            you add in step 3. WISP gets weather for each system's location, so place it where it really is.
          </p>
        </div>
        {#if systemLater}
          <p class="text-sm">
            You'll add irrigation systems in Setup. Until a farm has one, WISP has no weather or schedule for it.
            <button
              type="button"
              class="text-brand-600 underline underline-offset-2"
              onclick={() => (systemChosenLater = false)}>Set one up now</button
            >
          </p>
        {:else}
          {#if !farmId}
            <p class="text-sm">
              If you don't have time right now, you can <button
                type="button"
                class="text-brand-600 underline underline-offset-2"
                onclick={() => (systemChosenLater = true)}>set up an irrigation system later</button
              >.
            </p>
          {/if}
          <TextField
            label="Name"
            name="setup[pivot][name]"
            bind:value={systemName}
            placeholder={shape.kind === 'center' ? 'e.g. North 160' : 'e.g. Home garden'}
            error={error(e, 'pivot.name')}
          />
          <PivotShapeFields
            bind:shape
            prefix="setup[pivot]"
            error={(attribute) => error(e, `pivot.${attribute}`)}
            soilTypes={soil_types}
            onsuggest={suggestSoil}
            surveyNote="What the USDA soil survey says is under the {noun}, which sets the soil suggested for its fields in step 3. You'll see it again when you add more systems or fields in Setup."
          >
            <NumberField
              label={isPoint(shape.kind) ? 'Flow' : 'Pump capacity'}
              name="setup[pivot][pump_capacity_gpm]"
              quantity="flow"
              value={null}
              hint="Optional. With it, you can enter irrigation as hours the {noun} ran."
              error={error(e, 'pivot.pump_capacity_gpm')}
            />
          </PivotShapeFields>
        {/if}
      </section>

      {#if !systemLater}
        <section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
          <div>
            <h2 class="text-lg font-medium">3. Fields</h2>
            <p class="text-sm text-ink-muted">
              Add each field this {noun} waters; a pivot split between two fields you manage separately is two fields. A field
              is the land: after saving, you'll add what's planted on each one this season. You can draw each field's outline
              on the map later, or import outlines from a shapefile, KML or GeoJSON file.
            </p>
          </div>
          {#if fieldsLater}
            <p class="text-sm">
              You'll add fields in Setup, by hand or by importing their outlines.
              <button
                type="button"
                class="text-brand-600 underline underline-offset-2"
                onclick={() => (fieldsLater = false)}>Add them now</button
              >
            </p>
          {:else}
            <p class="text-sm">
              If you don't have time right now, you can <button
                type="button"
                class="text-brand-600 underline underline-offset-2"
                onclick={() => (fieldsLater = true)}>set up fields later</button
              >.
            </p>
            {#if error(e, 'fields')}<p class="text-sm text-status-irrigate-ink">{error(e, 'fields')}</p>{/if}
            {#each rows as row, i (row.key)}
              <fieldset
                class="grid gap-3 border-t border-line pt-4 first-of-type:border-0 first-of-type:pt-0 sm:grid-cols-4"
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
                  note={fit(row.soilTypeId) ? soilNote : undefined}
                />
                {#snippet soilNote()}
                  {@const { note, main, absent } = fit(row.soilTypeId)!}
                  <p class={absent ? 'text-status-caution-ink' : 'text-ink-muted'}>{note}</p>
                  {#if main}<button
                      type="button"
                      class="mt-0.5 block text-brand-600 underline underline-offset-2"
                      onclick={() => ((row.soilTypeId = String(main.id)), (row.soilChosen = true))}
                      >Use {main.name}</button
                    >{/if}
                {/snippet}
                {#if rows.length > 1}
                  <div class="sm:col-span-4">
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
          {/if}
        </section>
      {/if}

      <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
        <Button
          type="submit"
          disabled={processing || missing.length > 0}
          aria-describedby={missing.length ? 'still-needed' : undefined}>{submitLabel}</Button
        >
        {#if missing.length}
          <p id="still-needed" class="text-sm text-ink-muted" aria-live="polite">
            {`Still needed: ${listed(missing)}.`}
          </p>
        {:else if Object.keys(e).length}
          <p class="text-sm text-status-irrigate-ink">Please correct the highlighted entries.</p>
        {/if}
      </div>
    </div>
  {/snippet}
</Form>
