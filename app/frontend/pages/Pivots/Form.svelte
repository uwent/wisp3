<script lang="ts">
  import { untrack } from 'svelte'
  import { Form, Link, page } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import PivotMap from '@/lib/components/PivotMap.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { DEFAULT_RADIUS_FT, pivotAcres } from '@/lib/geo'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { units as unitsFor } from '@/lib/units'
  import { pivots, setup } from '@/routes'
  import type { Pivot } from '@/types/serializers'

  type Outline = Pick<Pivot, 'id' | 'name' | 'latitude' | 'longitude' | 'radius_ft' | 'arc_start_deg' | 'arc_end_deg'>

  let {
    pivot,
    farms,
    other_pivots,
  }: { pivot: Partial<Omit<Pivot, 'fields'>>; farms: { id: number; name: string }[]; other_pivots: Outline[] } =
    $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const editing = $derived(pivot.id !== undefined)

  // The map and the inputs edit the same values
  let latitude = $state<number | null>(untrack(() => pivot.latitude ?? null))
  let longitude = $state<number | null>(untrack(() => pivot.longitude ?? null))
  let radiusFt = $state<number | null>(untrack(() => pivot.radius_ft ?? DEFAULT_RADIUS_FT))
  let isArc = $state(untrack(() => pivot.arc_start_deg !== null && pivot.arc_start_deg !== undefined))
  let arcStart = $state<number | null>(untrack(() => pivot.arc_start_deg ?? 0))
  let arcEnd = $state<number | null>(untrack(() => pivot.arc_end_deg ?? 270))

  // Unsaved changes: anything typed in the form, or the pivot moved on the map
  const initial = untrack(() => ({ latitude, longitude, radiusFt }))
  let edited = $state(false)
  let saved = $state(false)
  const moved = $derived(
    latitude !== initial.latitude || longitude !== initial.longitude || radiusFt !== initial.radiusFt,
  )
  confirmUnsavedChanges(() => !saved && (edited || moved))

  const area = $derived(radiusFt ? pivotAcres(radiusFt, isArc ? arcStart : null, isArc ? arcEnd : null) : null)
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
        <PivotMap
          bind:latitude
          bind:longitude
          bind:radiusFt
          arcStart={isArc ? arcStart : null}
          arcEnd={isArc ? arcEnd : null}
          others={other_pivots}
        />
        <div class="grid gap-4 sm:grid-cols-3">
          <NumberField label="Latitude" name="pivot[latitude]" bind:value={latitude} error={errors.latitude} />
          <NumberField label="Longitude" name="pivot[longitude]" bind:value={longitude} error={errors.longitude} />
          <NumberField
            label="Radius"
            name="pivot[radius_ft]"
            quantity="distance"
            bind:value={radiusFt}
            error={errors.radius_ft}
            hint={area ? `Irrigates about ${units.format('area', area)}` : undefined}
          />
        </div>
        <label class="flex items-center gap-3 text-sm">
          <input type="checkbox" bind:checked={isArc} class="rounded" />
          Partial circle (the pivot sweeps an arc rather than a full circle)
        </label>
        {#if isArc}
          <div class="grid gap-4 sm:grid-cols-2">
            <NumberField
              label="Arc starts at"
              name="pivot[arc_start_deg]"
              unitLabel="° from north"
              bind:value={arcStart}
              error={errors.arc_start_deg}
            />
            <NumberField
              label="Arc ends at"
              name="pivot[arc_end_deg]"
              unitLabel="° (clockwise)"
              bind:value={arcEnd}
              error={errors.arc_end_deg}
            />
          </div>
        {:else}
          <input type="hidden" name="pivot[arc_start_deg]" value="" />
          <input type="hidden" name="pivot[arc_end_deg]" value="" />
        {/if}
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
