<script lang="ts">
  import Button from '@/lib/components/Button.svelte'
  import CalculatorIcon from '@/lib/components/CalculatorIcon.svelte'
  import Dialog from '@/lib/components/Dialog.svelte'
  import IrrigationCalculator from '@/lib/components/IrrigationCalculator.svelte'
  import { type CalculatorMethod, type CalculatorSystem, calculatorMethods } from '@/lib/irrigation'
  import { formatDate } from '@/lib/dates'
  import { count } from '@/lib/text'

  // The irrigation calculator (D15), on an irrigation system's row: a
  // button opening the calculator (IrrigationCalculator) in a dialog, with the fields to apply it to.
  // Apply hands the inches to the page (saving equipment typed there, if asked), which
  // fills the boxes of the fields chosen. The week view gives it its days to choose from, each with
  // its fields, and fills the day's cell (no choice of fields: that's the day page's).
  type Field = { id: number; name: string; acres: number | null }
  let {
    system,
    fields = [],
    date,
    days,
    onapply,
  }: {
    system: CalculatorSystem & { id: number; name: string }
    /** The fields watered (the chosen ones' acres spread run hours), all chosen to start */
    fields?: Field[]
    /** The day it's for (ISO), named in the title; with days, the one chosen to start */
    date: string
    /** The days to choose from, each with the fields it fills (the week view) */
    days?: { date: string; fields: Field[] }[]
    onapply: (inches: number, fieldIds: number[], date: string) => void
  } = $props()

  const uid = $props.id()
  const methods = $derived(calculatorMethods(system))

  let open = $state(false)
  let method = $state<CalculatorMethod>('hours')
  // Kept between openings, as the page's
  let hours = $state<number | null>(null)
  let percent = $state<number | null>(null)
  let circles = $state<number | null>(null)
  let inches = $state<number | null>(null)
  let calculator = $state<ReturnType<typeof IrrigationCalculator>>()
  let scope = $state<'all' | 'some'>('all')
  let chosen = $state<number[]>([])
  let day = $state('')
  const dayFields = $derived(days ? (days.find((d) => d.date === day)?.fields ?? []) : fields)

  function start() {
    method = methods[0]
    day = date
    scope = 'all'
    chosen = dayFields.map((field) => field.id)
    open = true
  }

  const watered = $derived(scope === 'all' ? dayFields : dayFields.filter((field) => chosen.includes(field.id)))

  function apply() {
    if (inches === null || !watered.length) return
    onapply(
      inches,
      watered.map((field) => field.id),
      day,
    )
    calculator?.saveEquipment()
    open = false
  }

  const names: Record<CalculatorMethod, string> = { hours: 'Run hours', percent: '% timer' }
</script>

<button
  type="button"
  class="relative flex size-7 items-center justify-center rounded text-ink-muted hover:bg-surface hover:text-ink"
  aria-label="Work out {system.name}'s irrigation"
  title="Work out inches from {methods.map((m) => names[m].toLowerCase()).join(' or ')}"
  onclick={start}
>
  <CalculatorIcon />
</button>

<Dialog
  bind:open
  title="Irrigation for {system.name} on {formatDate(day)}"
  description="Work out the inches put on, then apply them."
>
  <div class="space-y-4">
    {#if days}
      <div class="flex items-center gap-2 text-sm">
        <label for="{uid}-day" class="font-medium">Day</label>
        <select id="{uid}-day" class="rounded-md py-1.5 text-sm" bind:value={day} onchange={() => (scope = 'all')}>
          {#each days as option (option.date)}
            <option value={option.date}>{formatDate(option.date, { weekday: true })}</option>
          {/each}
        </select>
      </div>
    {/if}
    <IrrigationCalculator
      bind:this={calculator}
      {system}
      fields={watered}
      bind:method
      bind:hours
      bind:percent
      bind:circles
      bind:result={inches}
    />

    <fieldset class="space-y-2 border-t border-line pt-4">
      <legend class="sr-only">Apply to</legend>
      <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
        <span class="font-medium" aria-hidden="true">Apply to</span>
        {#if days}
          <span>{dayFields.map((field) => field.name).join(', ')}</span>
        {:else if dayFields.length > 1}
          <label class="flex items-center gap-1.5">
            <input type="radio" name="{uid}-scope" value="all" bind:group={scope} />
            All fields
          </label>
          <label class="flex items-center gap-1.5">
            <input type="radio" name="{uid}-scope" value="some" bind:group={scope} />
            Specific fields
          </label>
        {:else}
          <span>{dayFields[0]?.name}</span>
        {/if}
      </div>
      {#if scope === 'some'}
        <div class="flex flex-wrap gap-x-4 gap-y-1 pl-1">
          {#each dayFields as field (field.id)}
            <label class="flex items-center gap-1.5 text-sm">
              <input type="checkbox" class="rounded" value={field.id} bind:group={chosen} />
              {field.name}
            </label>
          {/each}
        </div>
      {/if}
    </fieldset>

    <div class="flex justify-end gap-3">
      <Button variant="secondary" onclick={() => (open = false)}>Cancel</Button>
      <Button onclick={apply} disabled={inches === null || !watered.length}>
        {dayFields.length > 1 && watered.length < dayFields.length
          ? `Apply to ${count(watered.length, 'field')}`
          : 'Apply'}
      </Button>
    </div>
  </div>
</Dialog>
