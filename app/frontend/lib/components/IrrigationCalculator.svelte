<script lang="ts">
  import { router } from '@inertiajs/svelte'
  import { untrack } from 'svelte'

  import NumberField from '@/lib/components/NumberField.svelte'
  import Term from '@/lib/components/Term.svelte'
  import {
    CALCULATOR_LIMITS as LIMITS,
    type CalculatorMethod,
    type CalculatorSystem,
    calculatorMethods,
    circleNoun,
    hoursInches,
    outOfRange,
    percentInches,
  } from '@/lib/irrigation'
  import { currentUnits } from '@/lib/units'
  import { systems } from '@/routes'

  // The irrigation calculator (D15): irrigation is entered in
  // inches, and this works them out from the run hours (gallons a minute × hours, over the acres of
  // the fields watered) or, on a pivot or linear, the percent timer (the depth at 100% × 100 ÷
  // percent, for each circle), laid out as a sum with its result beside it. The pump capacity and
  // depth at 100% start as the system's (its placeholders) and can be typed here; a value typed that
  // isn't the system's can be saved to it (saveEquipment, SystemsController#equipment). result is the
  // inches when they can be used (none out of range, not more than a day could be). In a dialog of
  // its own (IrrigationCalculatorDialog) or in the dashboard's log irrigation dialog.
  type Field = { id: number; name: string; acres: number | null }
  let {
    system,
    fields,
    method = $bindable(),
    hours = $bindable(null),
    percent = $bindable(null),
    circles = $bindable(null),
    result = $bindable(null),
  }: {
    system: CalculatorSystem & { id: number; name: string }
    /** The fields watered, whose acres spread run hours */
    fields: Field[]
    method?: CalculatorMethod
    hours?: number | null
    percent?: number | null
    circles?: number | null
    result?: number | null
  } = $props()

  const uid = $props.id()
  const units = $derived(currentUnits())
  const methods = $derived(calculatorMethods(system))
  const noun = $derived(circleNoun(system.kind))
  // The first way it offers, unless the page keeps one
  if (!method) method = untrack(() => calculatorMethods(system)[0])

  // Typed here; blank uses the system's
  let gpm = $state<number | null>(null)
  let depthAt100 = $state<number | null>(null)
  let saveToSystem = $state(true)
  const watered = $derived(fields)
  const noArea = $derived(watered.filter((field) => field.acres === null).map((field) => field.name))
  const acres = $derived(watered.reduce((sum, field) => sum + (field.acres ?? 0), 0))
  const usedGpm = $derived(gpm ?? system.pump_capacity_gpm)
  const usedDepth = $derived(depthAt100 ?? system.inches_at_100)
  /** What's wrong with a typed value, or null: past its range (CALCULATOR_LIMITS) */
  function rangeProblem(
    label: string,
    value: number | null,
    limit: { min?: number; max: number },
    show: (value: number) => string,
  ): string | null {
    const out = outOfRange(value, limit)
    if (!out) return null
    if (limit.min !== undefined) return `${label} must be from ${show(limit.min)} to ${show(limit.max)}`
    return out === 'low' ? `${label} must be more than 0` : `${label} must be at most ${show(limit.max)}`
  }
  const circlesLabel = $derived(system.kind === 'linear' ? 'Passes' : 'Circles')
  const problems = $derived(
    (method === 'hours'
      ? [
          rangeProblem('Pump capacity', gpm, LIMITS.gpm, (v) => units.format('flow', v)),
          rangeProblem('Hours', hours, LIMITS.hours, String),
        ]
      : [
          rangeProblem('Depth at 100%', depthAt100, LIMITS.inchesAt100, (v) => units.format('depth', v)),
          rangeProblem('Timer', percent, LIMITS.percent, (v) => `${v}%`),
          rangeProblem(circlesLabel, circles, LIMITS.circles, String),
        ]
    ).filter((problem) => problem !== null),
  )
  const exact = $derived(
    problems.length
      ? null
      : method === 'hours'
        ? hoursInches(
            usedGpm,
            hours,
            watered.map((field) => field.acres),
          )
        : percentInches(usedDepth, percent, circles),
  )
  // As it's shown here, so what's saved is what's seen
  const inches = $derived.by(() => {
    if (exact === null) return null
    const parsed = units.parse('depth', units.format('depth', exact, { unit: false }))
    return parsed.ok ? parsed.value : null
  })
  // More than a day's irrigation could be: a typo, or another unit
  const tooMuch = $derived(inches !== null && inches > LIMITS.inches.max)

  // A value typed that isn't the system's, and could be saved as its own
  const newGpm = $derived(
    method === 'hours' && gpm !== null && !outOfRange(gpm, LIMITS.gpm) && gpm !== system.pump_capacity_gpm ? gpm : null,
  )
  const newDepth = $derived(
    method === 'percent' &&
      depthAt100 !== null &&
      !outOfRange(depthAt100, LIMITS.inchesAt100) &&
      depthAt100 !== system.inches_at_100
      ? depthAt100
      : null,
  )

  $effect(() => {
    result = inches !== null && !tooMuch ? inches : null
  })

  /** Saves a pump capacity or depth at 100% typed here as the system's, when asked to */
  export function saveEquipment() {
    if (!saveToSystem || (newGpm === null && newDepth === null)) return
    const values = newGpm !== null ? { pump_capacity_gpm: newGpm } : { inches_at_100: newDepth }
    // Not a GET, so a page's unsaved-changes guard lets it through; preserveState keeps what's typed
    router.patch(systems.equipment(system.id).url, { system: values }, { preserveState: true, preserveScroll: true })
  }

  const names: Record<CalculatorMethod, string> = { hours: 'Run hours', percent: '% timer' }
  // The operators and result sit beside the boxes, level with them
  const beside = 'flex h-10.5 items-center text-sm text-ink-muted sm:h-9.5'
  const notSet = 'not set'
