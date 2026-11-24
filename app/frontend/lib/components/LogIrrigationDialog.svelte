<script lang="ts">
  import { Form } from '@inertiajs/svelte'

  import Button from './Button.svelte'
  import Dialog from './Dialog.svelte'
  import CalculatorIcon from './CalculatorIcon.svelte'
  import IrrigationCalculator from './IrrigationCalculator.svelte'
  import NumberField from './NumberField.svelte'
  import { addDays, formatDate } from '../dates'
  import { fieldsOn, rainfedOn } from '../irrigation'
  import { systemName } from '../geo'
  import { inSeason, lastIrrigationLine, type LogSystemProps, replacing } from '../logIrrigation'
  import type { OverviewSystem } from '../overview'
  import { nextRainLine } from '../rain'
  import type { Units } from '../units'
  import { systemIrrigations } from '@/routes'
  import type { ForecastDay } from '@/types/serializers'

  // Log a system's irrigation from the dashboard, for the common case of
  // one system that ran: a day (yesterday or today, or another within dates), an amount (with the
  // calculator) on the fields chosen, or an amount each. Saved through SystemIrrigationsController
  // (D15: each field's own inches; fields not sent are left as they are). It says when the system
  // last irrigated and when rain is next, and warns before replacing a day's irrigation. field:
  // opened from a field's card ("Irrigated since …?"), which starts as the only one chosen.
  let {
    open = $bindable(false),
    system,
    field = null,
    rain,
    dates,
    today,
    units,
  }: {
    open?: boolean
    system: OverviewSystem & LogSystemProps
    field?: number | null
    /** The week's rain in the system's weather zone */
    rain: ForecastDay[]
    /** The day it starts on, and the first and last it offers */
    dates: { default: string; from: string; to: string }
    today: string
    units: Units
  } = $props()

  const uid = $props.id()
  let date = $state('')
  let amount = $state<number | null>(null)
  let each = $state(false)
  let amounts = $state<Record<number, number | null>>({})
  let chosen = $state<number[]>([])
  // Boxes ticked by hand stay as they are when the day changes
  let picked = $state(false)
  // The calculator, open under the amount, fills it as it changes (over the fields checked, or all
  // of them before any is). Kept while closed (hidden), so what's typed in it stays and a pump
  // capacity or depth it offers to save is saved with the irrigation. worked is cleared when it
  // opens, so an earlier result never fills the amount.
  let working = $state(false)
  let worked = $state<number | null>(null)
  let calculator = $state<ReturnType<typeof IrrigationCalculator>>()

  /** The fields in season on the day, but not a rainfed one (D17), or the one the dialog was opened for */
  const seasonal = (day: string) =>
    field !== null
      ? [field]
      : fieldsOn(system.log_fields, day)
          .filter((f) => inSeason(f, day) && !rainfedOn(f, day))
          .map((f) => f.id)

  // Fresh each time it opens
  let wasOpen = false
  $effect.pre(() => {
    if (open && !wasOpen) {
      date = dates.default
      amount = null
      each = false
      amounts = {}
      chosen = seasonal(date)
      picked = false
      working = false
      worked = null
    }
    wasOpen = open
  })

  function setDate(day: string) {
    date = day
    if (!picked) chosen = seasonal(day)
    // Only fields on the system that day can be chosen
    else chosen = chosen.filter((id) => fieldsOn(system.log_fields, day).some((f) => f.id === id))
  }

  function toggleCalculator() {
    working = !working
    worked = null
  }

  function toggle(id: number, on: boolean) {
    picked = true
    chosen = on ? [...chosen, id] : chosen.filter((other) => other !== id)
    // A field checked with an amount each starts with the shared amount, as the others did
    if (on && each) amounts[id] = amounts[id] ?? amount
  }

  const yesterday = $derived(addDays(today, -1))
  // The system's fields that day: a field whose season that day ran on another system isn't its
  // (fieldsOn; SystemIrrigationsController#create saves only these)
  const fields = $derived(fieldsOn(system.log_fields, date))
  const chosenFields = $derived(fields.filter((f) => chosen.includes(f.id)))
  /** What each chosen field gets: the shared amount, or its own box */
  const sent = $derived(
    chosenFields
      .map((f) => ({ id: f.id, inches: each ? (amounts[f.id] ?? null) : amount }))
      .filter((entry) => entry.inches !== null),
  )
  const warning = $derived(
    replacing(
      system.recent_irrigation,
      date,
      chosenFields.filter((f) => sent.some((entry) => entry.id === f.id)),
      units,
    ),
  )
  const inRange = $derived(date >= dates.from && date <= dates.to)
  const lastLine = $derived(lastIrrigationLine(system.fields, today, units))
  const rainLine = $derived(nextRainLine(rain, today, units))

  $effect(() => {
    if (working && !each && worked !== null) amount = worked
  })

  function startEach() {
    each = !each
    if (each) for (const f of chosenFields) amounts[f.id] = amounts[f.id] ?? amount
  }
</script>

