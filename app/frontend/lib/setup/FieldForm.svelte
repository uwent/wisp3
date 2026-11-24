<script lang="ts">
  import { untrack } from 'svelte'
  import { systemName } from '@/lib/geo'
  import { boundaryAcres } from '@/lib/boundary'
  import { Form, Link, page } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import FormFooter from '@/lib/components/FormFooter.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import type { SystemShape } from '@/lib/geo'
  import { systemDistanceM, systemReach } from '@/lib/outlines/problems'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { fieldOutline, fields } from '@/routes'
  import type { Field, IrrigationSystem, SoilType } from '@/types/serializers'

  import FieldLabel from '@/lib/components/FieldLabel.svelte'

  import FieldAreaInput from './FieldAreaInput.svelte'
  import FieldSoilInput from './FieldSoilInput.svelte'
  import ShapeThumbnail from './ShapeThumbnail.svelte'
  import { lastSoil, rememberSoil } from './lastChoices'

  // Create a field under a system, or edit one (including moving it to another system, which its
  // seasons that haven't ended follow; ended ones keep theirs).
  // Its shape (the outline) is shown small and edited on its own page.
  let {
    field,
    systemId,
    systems,
    soilTypes,
    ondone,
    ondelete,
  }: {
    field?: Field
    systemId: number
    /** With their location, a new field gets the soil survey's suggestion for its system */
    systems: (Pick<IrrigationSystem, 'id' | 'name'> &
      Partial<Pick<IrrigationSystem, 'kind_name'>> &
      Partial<SystemShape>)[]
    soilTypes: SoilType[]
    ondone: () => void
    /** Deletes the field (asking first); left out for a new field or someone who isn't an owner */
    ondelete?: () => void
  } = $props()

  // Leaving (for the outline page, say) loses what's typed here, so ask first
  let edited = $state(false)
  let inputs = $state<HTMLElement>()
  confirmUnsavedChanges(
    () => edited,
    () => inputs,
  )

  // Form fields start from the props; the dialog mounts a new form each time it opens. A new field
  // starts on the soil last saved in this session (lib/setup/lastChoices.ts), until the survey suggests one
  let soilTypeId = $state(
    untrack(() =>
      String(
        field?.soil_type_id ??
          soilTypes.find((s) => s.id === lastSoil())?.id ??
          soilTypes.find((s) => s.key === 'sandy_loam')?.id ??
          soilTypes[0]?.id,
      ),
    ),
  )
  const soil = $derived(soilTypes.find((s) => String(s.id) === soilTypeId))

  // The soil survey reads the field's shape, or for a new field its system's, whose suggestion it
  // takes until the user picks a soil
  let systemChoice = $state(untrack(() => String(field?.system_id ?? systemId)))
  const system = $derived(systems.find((p) => String(p.id) === systemChoice))
  const surveyPoint = $derived(
    !field && system?.latitude != null && system.longitude != null
      ? ({ kind: 'center', ...system } as SystemShape & { name: string })
      : null,
  )
  // With a shape, each system says how far it is from the field (as on the shape page): the field's
  // own first, then the nearest
  const shaped = (p: (typeof systems)[number]): p is (typeof systems)[number] & SystemShape =>
    p.latitude != null && p.longitude != null && p.kind != null
  const systemOptions = $derived.by(() => {
    const boundary = field?.boundary
    const unitSystem = page.props.auth.user?.unit_system ?? 'imperial'
    const options = systems.map((p) => {
      const meters = boundary && shaped(p) ? systemDistanceM(boundary, p) : null
      const name = p.kind_name ? systemName({ name: p.name, kind_name: p.kind_name }) : p.name
      return {
        value: String(p.id),
        label: meters === null ? name : `${name} – ${systemReach(p as SystemShape, meters, unitSystem)}`,
        own: p.id === field?.system_id,
        meters,
      }
    })
    if (!boundary) return options
    return options.toSorted((a, b) => Number(b.own) - Number(a.own) || (a.meters ?? Infinity) - (b.meters ?? Infinity))
  })
  let area = $state(untrack(() => field?.area_acres ?? null))

  // Field capacity and wilting point: the soil's unless measured, collapsed to a line saying what's in
  // effect (as the planting form's Settings) and opened by an error in either
  let fieldCapacity = $state(untrack(() => field?.field_capacity ?? null))
  let wiltingPoint = $state(untrack(() => field?.perm_wilting_pt ?? null))
  let soilWaterOpen = $state(false)
  const percent = (fraction: number | null | undefined) =>
    fraction === null || fraction === undefined ? '–' : `${Number((fraction * 100).toFixed(1))}%`
  const soilWaterSummary = $derived.by(() => {
    const own = (value: number | null) => (value === null ? '' : ' (yours)')
    const values = `Field capacity ${percent(fieldCapacity ?? soil?.field_capacity)}${own(fieldCapacity)} · wilting point ${percent(wiltingPoint ?? soil?.perm_wilting_pt)}${own(wiltingPoint)}`
    return fieldCapacity === null && wiltingPoint === null && soil
      ? `${values}, from ${soil.name.toLowerCase()}`
      : values
  })
  // Seasons that have ended keep their soil, area and irrigation system
  const endedYears = $derived(field?.ended_years ?? [])
  const endedText = $derived(
    endedYears.length === 1 ? `The ${endedYears[0]} season` : `Earlier seasons (${endedYears.join(', ')})`,
  )
