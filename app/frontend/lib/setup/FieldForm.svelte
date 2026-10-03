<script lang="ts">
  import { untrack } from 'svelte'
  import { Form } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { fields } from '@/routes'
  import type { Field, SoilType } from '@/types/serializers'

  // Create a field under a pivot, or edit one (including moving it to another pivot)
  let {
    field,
    pivotId,
    pivots,
    soilTypes,
    ondone,
  }: {
    field?: Field
    pivotId: number
    pivots: { id: number; name: string }[]
    soilTypes: SoilType[]
    ondone: () => void
  } = $props()

  // Form fields start from the props; the dialog mounts a new form each time it opens
  let soilTypeId = $state(
    untrack(() => String(field?.soil_type_id ?? soilTypes.find((s) => s.key === 'sandy_loam')?.id ?? soilTypes[0]?.id)),
  )
  const soil = $derived(soilTypes.find((s) => String(s.id) === soilTypeId))
  const pct = (fraction: number | undefined) => (fraction === undefined ? '' : `${Math.round(fraction * 1000) / 10}%`)
</script>

<Form
  action={field ? fields.update(field.id) : fields.create()}
  class="space-y-4"
  options={{ preserveScroll: true, preserveState: true }}
  onSuccess={ondone}
>
  {#snippet children({ errors, processing })}
    <TextField label="Name" name="field[name]" value={field?.name ?? ''} error={errors.name} required />
    <div class="grid gap-4 sm:grid-cols-2">
      <SelectField label="Pivot" name="field[pivot_id]" value={String(field?.pivot_id ?? pivotId)} options={pivots.map((p) => ({ value: String(p.id), label: p.name }))} />
      <NumberField label="Area" name="field[area_acres]" quantity="area" value={field?.area_acres ?? null} error={errors.area_acres} />
    </div>
    <SelectField
      label="Soil"
      name="field[soil_type_id]"
      bind:value={soilTypeId}
      options={soilTypes.map((s) => ({ value: String(s.id), label: s.name }))}
      error={errors.soil_type}
    />
    <details class="text-sm" open={field?.field_capacity !== null && field?.field_capacity !== undefined}>
      <summary class="cursor-pointer text-ink-muted">Override the soil's water-holding values</summary>
      <div class="mt-3 grid gap-4 sm:grid-cols-2">
        <NumberField
          label="Field capacity"
          name="field[field_capacity]"
          scale={100}
          unitLabel="%"
          value={field?.field_capacity ?? null}
          hint="Blank uses {soil?.name ?? 'the soil'}: {pct(soil?.field_capacity)}"
          error={errors.field_capacity}
        />
        <NumberField
          label="Wilting point"
          name="field[perm_wilting_pt]"
          scale={100}
          unitLabel="%"
          value={field?.perm_wilting_pt ?? null}
          hint="Blank uses {soil?.name ?? 'the soil'}: {pct(soil?.perm_wilting_pt)}"
          error={errors.perm_wilting_pt}
        />
      </div>
    </details>
    <div class="space-y-1">
      <label for="field-notes" class="block text-sm font-medium">Notes</label>
      <textarea id="field-notes" name="field[notes]" rows="2" class="block w-full rounded-md text-sm">{field?.notes ?? ''}</textarea>
    </div>
    <Button type="submit" disabled={processing}>{field ? 'Save field' : 'Add field'}</Button>
  {/snippet}
</Form>
