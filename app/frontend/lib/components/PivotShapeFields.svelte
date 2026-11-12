<script lang="ts">
  import { page } from '@inertiajs/svelte'

  import NumberField from '@/lib/components/NumberField.svelte'
  import PivotMap from '@/lib/components/PivotMap.svelte'
  import SoilSurvey from '@/lib/components/SoilSurvey.svelte'
  import { draftShape, isPoint, type PivotKind, type PivotShape, shapeAcres, type ShapeDraft } from '@/lib/geo'
  import { units as unitsFor } from '@/lib/units'
  import type { SoilType } from '@/types/serializers'

  // An irrigation system's kind, location and size: the map picker and the inputs that edit the same
  // values, for the pivot form and the guided setup. A point kind (a traveler, solid set, drip, a
  // location only) has only its location. Inputs are named `${prefix}[attribute]`.
  let {
    shape = $bindable(),
    prefix,
    error,
    others = [],
    soilTypes,
    onsuggest,
  }: {
    shape: ShapeDraft
    prefix: string
    /** The server's error for one of the pivot's attributes */
    error: (attribute: string) => string | string[] | undefined
    others?: (PivotShape & { id: number; name: string })[]
    soilTypes: SoilType[]
    onsuggest?: (soilType: SoilType | null) => void
  } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const outline = $derived(draftShape(shape))
  const area = $derived(outline ? shapeAcres(outline) : null)
  const areaHint = $derived(area ? `Irrigates about ${units.format('area', area)}` : undefined)

  const KINDS: { value: PivotKind; label: string; hint: string }[] = [
    { value: 'center', label: 'Center pivot', hint: 'A circle, or part of one.' },
    { value: 'linear', label: 'Linear move', hint: 'A rectangle the machine travels along.' },
    {
      value: 'traveler',
      label: 'Traveler',
      hint: 'A hard hose reel or gun moved between fields. Set one up at each field it waters, and name the machine in Equipment.',
    },
    { value: 'solid_set', label: 'Solid set', hint: 'Sprinklers set out over a block. Place it at the block.' },
    { value: 'drip', label: 'Drip', hint: 'Drip tape or emitters. Place it at the block.' },
    { value: 'point', label: 'Location only', hint: 'Just where the field is, for its weather and soil.' },
  ]
</script>

<fieldset class="space-y-2">
  <legend class="text-sm font-medium">Irrigation system</legend>
  <input type="hidden" name="{prefix}[kind]" value={shape.kind} />
  <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
    {#each KINDS as kind (kind.value)}
      <label
        class="flex items-start gap-2 rounded-md border px-3 py-2 text-sm
          {shape.kind === kind.value ? 'border-brand-500 bg-brand-50' : 'border-line'}"
      >
        <input type="radio" value={kind.value} bind:group={shape.kind} class="mt-0.5" />
        <span><span class="block font-medium">{kind.label}</span> <span class="text-ink-muted">{kind.hint}</span></span>
      </label>
    {/each}
  </div>
  {#if isPoint(shape.kind)}
    <p class="text-sm text-ink-muted">
      Its area comes from its fields. Weather and the soil suggestion come from where you place it.
    </p>
  {/if}
  {#if error('kind')}<p class="text-sm text-status-irrigate-ink">{error('kind')}</p>{/if}
</fieldset>

<PivotMap bind:shape {others} {soilTypes} />
<SoilSurvey shape={outline} {soilTypes} {onsuggest} />

<div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
  <NumberField label="Latitude" name="{prefix}[latitude]" bind:value={shape.latitude} error={error('latitude')} />
  <NumberField label="Longitude" name="{prefix}[longitude]" bind:value={shape.longitude} error={error('longitude')} />
  {#if shape.kind === 'center'}
    <NumberField
      label="Radius"
      name="{prefix}[radius_ft]"
      quantity="distance"
      bind:value={shape.radiusFt}
      error={error('radius_ft')}
      hint={areaHint}
    />
  {/if}
</div>

{#if shape.kind === 'linear'}
  <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
    <NumberField
      label="Machine length"
      name="{prefix}[length_ft]"
      quantity="distance"
      bind:value={shape.lengthFt}
      error={error('length_ft')}
    />
    <NumberField
      label="Travel distance"
      name="{prefix}[travel_ft]"
      quantity="distance"
      bind:value={shape.travelFt}
      error={error('travel_ft')}
      hint={areaHint}
    />
    <NumberField
      label="Direction of travel"
      name="{prefix}[travel_bearing_deg]"
      unitLabel="° from north"
      bind:value={shape.travelBearing}
      error={error('travel_bearing_deg')}
      hint="A whole number from 0 to 179: 0 means the machine travels north and south, 90 east and west."
    />
  </div>
{/if}

{#if shape.kind === 'center'}
  <label class="flex items-center gap-3 text-sm">
    <input type="checkbox" bind:checked={shape.partial} class="rounded" />
    Partial circle (the pivot sweeps an arc rather than a full circle)
  </label>
  {#if shape.partial}
    <div class="grid gap-4 sm:grid-cols-2">
      <NumberField
        label="Arc starts at"
        name="{prefix}[arc_start_deg]"
        unitLabel="° from north"
        bind:value={shape.arcStart}
        error={error('arc_start_deg')}
      />
      <NumberField
        label="Arc ends at"
        name="{prefix}[arc_end_deg]"
        unitLabel="° (clockwise)"
        bind:value={shape.arcEnd}
        error={error('arc_end_deg')}
      />
    </div>
  {:else}
    <input type="hidden" name="{prefix}[arc_start_deg]" value="" />
    <input type="hidden" name="{prefix}[arc_end_deg]" value="" />
  {/if}
{/if}
