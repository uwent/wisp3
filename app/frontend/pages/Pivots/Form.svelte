<script lang="ts">
  import { untrack } from 'svelte'
  import { Form, Link, page, router } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import FormFooter from '@/lib/components/FormFooter.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import PivotShapeFields from '@/lib/components/PivotShapeFields.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import {
    draftShape,
    isPoint,
    KIND_NAMES,
    KIND_NOUNS,
    type PivotKind,
    type PivotShape,
    shapeDraft,
    systemName,
  } from '@/lib/geo'
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

  // The kind as saved, for the title; the kind being chosen, for the words below it
  const title = $derived(
    editing
      ? `Edit ${systemName({ name: pivot.name ?? '', kind_name: KIND_NAMES[pivot.kind ?? 'center'] })}`
      : 'Add an irrigation system',
  )
  const noun = $derived(KIND_NOUNS[shape.kind])

  // Only owners delete (Q8); the system's fields and their seasons go with it
  function destroy() {
    const name = systemName({ name: pivot.name ?? '', kind_name: KIND_NAMES[pivot.kind ?? 'center'] })
    if (!confirm(`Delete ${name} and its fields? This can't be undone.`)) return
    saved = true
    router.delete(pivots.destroy(pivot.id!).url)
  }
  const EQUIPMENT_EXAMPLES: Record<PivotKind, string> = {
    center: 'e.g. Valley 8000, end gun',
    linear: 'e.g. Zimmatic 9500L, hose drag',
    traveler: 'e.g. Hard hose reel #2',
    solid_set: 'e.g. Impact sprinklers, 40 × 40 ft',
    drip: 'e.g. 15 mil tape, 12 in emitters',
    point: '',
  }
</script>

<svelte:head><title>{title} · WISP</title></svelte:head>

<div>
  <Link href={setup.show()} class="text-sm text-brand-600 hover:underline">← Setup</Link>
  <h1 class="text-2xl font-semibold">{title}</h1>
  <p class="text-sm text-ink-muted">
    Weather comes from its location. {editing
      ? `If you move the ${noun}, WISP gets weather for its new location.`
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
            hint="A farm groups irrigation systems you want to view and manage together"
            error={errors.farm}
          />
        </div>
        <PivotShapeFields
          bind:shape
          prefix="pivot"
          error={(attribute) => errors[attribute]}
          others={other_pivots}
          soilTypes={soil_types}
          surveyLevel="h2"
        />
      </section>

      <section class="grid gap-4 rounded-lg border border-line bg-surface-raised p-6 sm:grid-cols-2">
        <NumberField
          label={isPoint(shape.kind) ? 'Flow' : 'Pump capacity'}
          name="pivot[pump_capacity_gpm]"
          quantity="flow"
          value={pivot.pump_capacity_gpm ?? null}
          hint="With it, you can enter irrigation as hours the {noun} ran."
          error={errors.pump_capacity_gpm}
        />
        <TextField
          label="Equipment"
          name="pivot[equipment]"
          value={pivot.equipment ?? ''}
          placeholder={EQUIPMENT_EXAMPLES[shape.kind]}
          hint={shape.kind === 'traveler' ? 'The machine, named the same at each field it waters' : undefined}
        />
        <div class="space-y-1 sm:col-span-2">
          <label for="pivot-notes" class="block text-sm font-medium">Notes</label>
          <textarea id="pivot-notes" name="pivot[notes]" rows="2" class="block w-full rounded-md text-sm"
            >{pivot.notes ?? ''}</textarea
          >
        </div>
      </section>

      <FormFooter
        ondelete={editing && page.props.auth.owner ? destroy : undefined}
        deleteLabel="Delete this {KIND_NOUNS[pivot.kind ?? 'center']}"
      >
        <Button type="submit" disabled={processing}>{editing ? 'Save' : 'Add irrigation system'}</Button>
      </FormFooter>
    </div>
  {/snippet}
</Form>
