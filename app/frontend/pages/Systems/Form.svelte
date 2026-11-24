<script lang="ts">
  import { untrack } from 'svelte'
  import { Form, Link, page, router } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import FormFooter from '@/lib/components/FormFooter.svelte'
  import FieldLabel from '@/lib/components/FieldLabel.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import SystemShapeFields from '@/lib/components/SystemShapeFields.svelte'
  import SectionHeading from '@/lib/components/SectionHeading.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import {
    draftShape,
    isPoint,
    KIND_NAMES,
    KIND_NOUNS,
    type LngLat,
    type SystemKind,
    type SystemShape,
    shapeAcres,
    shapeDraft,
    systemName,
    systemsFrame,
  } from '@/lib/geo'
  import { circleNoun, hasTimer, hoursInches } from '@/lib/irrigation'
  import { currentUnits } from '@/lib/units'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { systems, setup } from '@/routes'
  import type { FileShapes } from '@/lib/outlines/fileShapes'
  import { type Boundary } from '@/lib/boundary'
  import { unimportedShapes } from '@/lib/outlines/fileShapes'
  import { readKept } from '@/lib/outlines/kept'
  import type { IrrigationSystem, SoilType } from '@/types/serializers'

  type Outline = SystemShape &
    Pick<IrrigationSystem, 'id' | 'name' | 'farm_id'> & {
      /** Its fields' outlines' extent, [[west, south], [east, north]] */
      fields_extent: [LngLat, LngLat] | null
    }

  let {
    system,
    farms,
    other_systems,
    soil_types,
    irrigation_group = null,
    copy_of = null,
    field_outlines = [],
  }: {
    system: Partial<Omit<IrrigationSystem, 'fields'>>
    farms: { id: number; name: string }[]
    other_systems: Outline[]
    soil_types: SoilType[]
    /** The group a duplicated system's copy joins */
    irrigation_group?: { id: number; name: string; farm_id: number } | null
    /** The system being duplicated (Setup's Duplicate, ?copy_of=): everything but its location is copied */
    copy_of?: { id: number; name: string } | null
    /** The operation's field outlines, on the map */
    field_outlines?: { name: string; boundary: Boundary }[]
  } = $props()

  // A kept outline file's shapes not yet imported, on the map as a guide to place the system on
  const fileShapes: FileShapes | null = untrack(() => {
    const kept = readKept(page.props.auth.group?.id)
    return (
      kept &&
      unimportedShapes(
        kept,
        field_outlines.map((field) => field.boundary),
      )
    )
  })

  const editing = $derived(system.id !== undefined)
  let farmId = $state(untrack(() => String(system.farm_id ?? farms[0]?.id ?? '')))
  const joinsGroup = $derived(
    !editing && irrigation_group && String(irrigation_group.farm_id) === farmId ? irrigation_group : null,
  )
  // The map opens on the chosen farm's systems and their fields (all of the operation's when it has none)
  const frame = $derived(systemsFrame(other_systems.filter((other) => String(other.farm_id) === farmId)))

  // The map and the inputs edit the same values
  let shape = $state(untrack(() => shapeDraft(system)))

  // Unsaved changes: anything typed in the form, or the system moved or resized on the map
  const initial = untrack(() => JSON.stringify(draftShape(shape)))
  let edited = $state(false)
  let saved = $state(false)
  const moved = $derived(JSON.stringify(draftShape(shape)) !== initial)
  confirmUnsavedChanges(
    () => !saved && (edited || moved),
    () => document.getElementById('system-form'),
  )

  // The kind as saved, for the title; the kind being chosen, for the words below it
  const title = $derived(
    editing
      ? `Edit ${systemName({ name: system.name ?? '', kind_name: KIND_NAMES[system.kind ?? 'center'] })}`
      : copy_of
        ? `Duplicate ${copy_of.name}`
        : 'Add an irrigation system',
  )
  const noun = $derived(KIND_NOUNS[shape.kind])
  const units = $derived(currentUnits())

  // The percent timer: the depth a circle (a linear's pass) puts on at
  // 100%, from the sprinkler chart, or worked out from the hours one takes at 100%, the pump
  // capacity and the system's own area on the map
  let pumpGpm = $state<number | null>(untrack(() => system.pump_capacity_gpm ?? null))
  let inchesAt100 = $state<number | null>(untrack(() => system.inches_at_100 ?? null))
  let fromHours = $state(false)
  let circleHours = $state<number | null>(null)
  const circle = $derived(circleNoun(shape.kind))
  const mappedAcres = $derived.by(() => {
    const outline = draftShape(shape)
    return outline ? shapeAcres(outline) : null
  })
  const workedOut = $derived(pumpGpm && circleHours ? hoursInches(pumpGpm, circleHours, [mappedAcres]) : null)

  // Only owners delete (Q8); the system's fields and their seasons go with it
  function destroy() {
    const name = systemName({ name: system.name ?? '', kind_name: KIND_NAMES[system.kind ?? 'center'] })
    if (!confirm(`Delete ${name} and its fields? This can't be undone.`)) return
    // Leaving without asking; if the delete is refused and this page stays, the guard comes back
    saved = true
    router.delete(systems.destroy(system.id!).url, { onFinish: () => (saved = false) })
  }
  const EQUIPMENT_EXAMPLES: Record<SystemKind, string> = {
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
      : copy_of
        ? `Its kind, size and equipment are copied from ${copy_of.name}, not its fields. Place the new ${noun} on the map.`
        : "You can move it or change any of this after it's created."}
  </p>
