<script lang="ts">
  import NumberField from '@/lib/components/NumberField.svelte'
  import { circleNoun, type IrrigationUnit, percentInches } from '@/lib/irrigation'
  import { currentUnits } from '@/lib/units'

  // An irrigation's amount, as inches, run hours or the percent timer's setting with the circles (or
  // passes) run at it (docs/plans/phase-9.md §8). The others are submitted blank, so saving one way
  // clears what was saved another way (the server converts run hours and percents to inches).
  let {
    name,
    unit,
    value = $bindable(null),
    circles = $bindable(null),
    kind = 'center',
    inchesAt100 = null,
    errors = {},
    inchesLabel = 'Amount',
    hoursLabel = 'Run hours',
    percentLabel = 'Percent timer',
    circlesLabel,
    inchesPlaceholder,
    hoursPlaceholder,
    percentPlaceholder,
    hideLabel = false,
  }: {
    /** The record's input name: "pivot_irrigation" submits pivot_irrigation[inches] and the rest */
    name: string
    unit: IrrigationUnit
    /** The amount in the box shown: stored inches, hours or percent */
    value?: number | null
    /** Circles at the percent; null for one */
    circles?: number | null
    /** The system's kind, which names a circle ("pass" for a linear) */
    kind?: string
    /** The system's depth at 100%, for the inches a percent comes to */
    inchesAt100?: number | null
    errors?: {
      inches?: string | string[]
      run_hours?: string | string[]
      percent_timer?: string | string[]
      circles?: string | string[]
    }
    inchesLabel?: string
    hoursLabel?: string
    percentLabel?: string
    circlesLabel?: string
    inchesPlaceholder?: string
    hoursPlaceholder?: string
    percentPlaceholder?: string
    /** Labels for screen readers only (in table cells) */
    hideLabel?: boolean
  } = $props()

  const units = $derived(currentUnits())
  const noun = $derived(circleNoun(kind))
  const comesTo = $derived(unit === 'percent' ? percentInches(inchesAt100, value, circles) : null)
  const blank = (field: string) => `${name}[${field}]`
</script>

{#if unit === 'hours'}
  <NumberField
    {hideLabel}
    label={hoursLabel}
    name={blank('run_hours')}
    unitLabel="h"
    bind:value
    placeholder={hoursPlaceholder}
    error={errors.run_hours}
  />
{:else if unit === 'percent'}
  <!-- In a table (hideLabel) the boxes' units are shown here, as NumberField leaves them out -->
  <div class="flex flex-wrap items-start gap-x-2 gap-y-1">
    <div class="flex items-start gap-1 {hideLabel ? 'w-20' : 'w-32'}">
      <div class="min-w-0 flex-1">
        <NumberField
          {hideLabel}
          label={percentLabel}
          name={blank('percent_timer')}
          unitLabel="%"
          bind:value
          placeholder={percentPlaceholder}
          error={errors.percent_timer}
        />
      </div>
      {#if hideLabel}<span class="py-2 text-xs text-ink-muted" aria-hidden="true">%</span>{/if}
    </div>
    <div class="flex items-start gap-1 {hideLabel ? 'w-24' : 'w-36'}">
      <div class="min-w-0 flex-1">
        <NumberField
          {hideLabel}
          label={circlesLabel ?? `${noun[0].toUpperCase()}${noun.slice(1)}s`}
          name={blank('circles')}
          unitLabel="{noun}s"
          bind:value={circles}
          blankValue={1}
          error={errors.circles}
        />
      </div>
      {#if hideLabel}<span class="py-2 text-xs text-ink-muted" aria-hidden="true">{noun}s</span>{/if}
    </div>
    <p
      class="text-ink-muted {hideLabel
        ? 'py-2 text-xs'
        : 'flex h-10.5 items-center self-end text-sm whitespace-nowrap sm:h-9.5'}"
      aria-live="polite"
    >
      {comesTo === null ? `a ${noun} at that speed` : `= ${units.format('depth', comesTo)}`}
    </p>
  </div>
{:else}
  <NumberField
    {hideLabel}
    label={inchesLabel}
    name={blank('inches')}
    quantity="depth"
    bind:value
    placeholder={inchesPlaceholder}
    error={errors.inches}
  />
{/if}
{#if unit !== 'inches'}<input type="hidden" name={blank('inches')} value="" />{/if}
{#if unit !== 'hours'}<input type="hidden" name={blank('run_hours')} value="" />{/if}
{#if unit !== 'percent'}
  <input type="hidden" name={blank('percent_timer')} value="" />
  <input type="hidden" name={blank('circles')} value="" />
{/if}
