<script lang="ts">
  import { Form, Link, page, router } from '@inertiajs/svelte'

  import { weatherPanels } from '@/lib/charts/weatherCharts'
  import WeatherSection from '@/lib/charts/WeatherSection.svelte'
  import Button from '@/lib/components/Button.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import { formatDate } from '@/lib/dates'
  import { units as unitsFor } from '@/lib/units'
  import { dashboard, fields as fieldRoutes, pivotIrrigations, pivots } from '@/routes'
  import type { Pivot, PivotIrrigation, WeatherPanelDay } from '@/types/serializers'

  let {
    pivot,
    farm,
    year,
    irrigations,
    weather_from,
    weather,
  }: {
    pivot: Pivot
    farm: { id: number; name: string }
    year: number
    irrigations: PivotIrrigation[]
    weather_from: string
    weather: WeatherPanelDay[]
  } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const today = new Date().toLocaleDateString('en-CA')
  const panels = $derived(weatherPanels(units, { gddSince: formatDate(weather_from) }))
  const canUseHours = $derived(pivot.pump_capacity_gpm !== null && pivot.fields.every((field) => field.area_acres !== null))

  // The form edits a new irrigation, or an existing one picked from the list
  let editing = $state<PivotIrrigation | null>(null)
  let byHours = $state(false)
  let formKey = $state(0)
  // Adding one on a date that already has an irrigation replaces it (the controller), so say so
  let date = $state(today)
  const existing = $derived(editing ? undefined : irrigations.find((irrigation) => irrigation.date === date))

  function edit(irrigation: PivotIrrigation | null) {
    editing = irrigation
    byHours = irrigation !== null && irrigation.inches === null
    date = irrigation?.date ?? today
    formKey++
  }

  const fieldNames = (ids: number[] | null) =>
    ids === null ? 'All fields' : pivot.fields.filter((field) => ids.includes(field.id)).map((field) => field.name).join(', ')

  function remove(irrigation: PivotIrrigation) {
    if (confirm(`Delete the ${formatDate(irrigation.date)} irrigation?`)) {
      router.delete(pivotIrrigations.destroy({ pivotId: pivot.id, id: irrigation.id }).url, { preserveScroll: true })
    }
  }
</script>

<svelte:head><title>{pivot.name} · WISP</title></svelte:head>