</div>

<Form
  id="system-form"
  action={editing ? systems.update(system.id!) : systems.create()}
  class="space-y-6"
  onSuccess={() => (saved = true)}
>
  {#snippet children({ errors, processing })}
    <div class="space-y-6" oninput={() => (edited = true)} onchange={() => (edited = true)}>
      {#if copy_of}<input type="hidden" name="copy_of" value={copy_of.id} />{/if}
      {#if joinsGroup}<input type="hidden" name="system[irrigation_group_id]" value={joinsGroup.id} />{/if}
      <section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
        <div class="grid gap-4 sm:grid-cols-2">
          <TextField label="Name" name="system[name]" value={system.name ?? ''} error={errors.name} required />
          <SelectField
            label="Farm"
            name="system[farm_id]"
            bind:value={farmId}
            options={farms.map((farm) => ({ value: String(farm.id), label: farm.name }))}
            info="system.farm"
            hint={joinsGroup ? `It joins the group ${joinsGroup.name}` : undefined}
            error={errors.farm}
            required
          />
        </div>
        <SystemShapeFields
          bind:shape
          prefix="system"
          error={(attribute) => errors[attribute]}
          others={other_systems}
          {frame}
          soilTypes={soil_types}
          headingLevel="h2"
          locked={editing}
          {fileShapes}
          fields={field_outlines}
        />

        <section class="space-y-4" aria-labelledby="system-equipment">
          <SectionHeading label="Equipment and notes" id="system-equipment" level="h2" />
          <div
            class="grid items-start gap-4 sm:grid-cols-2 {hasTimer(shape.kind) ? 'sm:grid-rows-[auto_1fr_auto]' : ''}"
          >
            <NumberField
              label={isPoint(shape.kind) ? 'Flow' : 'Pump capacity'}
              name="system[pump_capacity_gpm]"
              quantity="flow"
              bind:value={pumpGpm}
              info="system.pump_capacity"
              error={errors.pump_capacity_gpm}
              optional
            />
            {#if hasTimer(shape.kind)}
              <!-- Beside the pump capacity and the equipment, so the helper below grows down the right -->
              <div class="space-y-2 sm:row-span-2">
                <NumberField
                  label="Depth at 100%"
                  name="system[inches_at_100]"
                  quantity="depth"
                  bind:value={inchesAt100}
                  info="system.inches_at_100"
                  error={errors.inches_at_100}
                  hint="What a {circle} puts on at full speed, from its sprinkler chart. With it you can enter irrigation as the percent timer's setting."
                  optional
                />
                {#if fromHours}
                  <div class="space-y-2 rounded-md border border-line p-3">
                    <NumberField
                      label="Hours for a {circle} at 100%"
                      id="system-circle-hours"
                      unitLabel="h"
                      bind:value={circleHours}
                    />
                    <p class="text-xs text-ink-muted" aria-live="polite">
                      {#if !pumpGpm}Add the pump capacity first.{:else if !mappedAcres}Place the {noun} on the map first.{:else if workedOut === null}{`With the pump capacity over the ${units.format('area', mappedAcres)} it covers on the map.`}{:else}{`${units.format('flow', pumpGpm)} for ${circleHours} hours over ${units.format('area', mappedAcres)}: ${units.format('depth', workedOut)}. An end gun waters more than the map shows, so the depth is a little less.`}{/if}
                    </p>
                    <div class="flex gap-2">
                      <Button
                        variant="secondary"
                        class="px-3 py-1 text-xs"
                        disabled={workedOut === null}
                        onclick={() => {
                          inchesAt100 = workedOut === null ? null : Number(workedOut.toFixed(3))
                          fromHours = false
                          edited = true
                        }}
                      >
                        Use this depth
                      </Button>
                      <Button variant="ghost" class="px-3 py-1 text-xs" onclick={() => (fromHours = false)}>
                        Cancel
                      </Button>
                    </div>
                  </div>
                {:else}
                  <button
                    type="button"
                    class="text-xs text-brand-600 underline underline-offset-2"
                    onclick={() => (fromHours = true)}
                  >
                    Work it out from the hours a {circle} takes
                  </button>
                {/if}
              </div>
            {/if}
            <TextField
              label="Equipment"
              name="system[equipment]"
              value={system.equipment ?? ''}
              placeholder={EQUIPMENT_EXAMPLES[shape.kind]}
              info="system.equipment"
              optional
              hint={shape.kind === 'traveler' ? 'The machine, named the same at each field it waters' : undefined}
            />
            <div class="space-y-1 sm:col-span-2">
              <FieldLabel label="Notes" for="system-notes" optional />
              <textarea id="system-notes" name="system[notes]" rows="2" class="block w-full rounded-md text-sm"
                >{system.notes ?? ''}</textarea
              >
            </div>
          </div>
        </section>
      </section>

      <FormFooter
        ondelete={editing && page.props.auth.owner ? destroy : undefined}
        deleteLabel="Delete this {KIND_NOUNS[system.kind ?? 'center']}"
      >
        <Button type="submit" disabled={processing}>{editing ? 'Save' : 'Add irrigation system'}</Button>
      </FormFooter>
    </div>
  {/snippet}
</Form>
