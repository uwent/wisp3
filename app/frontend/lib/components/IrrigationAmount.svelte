<script lang="ts">
  import NumberField from '@/lib/components/NumberField.svelte'

  // An irrigation's amount, as inches or as run hours. The other one is submitted blank, so saving
  // one way clears what was saved the other way (the server converts run hours to inches).
  let {
    name,
    byHours,
    value = $bindable(null),
    errors = {},
    inchesLabel = 'Amount',
    hoursLabel = 'Run hours',
    inchesPlaceholder,
    hoursPlaceholder,
    hideLabel = false,
  }: {
    /** The record's input name: "pivot_irrigation" submits pivot_irrigation[inches] and pivot_irrigation[run_hours] */
    name: string
    /** Run hours rather than inches */
    byHours: boolean
    /** The amount in the box shown: stored inches, or hours */
    value?: number | null
    errors?: { inches?: string | string[]; run_hours?: string | string[] }
    inchesLabel?: string
    hoursLabel?: string
    inchesPlaceholder?: string
    hoursPlaceholder?: string
    /** Labels for screen readers only (in table cells) */
    hideLabel?: boolean
  } = $props()
</script>

{#if byHours}
  <NumberField
    {hideLabel}
    label={hoursLabel}
    name="{name}[run_hours]"
    unitLabel="h"
    bind:value
    placeholder={hoursPlaceholder}
    error={errors.run_hours}
  />
  <input type="hidden" name="{name}[inches]" value="" />
{:else}
  <NumberField
    {hideLabel}
    label={inchesLabel}
    name="{name}[inches]"
    quantity="depth"
    bind:value
    placeholder={inchesPlaceholder}
    error={errors.inches}
  />
  <input type="hidden" name="{name}[run_hours]" value="" />
{/if}
