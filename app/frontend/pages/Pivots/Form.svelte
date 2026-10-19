<script lang="ts">
  import { untrack } from 'svelte'
  import { Form, Link } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import PivotShapeFields from '@/lib/components/PivotShapeFields.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { draftShape, type PivotShape, shapeDraft } from '@/lib/geo'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { pivots, setup } from '@/routes'
  import type { Pivot, SoilType } from '@/types/serializers'

  type Outline = PivotShape & Pick<Pivot, 'id' | 'name'>

  let {
    pivot,
    farms,
    other_pivots,
    soil_types,
  }: {
    pivot: Partial<Omit<Pivot, 'fields'>>
    farms: { id: number; name: string }[]
    other_pivots: Outline[]
    soil_types: SoilType[]
  } = $props()

  const editing = $derived(pivot.id !== undefined)

  // The map and the inputs edit the same values
  let shape = $state(untrack(() => shapeDraft(pivot)))

  // Unsaved changes: anything typed in the form, or the pivot moved or resized on the map
  const initial = untrack(() => JSON.stringify(draftShape(shape)))
  let edited = $state(false)
  let saved = $state(false)
  const moved = $derived(JSON.stringify(draftShape(shape)) !== initial)
  confirmUnsavedChanges(() => !saved && (edited || moved))
</script>

<svelte:head><title>{editing ? `Edit ${pivot.name}` : 'Add a pivot'} · WISP</title></svelte:head>

<div>
  <Link href={setup.show()} class="text-sm text-brand-600 hover:underline">← Setup</Link>
  <h1 class="text-2xl font-semibold">{editing ? `Edit ${pivot.name}` : 'Add a pivot'}</h1>
  <p class="text-sm text-ink-muted">
    Weather comes from the pivot's location. {editing
      ? 'Moving a pivot refetches its weather.'
      : 'You can move it or change any of this after it’s created.'}
  </p>
</div>

<Form action={editing ? pivots.update(pivot.id!) : pivots.create()} class="space-y-6" onSuccess={() => (saved = true)}>
  {#snippet children({ errors, processing })}
    <div class="space-y-6" oninput={() => (edited = true)} onchange={() => (edited = true)}>
      <section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
        <div class="grid gap-4 sm:grid-cols-2">
          <TextField label="Name" name="pivot[name]" value={pivot.name ?? ''} error={errors.name} required />
          <SelectField
            label="Farm"
            name="pivot[farm_id]"
            value={String(pivot.farm_id ?? farms[0]?.id ?? '')}
            options={farms.map((farm) => ({ value: String(farm.id), label: farm.name }))}
            hint="A farm groups pivots you want to view and manage together"
            error={errors.farm}
          />
        </div>
        <PivotShapeFields
          bind:shape
          prefix="pivot"
          error={(attribute) => errors[attribute]}
          others={other_pivots}
          soilTypes={soil_types}
        />
      </section>

      <section class="grid gap-4 rounded-lg border border-line bg-surface-raised p-6 sm:grid-cols-2">
        <NumberField
          label="Pump capacity"
          name="pivot[pump_capacity_gpm]"
          quantity="flow"
          value={pivot.pump_capacity_gpm ?? null}
          hint="Lets you enter irrigation as run hours"
          error={errors.pump_capacity_gpm}
        />
        <TextField
          label="Equipment"
          name="pivot[equipment]"
          value={pivot.equipment ?? ''}
          placeholder="e.g. Valley 8000, end gun"
        />
        <div class="space-y-1 sm:col-span-2">
          <label for="pivot-notes" class="block text-sm font-medium">Notes</label>
          <textarea id="pivot-notes" name="pivot[notes]" rows="2" class="block w-full rounded-md text-sm"
            >{pivot.notes ?? ''}</textarea
          >
        </div>
      </section>

      <Button type="submit" disabled={processing}>{editing ? 'Save pivot' : 'Add pivot'}</Button>
    </div>
  {/snippet}
</Form>
