<script lang="ts">
  import { untrack } from 'svelte'
  import { boundaryAcres, systemName } from '@/lib/geo'
  import { Form, Link } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import FormFooter from '@/lib/components/FormFooter.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import type { PivotShape } from '@/lib/geo'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { fieldOutline, fields } from '@/routes'
  import type { Field, Pivot, SoilType } from '@/types/serializers'

  import FieldAreaInput from './FieldAreaInput.svelte'
  import FieldSoilInput from './FieldSoilInput.svelte'
  import ShapeThumbnail from './ShapeThumbnail.svelte'

  // Create a field under a pivot, or edit one (including moving it to another pivot, which its
  // seasons that haven't ended follow; ended ones keep theirs, PLAN.md Phase 8 G.9, G.14 part 7).
  // Its shape (the outline, G.10) is shown small and edited on its own page (G.14).
  let {
    field,
    pivotId,
    pivots,
    soilTypes,
    ondone,
    ondelete,
  }: {
    field?: Field
    pivotId: number
    /** With their location, a new field gets the soil survey's suggestion for its pivot */
    pivots: (Pick<Pivot, 'id' | 'name'> & Partial<Pick<Pivot, 'kind_name'>> & Partial<PivotShape>)[]
    soilTypes: SoilType[]
    ondone: () => void
    /** Deletes the field (asking first); left out for a new field or someone who isn't an owner */
    ondelete?: () => void
  } = $props()

  // Leaving (for the outline page, say) loses what's typed here, so ask first
  let edited = $state(false)
  confirmUnsavedChanges(() => edited)

  // Form fields start from the props; the dialog mounts a new form each time it opens
  let soilTypeId = $state(
    untrack(() => String(field?.soil_type_id ?? soilTypes.find((s) => s.key === 'sandy_loam')?.id ?? soilTypes[0]?.id)),
  )
  const soil = $derived(soilTypes.find((s) => String(s.id) === soilTypeId))

  // The soil survey reads the field's shape, or for a new field its pivot's, whose suggestion it
  // takes until the user picks a soil (G.6)
  let pivotChoice = $state(untrack(() => String(field?.pivot_id ?? pivotId)))
  const pivot = $derived(pivots.find((p) => String(p.id) === pivotChoice))
  const system = $derived(
    !field && pivot?.latitude != null && pivot.longitude != null
      ? ({ kind: 'center', ...pivot } as PivotShape & { name: string })
      : null,
  )
  let area = $state(untrack(() => field?.area_acres ?? null))
  // Seasons that have ended keep their soil, area and irrigation system
  const endedYears = $derived(field?.ended_years ?? [])
  const endedText = $derived(
    endedYears.length === 1 ? `The ${endedYears[0]} season` : `Earlier seasons (${endedYears.join(', ')})`,
  )
  const pct = (fraction: number | undefined) => (fraction === undefined ? '' : `${Math.round(fraction * 1000) / 10}%`)
</script>

<Form
  action={field ? fields.update(field.id) : fields.create()}
  class="space-y-4"
  options={{ preserveScroll: true, preserveState: true }}
  onSuccess={ondone}
>
  {#snippet children({ errors, processing })}
    <div class="space-y-4" oninput={() => (edited = true)} onchange={() => (edited = true)}>
      <TextField label="Name" name="field[name]" value={field?.name ?? ''} error={errors.name} required />
      <SelectField
        label="Irrigation system"
        name="field[pivot_id]"
        bind:value={pivotChoice}
        options={pivots.map((p) => ({
          value: String(p.id),
          label: p.kind_name ? systemName({ name: p.name, kind_name: p.kind_name }) : p.name,
        }))}
        error={errors.pivot_id}
      />
      <fieldset class="space-y-2">
        <legend class="text-sm font-medium">Field area</legend>
        <div class="grid gap-4 sm:grid-cols-2">
          <FieldAreaInput
            name="field[area_acres]"
            bind:value={area}
            saved={field ? field.area_acres : undefined}
            drawn={field?.boundary ? boundaryAcres(field.boundary) : null}
            error={errors.area_acres}
            onchange={() => (edited = true)}
          />
          <div class="space-y-1">
            <p class="text-sm font-medium" id="field-shape">Shape</p>
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
                  aria-describedby="field-shape">{field.boundary ? 'Edit shape' : 'Add a shape'}</Link
                >
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
        {system}
        suggest={!field}
        error={errors.soil_type}
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
      <details class="text-sm" open={field?.field_capacity !== null && field?.field_capacity !== undefined}>
        <summary class="cursor-pointer text-ink-muted">Use your own field capacity and wilting point</summary>
        <div class="mt-3 grid gap-4 sm:grid-cols-2">
          <NumberField
            label="Field capacity"
            name="field[field_capacity]"
            scale={100}
            unitLabel="%"
            value={field?.field_capacity ?? null}
            hint="Leave blank to use {soil?.name ?? 'the soil'} ({pct(soil?.field_capacity)})"
            error={errors.field_capacity}
          />
          <NumberField
            label="Wilting point"
            name="field[perm_wilting_pt]"
            scale={100}
            unitLabel="%"
            value={field?.perm_wilting_pt ?? null}
            hint="Leave blank to use {soil?.name ?? 'the soil'} ({pct(soil?.perm_wilting_pt)})"
            error={errors.perm_wilting_pt}
          />
        </div>
      </details>
      <div class="space-y-1">
        <label for="field-notes" class="block text-sm font-medium">Notes</label>
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
