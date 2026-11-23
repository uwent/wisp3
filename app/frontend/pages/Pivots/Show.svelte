<script lang="ts">
  import { Form, Link, page, router } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import IrrigationCalculatorDialog from '@/lib/components/IrrigationCalculatorDialog.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import ZoneWeather from '@/lib/components/ZoneWeather.svelte'
  import { currentYear, formatDate, today as todayDate } from '@/lib/dates'
  import { KIND_NOUNS, systemName } from '@/lib/geo'
  import { common, type FieldSeasons, fieldsOn } from '@/lib/irrigation'
  import { isExample } from '@/lib/permissions'
  import { currentUnits } from '@/lib/units'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { dashboard, fields as fieldRoutes, pivotIrrigations, pivots } from '@/routes'
  import type { ForecastDay, Pivot } from '@/types/serializers'

  /** A day's irrigation: each field's amount (D15: stored per field) */
  type IrrigationDay = { date: string; fields: Record<string, number> }

  let {
    pivot,
    farm,
    year,
    irrigations,
    field_seasons,
    weather_zone,
    forecast,
  }: {
    pivot: Pivot
    farm: { id: number; name: string }
    year: number
    /** The year's irrigation by date, newest first */
    irrigations: IrrigationDay[]
    field_seasons: FieldSeasons[]
    weather_zone: { id: number; name: string; location: string } | null
    forecast: ForecastDay[]
  } = $props()

  const units = $derived(currentUnits())
  // "pivot", "drip block"
  const noun = $derived(KIND_NOUNS[pivot.kind])
  const today = todayDate()

  // The form edits a new irrigation, or a day's picked from the list: the date and each field's amount
  let editing = $state<IrrigationDay | null>(null)
  let date = $state(today)
  let amounts = $state<Record<number, number | null>>({})
  let formKey = $state(0)
  // Adding one on a date that already has irrigation replaces it, so say so
  const existing = $derived(
    editing?.date === date ? undefined : irrigations.find((irrigation) => irrigation.date === date),
  )

  // Typed values not yet saved: set by any input, cleared by a save or Cancel
  let dirty = $state(false)
  const unsaved = confirmUnsavedChanges(
    () => dirty,
    () => document.getElementById('irrigation-form'),
  )
  /** Whether what's typed may go: nothing is, or the user says so */
  const mayDrop = () => !dirty || confirm(unsaved.message())

  // The fields on the system on the form's date: a field moved here or away is on it for the
  // seasons that ran here
  const dayFields = $derived(fieldsOn(field_seasons, date))
  const shared = $derived(common(dayFields.map((field) => amounts[field.id] ?? null)))

  /** Puts a day's irrigation (or a new one) in the form; ask: first, if there are unsaved values */
  function edit(irrigation: IrrigationDay | null, ask = true) {
    if (ask && !mayDrop()) return
    dirty = false
    editing = irrigation
    date = irrigation?.date ?? today
    load()
    formKey++
  }

  // What load() put in the boxes, to tell typed amounts from saved ones
  let loaded = ''

  /** Each field's amount saved on the form's date, if any */
  function load() {
    const saved = irrigations.find((irrigation) => irrigation.date === date)?.fields ?? {}
    amounts = Object.fromEntries(fieldsOn(field_seasons, date).map((field) => [field.id, saved[field.id] ?? null]))
    loaded = JSON.stringify(amounts)
  }
  load()

  /**
   * Another date: an irrigation being edited moves there with its amounts, as do amounts typed for
   * a new one (each field still on the system that day keeps its own); untouched boxes show what's
   * saved on the new date
   */
  function changeDate() {
    if (!editing && JSON.stringify(amounts) === loaded) return load()
    const kept = amounts
    amounts = Object.fromEntries(fieldsOn(field_seasons, date).map((field) => [field.id, kept[field.id] ?? null]))
  }

  function fill(ids: number[], value: number | null) {
    for (const id of ids) amounts[id] = value
    dirty = true
  }

  const areas = $derived(Object.fromEntries(pivot.fields.map((field) => [field.id, field.area_acres])))
  const calculatorFields = $derived(
    dayFields.map((field) => ({ id: field.id, name: field.name, acres: areas[field.id] ?? null })),
  )

  /** A day's amount: its fields' shared amount, else "varies" */
  function dayAmount(irrigation: IrrigationDay) {
    const values = Object.values(irrigation.fields)
    return common(values).varies ? 'varies' : units.format('depth', values[0])
  }

  /** "All fields", or the fields watered, each with its amount when they differ */
  function fieldNames(irrigation: IrrigationDay) {
    const fields = fieldsOn(field_seasons, irrigation.date)
    const watered = fields.filter((field) => irrigation.fields[field.id] !== undefined)
    const varies = common(Object.values(irrigation.fields)).varies
    if (!varies && watered.length === fields.length) return 'All fields'
    return watered
      .map((field) => (varies ? `${field.name} (${units.format('depth', irrigation.fields[field.id])})` : field.name))
      .join(', ')
  }

  function remove(irrigation: IrrigationDay) {
    if (confirm(`Delete the ${formatDate(irrigation.date)} irrigation on every field?`)) {
      router.delete(pivotIrrigations.destroy({ pivotId: pivot.id, date: irrigation.date }).url, {
        preserveScroll: true,
      })
    }
  }

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
        Irrigation is each field's own. Typing the {noun}'s amount fills in every field; change any field before saving.
      </p>
    </div>
    <Form
      id="irrigation-form"
      action={pivotIrrigations.create(pivot.id)}
      class="space-y-4"
      options={{ preserveScroll: true }}
      oninput={() => (dirty = true)}
      onchange={() => (dirty = true)}
      onSuccess={() => edit(null, false)}
    >
      {#snippet children({ errors, processing })}
        {@const errs = errors as Record<string, string | string[]>}
        {#if editing}<input type="hidden" name="irrigation[from]" value={editing.date} />{/if}
        {#each dayFields as field (field.id)}
          <input type="hidden" name="irrigation[fields][{field.id}]" value={amounts[field.id] ?? ''} />
        {/each}
        <div class="grid gap-4 sm:grid-cols-3">
          <div class="space-y-1">
            <label for="irrigation-date" class="block text-sm font-medium">Date</label>
            <input
              id="irrigation-date"
              type="date"
              name="irrigation[date]"
              bind:value={date}
              onchange={changeDate}
              required
              class="block w-full rounded-md text-sm"
            />
            {#if errs.date}<p class="text-sm text-status-irrigate-ink">{errs.date}</p>{/if}
            {#if existing}
              <p class="text-sm" role="status">
                {formatDate(existing.date)} already has irrigation. Saving will replace it.
                <button type="button" class="text-brand-600 underline" onclick={() => edit(existing)}
                  >Edit that one instead</button
                >
              </p>
            {/if}
          </div>
          <div class="space-y-2 sm:col-span-2">
            <div class="w-44">
              <NumberField
                id="irrigation-amount"
                label={dayFields.length > 1 ? 'Amount on every field' : 'Amount'}
                quantity="depth"
                precision={units.digits('depth')}
                bind:value={() => shared.value, (value) => fill(Object.keys(amounts).map(Number), value)}
                placeholder={shared.varies ? 'varies' : ''}
                error={dayFields.length === 1 ? errs[`fields.${dayFields[0].id}.irrigation_in`] : undefined}
              >
                {#snippet trailing()}
                  <IrrigationCalculatorDialog
                    system={pivot}
                    fields={calculatorFields}
                    {date}
                    onapply={(inches, ids) => fill(ids, inches)}
                  />
                {/snippet}
              </NumberField>
            </div>
          </div>
        </div>
        {#if dayFields.length > 1}
          <fieldset class="space-y-2">
            <legend class="text-sm font-medium">Each field</legend>
            <p class="text-xs text-ink-muted">Leave a field blank if it wasn't watered.</p>
            <table class="text-sm">
              <tbody>
                {#each dayFields as field (field.id)}
                  <tr class="align-top">
                    <td class="py-1 pr-4">
                      <!-- The box is named by its own (hidden) label, "Irrigation on North" -->
                      <span class="block py-2" aria-hidden="true">{field.name}</span>
                    </td>
                    <td class="w-36 py-1">
                      <NumberField
                        hideLabel
                        id="irrigation-field-{field.id}"
                        label="Irrigation on {field.name}"
                        quantity="depth"
                        precision={units.digits('depth')}
                        bind:value={amounts[field.id]}
                        error={errs[`fields.${field.id}.irrigation_in`]}
                      />
                    </td>
                    <td class="py-1 pl-2 text-xs text-ink-muted"
                      ><span class="block py-2">{units.label('depth')}</span></td
                    >
                  </tr>
                {/each}
              </tbody>
            </table>
          </fieldset>
        {/if}
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
          <th class="px-4 py-2 font-medium">Fields</th>
          {#if !readOnly}<th class="px-4 py-2"><span class="sr-only">Actions</span></th>{/if}
        </tr>
      </thead>
      <tbody class="divide-y divide-line">
        {#each irrigations as irrigation (irrigation.date)}
          <tr>
            <td class="px-4 py-2 whitespace-nowrap">{formatDate(irrigation.date, { weekday: true })}</td>
            <td class="px-4 py-2 text-right whitespace-nowrap tabular-nums">{dayAmount(irrigation)}</td>
            <td class="px-4 py-2">{fieldNames(irrigation)}</td>
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
