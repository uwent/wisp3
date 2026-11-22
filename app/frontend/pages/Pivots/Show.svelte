<script lang="ts">
  import { Form, Link, page, router } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import IrrigationAmount from '@/lib/components/IrrigationAmount.svelte'
  import IrrigationUnitSwitch from '@/lib/components/IrrigationUnitSwitch.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import Term from '@/lib/components/Term.svelte'
  import ZoneWeather from '@/lib/components/ZoneWeather.svelte'
  import { currentYear, formatDate, today as todayDate } from '@/lib/dates'
  import { isPoint, KIND_NOUNS, systemName } from '@/lib/geo'
  import { isExample } from '@/lib/permissions'
  import {
    canUseHours,
    canUsePercent,
    circleNoun,
    enteredAs,
    type FieldAmount,
    fieldOverride,
    type FieldSeasons,
    fieldsOn,
    hasTimer,
    type IrrigationUnit,
    percentInches,
    savedAmount,
    unitsFor,
  } from '@/lib/irrigation'
  import { currentUnits } from '@/lib/units'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { dashboard, fields as fieldRoutes, pivotIrrigations, pivots } from '@/routes'
  import type { ForecastDay, Pivot, PivotIrrigation } from '@/types/serializers'

  let {
    pivot,
    farm,
    year,
    irrigations,
    field_seasons,
    field_amounts,
    weather_zone,
    forecast,
  }: {
    pivot: Pivot
    farm: { id: number; name: string }
    year: number
    irrigations: PivotIrrigation[]
    field_seasons: FieldSeasons[]
    /** Fields' own irrigation by date and field, which replaces the system's */
    field_amounts: Record<string, Record<string, FieldAmount>>
    weather_zone: { id: number; name: string; location: string } | null
    forecast: ForecastDay[]
  } = $props()

  const units = $derived(currentUnits())
  // "pivot", "drip block"
  const noun = $derived(KIND_NOUNS[pivot.kind])
  const today = todayDate()

  // The form edits a new irrigation, or an existing one picked from the list
  let editing = $state<PivotIrrigation | null>(null)
  let unit = $state<IrrigationUnit>('inches')
  // The amount in the box shown, from the irrigation being edited, and the circles at a percent
  let amount = $state<number | null>(null)
  let circles = $state<number | null>(null)
  // Each field's own amount, in overrideUnit (blank: the system's), and the fields it's applied to
  let overrides = $state<Record<number, number | null>>({})
  let overrideUnits = $state<Record<number, 'inches' | 'percent'>>({})
  let applied = $state<number[]>([])
  let formKey = $state(0)
  // Adding one on a date that already has an irrigation replaces it (the controller), so say so
  let date = $state(today)
  const existing = $derived(editing ? undefined : irrigations.find((irrigation) => irrigation.date === date))

  // Typed values not yet saved: set by any input, cleared by a save or Cancel
  let dirty = $state(false)
  const unsaved = confirmUnsavedChanges(
    () => dirty,
    () => document.getElementById('irrigation-form'),
  )
  /** Whether what's typed may go: nothing is, or the user says so */
  const mayDrop = () => !dirty || confirm(unsaved.message())

  /** Puts another irrigation (or a new one) in the form; ask: first, if there are unsaved values */
  function edit(irrigation: PivotIrrigation | null, ask = true) {
    if (ask && !mayDrop()) return
    dirty = false
    editing = irrigation
    unit = enteredAs(irrigation)
    amount = savedAmount(irrigation, unit)
    circles = irrigation?.circles ?? null
    date = irrigation?.date ?? today
    loadFields()
    formKey++
  }

  /** The fields' own amounts saved on the form's date, in the unit they're entered in */
  function loadFields() {
    const fields = fieldsOn(field_seasons, date)
    const loaded = fields.map(
      (field) => [field.id, fieldOverride(field_amounts[date]?.[field.id], unit, canUsePercent(pivot))] as const,
    )
    overrides = Object.fromEntries(loaded.map(([id, own]) => [id, own.value]))
    overrideUnits = Object.fromEntries(loaded.map(([id, own]) => [id, own.unit]))
    applied = fields
      .filter((field) => editing?.field_ids == null || editing.field_ids.includes(field.id))
      .map((f) => f.id)
  }
  loadFields()

  function switchUnit(next: IrrigationUnit) {
    unit = next
    amount = savedAmount(editing, next)
    circles = editing?.circles ?? null
    loadFields()
    dirty = true
  }

  // The fields on the system on the form's date: a field moved here or away is on it for the
  // seasons that ran here
  const dayFields = $derived(date ? fieldsOn(field_seasons, date) : pivot.fields)

  /** "All fields", or the fields it applied to; a field's own amount after its name */
  function fieldNames(irrigation: PivotIrrigation) {
    const own = field_amounts[irrigation.date] ?? {}
    const named = (field: FieldSeasons) => {
      const amount = own[field.id]
      if (!amount) return field.name
      const percent = amount.irrigation_pct === null ? '' : ` at ${amount.irrigation_pct}%`
      return `${field.name} (${units.format('depth', amount.irrigation_in)}${percent})`
    }
    const fields = fieldsOn(field_seasons, irrigation.date)
    const ids = irrigation.field_ids
    if (ids === null && !fields.some((field) => own[field.id])) return 'All fields'
    return fields
      .filter((field) => ids === null || ids.includes(field.id))
      .map(named)
      .join(', ')
  }

  /** The system's amount as a field's box shows it, for its placeholder: "40% (pivot's)" */
  function systemFor(fieldUnit: 'inches' | 'percent') {
    const theirs = `${noun}'s`
    if (amount === null) return `the ${theirs}`
    if (unit === 'percent' && fieldUnit === 'percent' && circles === null) return `${amount}% (${theirs})`
    const inches =
      unit === 'inches' ? amount : unit === 'percent' ? percentInches(pivot.inches_at_100, amount, circles) : null
    return inches === null ? `the ${theirs}` : `${units.input('depth', inches)} (${theirs})`
  }

  function remove(irrigation: PivotIrrigation) {
    const own = Object.keys(field_amounts[irrigation.date] ?? {}).length
    const fields = own ? ` and the fields' own amounts that day` : ''
    if (confirm(`Delete the ${formatDate(irrigation.date)} irrigation${fields}?`)) {
      router.delete(pivotIrrigations.destroy({ pivotId: pivot.id, id: irrigation.id }).url, { preserveScroll: true })
    }
  }

  // What it takes to enter the other units, when one is missing
  const missingUnits = $derived(
    [
      !canUseHours(pivot) &&
        `To enter run hours, add this ${noun}'s ${isPoint(pivot.kind) ? 'flow' : 'pump capacity'} and an area for each field.`,
      hasTimer(pivot.kind) &&
        !canUsePercent(pivot) &&
        `To enter the percent timer's setting, add the depth a ${circleNoun(pivot.kind)} puts on at 100%.`,
    ]
      .filter(Boolean)
      .join(' '),
  )

  // The example farm (PLAN.md G.8) is only viewed
  const readOnly = $derived(isExample(page.props))
