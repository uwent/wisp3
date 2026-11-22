<script lang="ts">
  import type { IrrigationUnit } from '@/lib/irrigation'
  import { currentUnits } from '@/lib/units'

  // How an irrigation's amount is entered (docs/plans/phase-9.md §8): in | hours | % timer, as a
  // row of radio buttons. Only the units the system can convert are offered (unitsFor); with one,
  // nothing is shown.
  let {
    name,
    label,
    units: offered,
    unit,
    onchange,
  }: {
    /** The radios' group name, unique on the page */
    name: string
    /** What the choice is for, for screen readers: "Enter North's irrigation as" */
    label: string
    units: IrrigationUnit[]
    unit: IrrigationUnit
    onchange: (unit: IrrigationUnit) => void
  } = $props()

  const userUnits = $derived(currentUnits())
  const names = $derived<Record<IrrigationUnit, string>>({
    inches: userUnits.label('depth'),
    hours: 'hours',
    percent: '% timer',
  })
</script>

{#if offered.length > 1}
  <div class="flex w-fit overflow-hidden rounded-md border border-line text-xs" role="radiogroup" aria-label={label}>
    {#each offered as option (option)}
      <label
        class="relative flex cursor-pointer items-center px-2 py-1 whitespace-nowrap has-checked:bg-brand-600 has-checked:text-white
          has-focus-visible:outline-2 has-focus-visible:outline-brand-500 dark:has-checked:text-surface"
      >
        <input
          type="radio"
          class="sr-only"
          {name}
          value={option}
          checked={unit === option}
          onchange={() => onchange(option)}
        />
        {names[option]}
      </label>
    {/each}
  </div>
{/if}
