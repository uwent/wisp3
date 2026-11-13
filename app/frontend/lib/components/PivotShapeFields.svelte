<script lang="ts">
  import { page } from '@inertiajs/svelte'
  import type { Snippet } from 'svelte'

  import NumberField from '@/lib/components/NumberField.svelte'
  import PivotMap from '@/lib/components/PivotMap.svelte'
  import SoilSurvey from '@/lib/components/SoilSurvey.svelte'
  import {
    draftShape,
    isPoint,
    KIND_NOUNS,
    type PivotKind,
    type PivotShape,
    shapeAcres,
    type ShapeDraft,
  } from '@/lib/geo'
  import { units as unitsFor } from '@/lib/units'
  import type { SoilType } from '@/types/serializers'

  // An irrigation system's kind, location and size: the map picker and the inputs that edit the same
  // values, for the pivot form and the guided setup. A point kind (a traveler, solid set, drip, a
  // location only) has only its location. Inputs are named `${prefix}[attribute]`. `children` (the
  // setup's pump capacity) ends the coordinates' row; the soil survey comes last.
  let {
    shape = $bindable(),
    prefix,
    error,
    others = [],
    soilTypes,
    onsuggest,
    children,
    surveyLevel = 'h3',
    surveyNote,
  }: {
    shape: ShapeDraft
    prefix: string
    /** The server's error for one of the pivot's attributes */
    error: (attribute: string) => string | string[] | undefined
    others?: (PivotShape & { id: number; name: string })[]
    soilTypes: SoilType[]
    onsuggest?: (soilType: SoilType | null, shares: Map<string, number>) => void
    children?: Snippet
    /** The soil survey heading's level, to fit the page's outline */
    surveyLevel?: 'h2' | 'h3'
    /** A line under the soil survey's heading */
    surveyNote?: string
  } = $props()

  // Sizes stay blank until the system is placed (then the map's shape fills them) or one is typed
  // (then placing it uses that size)
  const placed = $derived(shape.latitude !== null && shape.longitude !== null)
  let typed = $state({ radius: false, length: false, travel: false })
  const sized = (key: keyof typeof typed) => placed || typed[key]
  const SWEEPS = [
    [false, 'Full circle'],
    [true, 'Partial circle'],
  ] as const

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const outline = $derived(draftShape(shape))
  const area = $derived(outline ? shapeAcres(outline) : null)
  const areaHint = $derived(area ? `Irrigates about ${units.format('area', area)}` : undefined)

  const KINDS: { value: PivotKind; label: string; hint: string }[] = [
    { value: 'center', label: 'Center pivot', hint: 'A circle, or part of one.' },
    { value: 'linear', label: 'Linear', hint: 'A rectangle the machine travels along.' },
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

<div class="grid gap-4 sm:grid-cols-2 {children ? 'lg:grid-cols-4' : 'lg:grid-cols-3'}">
  <NumberField label="Latitude" name="{prefix}[latitude]" bind:value={shape.latitude} error={error('latitude')} />
  <NumberField label="Longitude" name="{prefix}[longitude]" bind:value={shape.longitude} error={error('longitude')} />
  {#if shape.kind === 'center'}
    <NumberField
      label="Radius"
      name="{prefix}[radius_ft]"
      quantity="distance"
      bind:value={() => (sized('radius') ? shape.radiusFt : null), (v) => ((typed.radius = true), (shape.radiusFt = v))}
      error={error('radius_ft')}
      hint={areaHint}
    />
  {/if}
  {@render children?.()}
</div>

{#if shape.kind === 'linear'}
  <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
    <NumberField
      label="Machine length"
      name="{prefix}[length_ft]"
      quantity="distance"
      bind:value={() => (sized('length') ? shape.lengthFt : null), (v) => ((typed.length = true), (shape.lengthFt = v))}
      error={error('length_ft')}
    />
    <NumberField
      label="Travel distance"
      name="{prefix}[travel_ft]"
      quantity="distance"
      bind:value={() => (sized('travel') ? shape.travelFt : null), (v) => ((typed.travel = true), (shape.travelFt = v))}
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
  <div class="flex flex-wrap items-start gap-x-6 gap-y-4">
    <div class="space-y-1">
      <span id="pivot-sweep" class="block text-sm font-medium">Pivot sweep</span>
      <div
        class="flex overflow-hidden rounded-md border border-line text-sm sm:w-fit"
        role="radiogroup"
        aria-labelledby="pivot-sweep"
      >
        {#each SWEEPS as [value, label] (label)}
          <label
            class="flex flex-1 cursor-pointer items-center px-3 py-2 whitespace-nowrap has-checked:bg-brand-600 has-checked:text-white
              has-focus-visible:outline-2 has-focus-visible:outline-brand-500 dark:has-checked:text-surface"
          >
            <input
              type="radio"
              class="sr-only"
              name="pivot-sweep"
              checked={shape.partial === value}
              onchange={() => (shape.partial = value)}
            />
            {label}
          </label>
        {/each}
      </div>
    </div>
    {#if shape.partial}
      <div class="grid flex-1 gap-4 sm:min-w-96 sm:grid-cols-2">
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
  </div>
{/if}

<section class="space-y-2" aria-labelledby="soil-survey">
  <svelte:element this={surveyLevel} id="soil-survey" class="font-medium">Soil survey</svelte:element>
  {#if surveyNote}<p class="text-sm text-ink-muted">{surveyNote}</p>{/if}
  {#if !outline}
    <p class="rounded-md border border-dashed border-line px-3 py-2 text-sm text-ink-muted">
      Place the {KIND_NOUNS[shape.kind]} on the map to see the soils around it.
    </p>
  {/if}
  <SoilSurvey shape={outline} {soilTypes} {onsuggest} />
</section>
