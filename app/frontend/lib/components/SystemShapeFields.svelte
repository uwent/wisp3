<script lang="ts">
  import { type Snippet, tick, untrack } from 'svelte'

  import CoordinatesField from '@/lib/components/CoordinatesField.svelte'
  import FieldLabel from '@/lib/components/FieldLabel.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import KindIcon from '@/lib/components/KindIcon.svelte'
  import SystemMap from '@/lib/components/SystemMap.svelte'
  import type { FileShapes } from '@/lib/outlines/fileShapes'
  import type { SavedField } from '@/lib/outlines/layers'
  import SectionHeading from '@/lib/components/SectionHeading.svelte'
  import SoilSurvey from '@/lib/components/SoilSurvey.svelte'
  import {
    draftShape,
    isPoint,
    KIND_NOUNS,
    type LngLat,
    type SystemKind,
    type SystemShape,
    shapeAcres,
    type ShapeDraft,
  } from '@/lib/geo'
  import { currentUnits } from '@/lib/units'
  import type { SoilType } from '@/types/serializers'

  // An irrigation system's kind, location and size: the map picker and the inputs that edit the same
  // values, for the system form and the guided setup. A point kind (a traveler, solid set, drip, a
  // location only) has only its location. Inputs are named `${prefix}[attribute]`. `children` (the
  // setup's pump capacity) ends the coordinates' row; the soil survey comes last. In sections, each
  // under a heading: the kind, the location and size, and the soil survey; a saved
  // system's kind, rarely changed, is one line until Change shows the choices.
  let {
    shape = $bindable(),
    prefix,
    error,
    others = [],
    frame = null,
    soilTypes,
    onsuggest,
    children,
    headingLevel = 'h3',
    surveyNote,
    locked = false,
    fileShapes = null,
    fields = [],
  }: {
    shape: ShapeDraft
    prefix: string
    /** The server's error for one of the system's attributes */
    error: (attribute: string) => string | string[] | undefined
    others?: (SystemShape & { id: number; name: string })[]
    /** What the map opens on while the system has no location (SystemMap) */
    frame?: [LngLat, LngLat] | null
    soilTypes: SoilType[]
    onsuggest?: (soilType: SoilType | null, shares: Map<string, number>) => void
    children?: Snippet
    /** The sections' headings' level, to fit the page's outline */
    headingLevel?: 'h2' | 'h3'
    /** A line under the soil survey's heading */
    surveyNote?: string
    /** A saved system: the map starts locked (unlocked with Edit on the map) and the kind is one line */
    locked?: boolean
    /** A kept outline file's shapes not yet imported, drawn on the map as a guide */
    fileShapes?: FileShapes | null
    /** The operation's field outlines, on the map */
    fields?: SavedField[]
  } = $props()

  let systemMap = $state<SystemMap>()

  // A saved system's kind is shown as one line until Change (or an error in it) shows the choices
  let kindOpen = $state(untrack(() => !locked))
  const showKinds = $derived(kindOpen || Boolean(error('kind')))
  let kindChoices = $state<HTMLElement>()
  async function changeKind() {
    kindOpen = true
    await tick()
    kindChoices?.querySelector<HTMLInputElement>('input:checked')?.focus()
  }

  // Sizes stay blank until the system is placed (then the map's shape fills them) or one is typed
  // (then placing it uses that size)
  const placed = $derived(shape.latitude !== null && shape.longitude !== null)
  let typed = $state({ radius: false, length: false, travel: false })
  const sized = (key: keyof typeof typed) => placed || typed[key]
  const SWEEPS = [
    [false, 'Full circle'],
    [true, 'Partial circle'],
  ] as const

  const units = $derived(currentUnits())
  const outline = $derived(draftShape(shape))
  const area = $derived(outline ? shapeAcres(outline) : null)
  const areaHint = $derived(area ? `Irrigates about ${units.format('area', area)}` : undefined)

  const KINDS: { value: SystemKind; label: string; hint: string }[] = [
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

<section class="space-y-3" aria-labelledby="system-kind">
  <SectionHeading label="Kind of system" id="system-kind" level={headingLevel} info="system.kind" />
  <input type="hidden" name="{prefix}[kind]" value={shape.kind} />
  {#if showKinds}
    <fieldset class="relative space-y-2">
      <legend class="sr-only">Kind of system</legend>
      <div bind:this={kindChoices} class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
        {#each KINDS as kind (kind.value)}
          <label
            class="flex items-start gap-2 rounded-md border px-3 py-2 text-sm
              {shape.kind === kind.value ? 'border-brand-500 bg-brand-50' : 'border-line'}"
          >
            <input type="radio" value={kind.value} bind:group={shape.kind} class="mt-0.5" />
            <span>
              <span class="block font-medium">{kind.label}</span> <span class="text-ink-muted">{kind.hint}</span>
            </span>
          </label>
        {/each}
      </div>
      {#if isPoint(shape.kind)}
        <p class="text-sm text-ink-muted">
          Its area comes from its fields. {onsuggest
            ? 'Weather and the soil suggestion come from where you place it.'
            : 'Its weather comes from where you place it.'}
        </p>
      {/if}
    </fieldset>
  {:else}
    <div class="flex items-center justify-between gap-3 rounded-md border border-line px-3 py-2 text-sm">
      <span class="flex items-center gap-2 font-medium">
        <KindIcon kind={shape.kind} />{KINDS.find((kind) => kind.value === shape.kind)?.label}
      </span>
      <button
        type="button"
        class="text-brand-600 hover:underline"
        aria-label="Change the kind of system"
        onclick={changeKind}
      >
        Change
      </button>
    </div>
  {/if}
  {#if error('kind')}<p class="text-sm text-status-irrigate-ink">{error('kind')}</p>{/if}
</section>

<section class="space-y-4" aria-labelledby="system-location">
  <SectionHeading
    label={isPoint(shape.kind) ? 'Location' : 'Location and size'}
    id="system-location"
    level={headingLevel}
  />
  <SystemMap bind:this={systemMap} bind:shape {others} {frame} {soilTypes} {locked} {fileShapes} {fields} />

  <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
    <CoordinatesField
      {prefix}
      bind:latitude={shape.latitude}
      bind:longitude={shape.longitude}
      info="system.coordinates"
      error={error('latitude') ?? error('longitude')}
      required
    />
    {#if shape.kind === 'center'}
      <NumberField
        label="Radius"
        name="{prefix}[radius_ft]"
        quantity="distance"
        bind:value={
          () => (sized('radius') ? shape.radiusFt : null), (v) => ((typed.radius = true), (shape.radiusFt = v))
        }
        info="system.radius"
        error={error('radius_ft')}
        optional
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
        bind:value={
          () => (sized('length') ? shape.lengthFt : null), (v) => ((typed.length = true), (shape.lengthFt = v))
        }
        info="system.length"
        error={error('length_ft')}
        required
      />
      <NumberField
        label="Travel distance"
        name="{prefix}[travel_ft]"
        quantity="distance"
        bind:value={
          () => (sized('travel') ? shape.travelFt : null), (v) => ((typed.travel = true), (shape.travelFt = v))
        }
        info="system.travel"
        error={error('travel_ft')}
        required
        hint={areaHint}
      />
      <NumberField
        label="Direction of travel"
        name="{prefix}[travel_bearing_deg]"
        unitLabel="° from north"
        bind:value={shape.travelBearing}
        error={error('travel_bearing_deg')}
        info="system.bearing"
        required
      />
    </div>
  {/if}

  {#if shape.kind === 'center'}
    <div class="flex flex-wrap items-start gap-x-6 gap-y-4">
      <div class="space-y-1">
        <FieldLabel as="span" label="Pivot sweep" labelId="system-sweep" info="system.sweep" />
        <div
          class="flex overflow-hidden rounded-md border border-line text-sm sm:w-fit"
          role="radiogroup"
          aria-labelledby="system-sweep"
        >
          {#each SWEEPS as [value, label] (label)}
            <label
              class="flex flex-1 cursor-pointer items-center px-3 py-2 whitespace-nowrap has-checked:bg-brand-600 has-checked:text-white
              has-focus-visible:outline-2 has-focus-visible:outline-brand-500 dark:has-checked:text-surface"
            >
              <input
                type="radio"
                class="sr-only"
                name="system-sweep"
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
            info="system.arc_start"
            error={error('arc_start_deg')}
            required
          />
          <NumberField
            label="Arc ends at"
            name="{prefix}[arc_end_deg]"
            unitLabel="° (clockwise)"
            bind:value={shape.arcEnd}
            info="system.arc_end"
            error={error('arc_end_deg')}
            required
          />
        </div>
      {:else}
        <input type="hidden" name="{prefix}[arc_start_deg]" value="" />
        <input type="hidden" name="{prefix}[arc_end_deg]" value="" />
      {/if}
    </div>
  {/if}
</section>

<!-- Only where a soil is suggested (quick setup's fields): a system has no soil of its own -->
{#if onsuggest}
  <section class="space-y-2" aria-labelledby="soil-survey">
    <SectionHeading label="Soil survey" id="soil-survey" level={headingLevel}>
      {#if systemMap}
        <button
          type="button"
          class="text-sm text-brand-600 hover:underline"
          aria-pressed={systemMap.soil.on}
          onclick={() => systemMap?.soil.toggle()}
        >
          {systemMap.soil.on ? 'Hide soil types on the map' : 'Show soil types on the map'}
        </button>
      {/if}
    </SectionHeading>
    {#if surveyNote}<p class="text-sm text-ink-muted">{surveyNote}</p>{/if}
    {#if !outline}
      <p class="rounded-md border border-dashed border-line px-3 py-2 text-sm text-ink-muted">
        Place the {KIND_NOUNS[shape.kind]} on the map to see the soils around it.
      </p>
    {/if}
    <SoilSurvey shape={outline} {soilTypes} {onsuggest} />
  </section>
{/if}