</script>

{#snippet answer()}
  <span class="flex h-10.5 items-center gap-1.5 text-sm sm:h-9.5" aria-live="polite">
    <span class="text-ink-muted" aria-hidden="true">=</span>
    {#if inches === null}
      <span class="text-ink-muted">{`—— ${units.label('depth')}`}</span>
    {:else}
      <strong class="font-semibold tabular-nums {tooMuch ? 'text-status-irrigate-ink' : 'text-ink'}"
        >{units.format('depth', inches)}</strong
      >
    {/if}
  </span>
{/snippet}

{#snippet trouble()}
  <!-- The live region stays put, so what appears in it is announced; a role on the list would drop its items' -->
  <div role="status">
    {#if problems.length || tooMuch}
      <ul class="space-y-0.5 text-xs text-status-irrigate-ink">
        {#each problems as problem (problem)}<li>{problem}</li>{/each}
        {#if tooMuch}<li>
            {`That's more than ${units.format('depth', LIMITS.inches.max, { digits: 0 })} in a day: check the numbers.`}
          </li>{/if}
      </ul>
    {/if}
  </div>
{/snippet}

<div class="space-y-4">
  {#if methods.length > 1}
    <div
      class="flex w-fit overflow-hidden rounded-md border border-line text-sm"
      role="radiogroup"
      aria-label="Work it out from"
    >
      {#each methods as option (option)}
        <label
          class="relative flex cursor-pointer items-center px-3 py-1.5 whitespace-nowrap has-checked:bg-brand-600 has-checked:text-white has-focus-visible:outline-2 has-focus-visible:outline-brand-500 dark:has-checked:text-surface"
        >
          <input type="radio" class="sr-only" name="{uid}-method" value={option} bind:group={method} />
          {names[option]}
        </label>
      {/each}
    </div>
  {/if}

  {#if method === 'hours'}
    <div class="flex flex-wrap items-end gap-x-2 gap-y-2">
      <div class="w-36">
        <NumberField
          id="{uid}-gpm"
          label="Pump capacity"
          quantity="flow"
          bind:value={gpm}
          placeholder={system.pump_capacity_gpm === null ? notSet : units.input('flow', system.pump_capacity_gpm)}
        />
      </div>
      <span class={beside} aria-hidden="true">×</span>
      <div class="w-28">
        <NumberField id="{uid}-hours" label="Hours it ran" unitLabel="h" bind:value={hours} />
      </div>
      {@render answer()}
    </div>
    {@render trouble()}
    <p class="text-xs text-ink-muted">
      {noArea.length
        ? `Run hours need an area for ${noArea.join(', ')}: add it in Setup, or enter inches.`
        : usedGpm === null
          ? `Spread over ${Number(acres.toFixed(1))} acres. Enter the pump capacity to work it out.`
          : `Spread over the ${Number(acres.toFixed(1))} acres watered.`}
    </p>
    {#if newGpm !== null}
      <label class="flex items-start gap-2 text-sm">
        <input type="checkbox" class="mt-0.5 rounded" bind:checked={saveToSystem} />
        {`Save ${units.format('flow', newGpm)} as ${system.name}'s pump capacity`}
      </label>
    {/if}
  {:else}
    <div class="flex flex-wrap items-end gap-x-2 gap-y-2">
      <div class="w-32">
        <NumberField
          id="{uid}-depth"
          label="Depth at 100%"
          quantity="depth"
          bind:value={depthAt100}
          placeholder={system.inches_at_100 === null ? notSet : units.input('depth', system.inches_at_100)}
        />
      </div>
      <span class={beside} aria-hidden="true">at</span>
      <div class="w-24">
        <NumberField id="{uid}-percent" label="Timer" unitLabel="%" bind:value={percent} />
      </div>
      <span class={beside} aria-hidden="true">×</span>
      <div class="w-24">
        <NumberField id="{uid}-circles" label={circlesLabel} bind:value={circles} blankValue={1} />
      </div>
      {@render answer()}
    </div>
    {@render trouble()}
    <p class="text-xs text-ink-muted">
      The <Term id="percent_timer">percent timer</Term>{`: the depth a ${noun} puts on at 100% × 100 ÷ the setting.`}
    </p>
    {#if newDepth !== null}
      <label class="flex items-start gap-2 text-sm">
        <input type="checkbox" class="mt-0.5 rounded" bind:checked={saveToSystem} />
        {`Save ${units.format('depth', newDepth)} as ${system.name}'s depth at 100%`}
      </label>
    {/if}
  {/if}
</div>