</script>

<svelte:head><title>{systemName(pivot)} · WISP</title></svelte:head>

<div class="flex flex-wrap items-end justify-between gap-3">
  <div>
    <Link href={dashboard.show()} class="text-sm text-brand-600 hover:underline">← Dashboard</Link>
    <h1 class="text-2xl font-semibold">
      <span class="font-normal text-ink-muted">Irrigation system:</span>
      {systemName(pivot)}
    </h1>
    <p class="text-sm text-ink-muted">
      Farm: {farm.name} · Fields:
      {#each pivot.fields as field, i (field.id)}{i ? ', ' : ''}<Link
          href={fieldRoutes.show(field.id)}
          class="text-brand-600 underline underline-offset-2">{field.name}</Link
        >{:else}no fields yet{/each}
      {#if !readOnly}
        · <Link href={pivots.edit(pivot.id)} class="text-brand-600 underline underline-offset-2">Edit {noun}</Link>
      {/if}
    </p>
  </div>
  <select
    class="rounded-md text-sm"
    aria-label="Season"
    value={year}
    onchange={(e) => {
      if (!mayDrop()) {
        e.currentTarget.value = String(year)
        return
      }
      dirty = false
      router.get(pivots.show(pivot.id).url, { year: e.currentTarget.value })
    }}
  >
    {#each [year - 2, year - 1, year, year + 1] as y (y)}<option value={y}>{y}</option>{/each}
  </select>
</div>

{#key formKey}
  <section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6" hidden={readOnly}>
    <div>
      <h2 class="text-lg font-medium">{editing ? `Edit ${formatDate(editing.date)}` : 'Add an irrigation'}</h2>
      <p class="text-sm text-ink-muted">
        Enter each irrigation once here and it applies to the {noun}'s fields. A field's own entry for a day replaces
        it.
      </p>
    </div>
    <Form
      id="irrigation-form"
      action={editing
        ? pivotIrrigations.update({ pivotId: pivot.id, id: editing.id })
        : pivotIrrigations.create(pivot.id)}
      class="space-y-4"
      options={{ preserveScroll: true }}
      oninput={() => (dirty = true)}
      onchange={() => (dirty = true)}
      onSuccess={() => edit(null, false)}
    >
      {#snippet children({ errors, processing })}
        <div class="grid gap-4 sm:grid-cols-3">
          <div class="space-y-1">
            <label for="irrigation-date" class="block text-sm font-medium">Date</label>
            <input
              id="irrigation-date"
              type="date"
              name="pivot_irrigation[date]"
              bind:value={date}
              onchange={loadFields}
              required
              class="block w-full rounded-md text-sm"
            />
            {#if errors.date}<p class="text-sm text-status-irrigate-ink">{errors.date}</p>{/if}
            {#if existing}
              <p class="text-sm" role="status">
                {formatDate(existing.date)} already has {units.format('depth', existing.applied_inches)} of irrigation. Saving
                will replace it.
                <button type="button" class="text-brand-600 underline" onclick={() => edit(existing)}
                  >Edit that one instead</button
                >
              </p>
            {/if}
          </div>
          <div class="space-y-2 sm:col-span-2">
            <IrrigationUnitSwitch
              name="irrigation-unit"
              label="Enter the irrigation as"
              units={unitsFor(pivot)}
              {unit}
              onchange={switchUnit}
            />
            <IrrigationAmount
              name="pivot_irrigation"
              {unit}
              bind:value={amount}
              bind:circles
              kind={pivot.kind}
              inchesAt100={pivot.inches_at_100}
              errors={{
                inches: errors.inches,
                run_hours: errors.run_hours,
                percent_timer: errors.percent_timer,
                circles: errors.circles,
              }}
            />
            {#if missingUnits}
              <p class="text-xs text-ink-muted">
                {missingUnits}
                {#if !readOnly}<Link href={pivots.edit(pivot.id)} class="text-brand-600 underline underline-offset-2"
                    >Edit {noun}</Link
                  >{/if}
              </p>
            {/if}
          </div>
        </div>
        {#if dayFields.length > 1}
          {@const anyPercent = dayFields.some((field) => overrideUnits[field.id] === 'percent')}
          <fieldset class="space-y-2">
            <legend class="text-sm font-medium">Applied to</legend>
            <p class="text-xs text-ink-muted">
              Leave a field's amount blank for the {noun}'s, or give it its own{#if anyPercent}{', as the '}<Term
                  id="percent_timer">percent timer</Term
                >{' setting its sector ran at'}{/if}.
            </p>
            <input type="hidden" name="pivot_irrigation[field_ids][]" value="" />
            <table class="text-sm">
              <tbody>
                {#each dayFields as field (field.id)}
                  {@const on = applied.includes(field.id)}
                  {@const base = `pivot_irrigation[field_amounts][${field.id}]`}
                  {@const own = overrides[field.id] ?? null}
                  {@const byPercent = overrideUnits[field.id] === 'percent'}
                  <tr class="align-top">
                    <td class="py-1 pr-4">
                      <label class="flex items-center gap-2 py-2">
                        <input
                          type="checkbox"
                          name="pivot_irrigation[field_ids][]"
                          value={field.id}
                          bind:group={applied}
                          class="rounded"
                        />
                        {field.name}
                      </label>
                    </td>
                    <td class="w-32 py-1 pr-2">
                      {#if on}
                        <NumberField
                          hideLabel
                          label="{field.name}'s own amount{byPercent ? ' (percent timer)' : ''}"
                          name="{base}[{byPercent ? 'irrigation_pct' : 'irrigation_in'}]"
                          quantity={byPercent ? undefined : 'depth'}
                          bind:value={overrides[field.id]}
                          placeholder={systemFor(overrideUnits[field.id])}
                          error={errors[`fields.${field.id}.irrigation_in`] ??
                            errors[`fields.${field.id}.irrigation_pct`]}
                        />
                      {/if}
                      <!-- A percent saved before stays unless the inches change (DailyEntry.record) -->
                      {#if byPercent || !on}<input type="hidden" name="{base}[irrigation_in]" value="" />{/if}
                      {#if !on}
                        <input type="hidden" name="{base}[irrigation_pct]" value="" />
                        <span class="block py-2 text-xs text-ink-muted">none</span>
                      {/if}
                    </td>
                    <td class="py-1 text-xs text-ink-muted">
                      {#if on && byPercent && own !== null}
                        <span class="block py-2"
                          >% = {units.format('depth', percentInches(pivot.inches_at_100, own))}</span
                        >
                      {:else if on && own !== null}
                        <span class="block py-2">{units.label('depth')}</span>
                      {/if}
                    </td>
                  </tr>
                {/each}
              </tbody>
            </table>
            {#if errors.field_ids}<p class="text-sm text-status-irrigate-ink">{errors.field_ids}</p>{/if}
          </fieldset>
        {/if}
        <div class="space-y-1">
          <label for="irrigation-notes" class="block text-sm font-medium">Notes</label>
          <input
            id="irrigation-notes"
            name="pivot_irrigation[notes]"
            value={editing?.notes ?? ''}
            class="block w-full rounded-md text-sm"
          />
        </div>
        <div class="flex gap-2">
          <Button type="submit" disabled={processing}>Save irrigation</Button>
          {#if editing}<Button variant="secondary" onclick={() => edit(null, false)}>Cancel</Button>{/if}
        </div>
      {/snippet}
    </Form>
  </section>
{/key}

{#if irrigations.length}
  <div class="flex justify-end text-sm">
    <a
      href={pivotIrrigations.index(pivot.id, { query: { year } }).url}
      class="rounded-md border border-line bg-surface-raised px-3 py-1.5 hover:bg-surface"
      download
    >
      Export {year} irrigation (CSV)
    </a>
  </div>
{/if}

<section class="relative overflow-x-auto rounded-lg border border-line bg-surface-raised">
  {#if irrigations.length === 0}
    <p class="p-6 text-center text-sm text-ink-muted">No irrigation entered for {year} yet.</p>
  {:else}
    <table class="w-full text-sm">
      <thead class="border-b border-line text-left text-xs text-ink-muted">
        <tr>
          <th class="px-4 py-2 font-medium">Date</th>
          <th class="px-4 py-2 text-right font-medium">Amount</th>
          <th class="px-4 py-2 font-medium">Applied to</th>
          <th class="px-4 py-2 font-medium">Notes</th>
          {#if !readOnly}<th class="px-4 py-2"><span class="sr-only">Actions</span></th>{/if}
        </tr>
      </thead>
      <tbody class="divide-y divide-line">
        {#each irrigations as irrigation (irrigation.id)}
          <tr>
            <td class="px-4 py-2 whitespace-nowrap">{formatDate(irrigation.date, { weekday: true })}</td>
            <td class="px-4 py-2 text-right whitespace-nowrap tabular-nums">
              {units.format('depth', irrigation.applied_inches)}
              {#if irrigation.percent_timer !== null && irrigation.inches === null}<span
                  class="block text-xs text-ink-muted"
                  >{irrigation.percent_timer}% timer{irrigation.circles === null
                    ? ''
                    : `, ${irrigation.circles} ${circleNoun(pivot.kind)}s`}</span
                >{:else if irrigation.inches === null}<span class="block text-xs text-ink-muted"
                  >{irrigation.run_hours} hours</span
                >{/if}
            </td>
            <td class="px-4 py-2">{fieldNames(irrigation)}</td>
            <td class="px-4 py-2 text-ink-muted">{irrigation.notes ?? ''}</td>
            {#if !readOnly}
              <td class="px-4 py-2 text-right whitespace-nowrap">
                <Button variant="ghost" class="px-2 py-1 text-xs" onclick={() => edit(irrigation)}>Edit</Button>
                <Button variant="danger-ghost" class="px-2 py-1 text-xs" onclick={() => remove(irrigation)}
                  >Delete</Button
                >
              </td>
            {/if}
          </tr>
        {/each}
      </tbody>
    </table>
  {/if}
</section>

<ZoneWeather zone={weather_zone} {forecast} {units} query={year === currentYear() ? {} : { year }} />