</script>

<Form
  action={field ? fields.update(field.id) : fields.create()}
  class="space-y-4"
  options={{ preserveScroll: true, preserveState: true }}
  onSuccess={() => {
    if (soil) rememberSoil(soil.id)
    ondone()
  }}
  onError={(errors) => {
    if (errors.field_capacity || errors.perm_wilting_pt) soilWaterOpen = true
  }}
>
  {#snippet children({ errors, processing })}
    <div bind:this={inputs} class="space-y-4" oninput={() => (edited = true)} onchange={() => (edited = true)}>
      <TextField label="Name" name="field[name]" value={field?.name ?? ''} error={errors.name} required />
      <SelectField
        label="Irrigation system"
        name="field[system_id]"
        bind:value={systemChoice}
        options={systemOptions.map(({ value, label }) => ({ value, label }))}
        info="field.system"
        error={errors.system_id}
        required
      />
      <fieldset class="space-y-2">
        <legend class="text-sm font-medium">Area and shape</legend>
        <div class="grid gap-4 sm:grid-cols-2">
          <FieldAreaInput
            name="field[area_acres]"
            bind:value={area}
            saved={field ? field.area_acres : undefined}
            drawn={field?.boundary ? boundaryAcres(field.boundary) : null}
            error={errors.area_acres}
            info="field.area"
            onchange={() => (edited = true)}
          />
          <div class="space-y-1">
            <FieldLabel as="span" label="Shape" labelId="field-shape" info="field.shape" />
            <div class="flex items-center gap-3 text-sm">
              {#if field?.boundary}
                <ShapeThumbnail boundary={field.boundary} label="The shape of {field.name}" />
              {:else}
                <span class="text-ink-muted">None</span>
              {/if}
              {#if field}
                <Link
                  href={fieldOutline(field.id, { query: { from: 'setup' } })}
                  class="text-brand-600 underline underline-offset-2"
                  aria-describedby="field-shape"
                >
                  {field.boundary ? 'Edit shape' : 'Add a shape'}
                </Link>
              {:else}
                <span class="text-xs text-ink-muted">Add one once the field is saved</span>
              {/if}
            </div>
          </div>
        </div>
      </fieldset>
      <FieldSoilInput
        name="field[soil_type_id]"
        bind:value={soilTypeId}
        {soilTypes}
        saved={field ? field.soil_type_id : undefined}
        boundary={field?.boundary ?? null}
        system={surveyPoint}
        suggest={!field}
        error={errors.soil_type}
        info="field.soil"
        onchange={() => (edited = true)}
      />
      {#if endedYears.length}
        <p class="text-sm text-ink-muted">
          Changes to the soil, area and irrigation system apply to seasons that haven't ended. {endedText}
          {endedYears.length === 1
            ? 'keeps the soil, area and system it ran with'
            : 'keep the soil, area and system they ran with'}; to correct a soil or area, edit that season's crop.
        </p>
      {/if}
      <!-- Kept mounted while closed, so its values are submitted -->
      <details bind:open={soilWaterOpen} class="group rounded-md border border-line">
        <summary class="cursor-pointer list-none px-3 py-2 text-sm">
          <span class="flex items-center justify-between gap-2">
            <span class="font-display font-semibold">Soil water</span>
            <span class="text-ink-muted group-open:hidden">Change</span>
          </span>
          <span class="block text-ink-muted">{soilWaterSummary}</span>
        </summary>
        <div class="grid gap-4 border-t border-line p-3 sm:grid-cols-2">
          <NumberField
            label="Field capacity"
            name="field[field_capacity]"
            scale={100}
            unitLabel="%"
            bind:value={fieldCapacity}
            blankValue={soil?.field_capacity ?? null}
            hint="Blank: {soil?.name ?? 'the soil'}'s"
            info="field.field_capacity"
            error={errors.field_capacity}
          />
          <NumberField
            label="Wilting point"
            name="field[perm_wilting_pt]"
            scale={100}
            unitLabel="%"
            bind:value={wiltingPoint}
            blankValue={soil?.perm_wilting_pt ?? null}
            hint="Blank: {soil?.name ?? 'the soil'}'s"
            info="field.wilting_point"
            error={errors.perm_wilting_pt}
          />
        </div>
      </details>
      <div class="space-y-1">
        <FieldLabel label="Notes" for="field-notes" optional />
        <textarea id="field-notes" name="field[notes]" rows="2" class="block w-full rounded-md text-sm"
          >{field?.notes ?? ''}</textarea
        >
      </div>
    </div>
    <FormFooter {ondelete} deleteLabel="Delete this field">
      <Button type="submit" disabled={processing}>{field ? 'Save field' : 'Add field'}</Button>
    </FormFooter>
  {/snippet}
</Form>