<Dialog bind:open title="Log irrigation on {systemName(system)}" guard>
  <Form
    action={systemIrrigations.create(system.id)}
    class="space-y-4"
    options={{ preserveScroll: true }}
    onSuccess={() => {
      calculator?.saveEquipment()
      open = false
    }}
  >
    {#snippet children({ errors, processing })}
      {@const errs = errors as Record<string, string | string[]>}
      <input type="hidden" name="irrigation[date]" value={date} />
      {#each sent as entry (entry.id)}
        <input type="hidden" name="irrigation[fields][{entry.id}]" value={entry.inches} />
      {/each}

      <div class="space-y-0.5 text-sm text-ink-muted">
        <p>{lastLine}</p>
        {#if rainLine}<p>{rainLine}</p>{/if}
      </div>

      <div class="space-y-1">
        <span class="block text-sm font-medium" id="{uid}-date">Date</span>
        <div class="flex flex-wrap items-center gap-2" role="group" aria-labelledby="{uid}-date">
          {#each [{ day: yesterday, name: 'Yesterday' }, { day: today, name: 'Today' }] as option (option.day)}
            <button
              type="button"
              class="rounded-md border px-3 py-1.5 text-sm {date === option.day
                ? 'border-brand-600 bg-brand-600 text-white dark:text-surface'
                : 'border-line bg-surface-raised hover:bg-surface'}"
              aria-pressed={date === option.day}
              onclick={() => setDate(option.day)}>{option.name}</button
            >
          {/each}
          <input
            type="date"
            class="rounded-md text-sm"
            aria-label="Choose a date"
            min={dates.from}
            max={dates.to}
            value={date}
            onchange={(e) => setDate(e.currentTarget.value)}
          />
        </div>
        {#if !inRange}
          <p class="text-sm text-status-irrigate-ink">
            Choose a day from {formatDate(dates.from)} to {formatDate(dates.to)}; for earlier days use daily entry's
            week.
          </p>
        {/if}
        {#if errs.date}<p class="text-sm text-status-irrigate-ink">{errs.date}</p>{/if}
      </div>

      {#if !each}
        <div class="w-48">
          <NumberField
            id="{uid}-amount"
            label="Amount"
            quantity="depth"
            precision={units.digits('depth')}
            bind:value={amount}
          >
            {#snippet trailing()}
              <button
                type="button"
                class="relative flex size-7 items-center justify-center rounded-sm text-ink-muted hover:bg-surface hover:text-ink {working
                  ? 'bg-surface text-ink'
                  : ''}"
                aria-label="Work out {system.name}'s irrigation"
                aria-expanded={working}
                aria-controls="{uid}-calculator"
                onclick={toggleCalculator}><CalculatorIcon /></button
              >
            {/snippet}
          </NumberField>
        </div>
      {/if}
      <div id="{uid}-calculator" class="rounded-md border border-line bg-surface p-3" hidden={!working || each}>
        <IrrigationCalculator
          bind:this={calculator}
          {system}
          fields={chosenFields.length ? chosenFields : fields}
          bind:result={worked}
        />
      </div>

      <fieldset class="space-y-2">
        <legend class="text-sm font-medium">Fields</legend>
        {#if !fields.length}
          <p class="text-sm text-ink-muted">This system has no fields yet.</p>
        {/if}
        <ul class="space-y-1.5">
          {#each fields as f (f.id)}
            {@const on = chosen.includes(f.id)}
            <li class="flex min-h-9 items-center gap-3">
              <label class="flex min-w-0 flex-1 items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  class="rounded-sm"
                  checked={on}
                  onchange={(e) => toggle(f.id, e.currentTarget.checked)}
                />
                <!-- The note under the name, so a phone's narrow row keeps the name whole -->
                <span class="min-w-0 leading-tight">
                  <span class="block truncate">{f.name}</span>
                  {#if !inSeason(f, date)}<span class="block text-xs text-ink-muted">no crop that day</span>
                  {:else if rainfedOn(f, date)}<span class="block text-xs text-ink-muted">Rainfed</span>{/if}
                </span>
              </label>
              {#if each && on}
                <div class="flex w-32 shrink-0 items-center gap-1.5">
                  <NumberField
                    hideLabel
                    id="{uid}-field-{f.id}"
                    label="Irrigation on {f.name}"
                    quantity="depth"
                    precision={units.digits('depth')}
                    bind:value={() => amounts[f.id] ?? null, (value) => (amounts[f.id] = value)}
                  />
                  <span class="text-sm text-ink-muted" aria-hidden="true">{units.label('depth')}</span>
                </div>
              {/if}
            </li>
            {#if errs[`fields.${f.id}.irrigation_in`]}
              <li class="text-sm text-status-irrigate-ink">{f.name}: {errs[`fields.${f.id}.irrigation_in`]}</li>
            {/if}
          {/each}
        </ul>
        {#if fields.length > 1}
          <button type="button" class="text-sm text-brand-600 underline underline-offset-2" onclick={startEach}
            >{each ? 'The same amount on every field' : 'A different amount on each field'}</button
          >
        {/if}
      </fieldset>

      <!-- The live region stays put, so the warning is announced when it appears -->
      <div role="status">
        {#if warning}
          <p class="rounded-md bg-status-caution/15 px-3 py-2 text-sm">{warning}. Saving replaces it.</p>
        {/if}
      </div>

      <!-- No Cancel: ✕ and Escape close it, asking first when something's typed (guard) -->
      <div class="flex justify-end border-t border-line pt-4">
        <Button type="submit" disabled={processing || !sent.length || !inRange}>Save irrigation</Button>
      </div>
    {/snippet}
  </Form>
</Dialog>