<div class="flex flex-wrap items-end justify-between gap-3">
  <div>
    <Link href={dashboard.show()} class="text-sm text-brand-600 hover:underline">← Dashboard</Link>
    <h1 class="text-2xl font-semibold"><span class="font-normal text-ink-muted">Pivot:</span> {pivot.name}</h1>
    <p class="text-sm text-ink-muted">
      Farm: {farm.name} · Fields:
      {#each pivot.fields as field, i (field.id)}{i ? ', ' : ''}<Link href={fieldRoutes.show(field.id)} class="text-brand-600 hover:underline">{field.name}</Link>{:else}none yet{/each}
      · <Link href={pivots.edit(pivot.id)} class="text-brand-600 hover:underline">Edit pivot</Link>
    </p>
  </div>
  <select class="rounded-md text-sm" aria-label="Season" value={year} onchange={(e) => router.get(pivots.show(pivot.id).url, { year: e.currentTarget.value })}>
    {#each [year - 2, year - 1, year, year + 1] as y (y)}<option value={y}>{y}</option>{/each}
  </select>
</div>

{#key formKey}
  <section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
    <div>
      <h2 class="text-lg font-medium">{editing ? `Edit ${formatDate(editing.date)}` : 'Add an irrigation'}</h2>
      <p class="text-sm text-ink-muted">
        Enter each irrigation once here and it applies to the pivot's fields. A field's own entry for a day replaces it.
      </p>
    </div>
    <Form
      action={editing ? pivotIrrigations.update({ pivotId: pivot.id, id: editing.id }) : pivotIrrigations.create(pivot.id)}
      class="space-y-4"
      options={{ preserveScroll: true }}
      onSuccess={() => edit(null)}
    >
      {#snippet children({ errors, processing })}
        <div class="grid gap-4 sm:grid-cols-3">
          <div class="space-y-1">
            <label for="irrigation-date" class="block text-sm font-medium">Date</label>
            <input id="irrigation-date" type="date" name="pivot_irrigation[date]" bind:value={date} required class="block w-full rounded-md text-sm" />
            {#if errors.date}<p class="text-sm text-status-irrigate">{errors.date}</p>{/if}
            {#if existing}
              <p class="text-sm" role="status">
                ⚠ {formatDate(existing.date)} already has {units.format('depth', existing.applied_inches)}; saving replaces it.
                <button type="button" class="text-brand-600 underline" onclick={() => edit(existing)}>Edit that one instead</button>
              </p>
            {/if}
          </div>
          {#if byHours}
            <NumberField label="Run hours" name="pivot_irrigation[run_hours]" unitLabel="h" value={editing?.run_hours ?? null} error={errors.run_hours} />
            <input type="hidden" name="pivot_irrigation[inches]" value="" />
          {:else}
            <NumberField label="Amount" name="pivot_irrigation[inches]" quantity="depth" value={editing?.inches ?? null} error={errors.inches} />
            <input type="hidden" name="pivot_irrigation[run_hours]" value="" />
          {/if}
          <div class="flex items-end pb-2 text-sm">
            {#if canUseHours}
              <label class="flex items-center gap-2">
                <input type="checkbox" bind:checked={byHours} class="rounded" /> Enter run hours
              </label>
            {:else}
              <span class="text-ink-muted">Add pump capacity and field areas to enter run hours.</span>
            {/if}
          </div>
        </div>
        {#if pivot.fields.length > 1}
          <fieldset class="space-y-2">
            <legend class="text-sm font-medium">Applied to</legend>
            <input type="hidden" name="pivot_irrigation[field_ids][]" value="" />
            <div class="flex flex-wrap gap-x-5 gap-y-2">
              {#each pivot.fields as field (field.id)}
                <label class="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    name="pivot_irrigation[field_ids][]"
                    value={field.id}
                    checked={editing?.field_ids == null || editing.field_ids.includes(field.id)}
                    class="rounded"
                  />
                  {field.name}
                </label>
              {/each}
            </div>
            {#if errors.field_ids}<p class="text-sm text-status-irrigate">{errors.field_ids}</p>{/if}
          </fieldset>
        {/if}
        <div class="space-y-1">
          <label for="irrigation-notes" class="block text-sm font-medium">Notes</label>
          <input id="irrigation-notes" name="pivot_irrigation[notes]" value={editing?.notes ?? ''} class="block w-full rounded-md text-sm" />
        </div>
        <div class="flex gap-2">
          <Button type="submit" disabled={processing}>Save irrigation</Button>
          {#if editing}<Button variant="secondary" onclick={() => edit(null)}>Cancel</Button>{/if}
        </div>
      {/snippet}
    </Form>
  </section>
{/key}

<section class="overflow-x-auto rounded-lg border border-line bg-surface-raised">
  {#if irrigations.length === 0}
    <p class="p-6 text-center text-sm text-ink-muted">No irrigation entered for {year}.</p>
  {:else}
    <table class="w-full text-sm">
      <thead class="border-b border-line text-left text-xs text-ink-muted">
        <tr>
          <th class="px-4 py-2 font-medium">Date</th>
          <th class="px-4 py-2 text-right font-medium">Amount</th>
          <th class="px-4 py-2 font-medium">Applied to</th>
          <th class="px-4 py-2 font-medium">Notes</th>
          <th class="px-4 py-2"><span class="sr-only">Actions</span></th>
        </tr>
      </thead>
      <tbody class="divide-y divide-line">
        {#each irrigations as irrigation (irrigation.id)}
          <tr>
            <td class="px-4 py-2 whitespace-nowrap">{formatDate(irrigation.date, { weekday: true })}</td>
            <td class="px-4 py-2 text-right whitespace-nowrap tabular-nums">
              {units.format('depth', irrigation.applied_inches)}
              {#if irrigation.inches === null}<span class="block text-xs text-ink-muted">{irrigation.run_hours} h run</span>{/if}
            </td>
            <td class="px-4 py-2">{fieldNames(irrigation.field_ids)}</td>
            <td class="px-4 py-2 text-ink-muted">{irrigation.notes ?? ''}</td>
            <td class="px-4 py-2 text-right whitespace-nowrap">
              <Button variant="ghost" class="px-2 py-1 text-xs" onclick={() => edit(irrigation)}>Edit</Button>
              <Button variant="danger-ghost" class="px-2 py-1 text-xs" onclick={() => remove(irrigation)}>Delete</Button>
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  {/if}
</section>

<WeatherSection title="Weather at this pivot, {year}" {panels} days={weather} {units}>
  Each field's crop ET and soil water are on its own page.
</WeatherSection>
