<script lang="ts">
  import { Form, Link, page, router } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import { addDays, formatDate } from '@/lib/dates'
  import { confirmUnsavedChanges, UNSAVED_MESSAGE } from '@/lib/unsaved.svelte'
  import { units as unitsFor } from '@/lib/units'
  import { dailyEntries, fields as fieldRoutes, newQuickSetup } from '@/routes'
  import type { PivotIrrigation } from '@/types/serializers'

  type DayField = {
    id: number
    name: string
    area_acres: number | null
    crop: string | null
    rain_model: number | null
    entry: {
      rain_in: number | null
      irrigation_in: number | null
      soil_moisture_pct: number | null
      notes: string | null
    } | null
  }
  type DayPivot = {
    id: number
    name: string
    pump_capacity_gpm: number | null
    irrigation: PivotIrrigation | null
    fields: DayField[]
  }

  let { date, farms }: { date: string; farms: { id: number; name: string; pivots: DayPivot[] }[] } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const today = new Date().toLocaleDateString('en-CA')

  // Typed values not yet saved: set by any input, cleared by a successful save
  let dirty = $state(false)
  confirmUnsavedChanges(() => dirty)

  /** Goes to another date, asking first if there are unsaved values; false if the user stayed */
  function go(to: string): boolean {
    if (dirty && !confirm(UNSAVED_MESSAGE)) return false
    dirty = false
    router.get(dailyEntries.show().url, { date: to })
    return true
  }
  const canUseHours = (pivot: DayPivot) =>
    pivot.pump_capacity_gpm !== null && pivot.fields.every((f) => f.area_acres !== null)

  // Which pivots are entered as run hours; starts from the saved irrigation
  let byHours = $state<Record<number, boolean>>({})
  const hours = (pivot: DayPivot) =>
    byHours[pivot.id] ?? (pivot.irrigation !== null && pivot.irrigation.inches === null)

  const pivotApplies = (pivot: DayPivot, field: DayField) =>
    pivot.irrigation !== null && (pivot.irrigation.field_ids === null || pivot.irrigation.field_ids.includes(field.id))

  const e = (errors: Record<string, string | string[]>, key: string) => errors[key]
</script>

<svelte:head><title>Daily entry · WISP</title></svelte:head>

<div class="flex flex-wrap items-end justify-between gap-3">
  <div>
    <h1 class="text-2xl font-semibold">Daily entry</h1>
    <p class="text-sm text-ink-muted">Rain, irrigation and soil moisture readings for every field on one day.</p>
  </div>
  <div class="flex items-center gap-1">
    <Button variant="secondary" class="px-3" onclick={() => go(addDays(date, -1))} aria-label="Previous day">‹</Button>
    <input
      type="date"
      value={date}
      max={today}
      class="rounded-md text-sm"
      aria-label="Date"
      onchange={(event) => {
        if (!go(event.currentTarget.value)) event.currentTarget.value = date
      }}
    />
    <Button
      variant="secondary"
      class="px-3"
      onclick={() => go(addDays(date, 1))}
      disabled={date >= today}
      aria-label="Next day">›</Button
    >
  </div>
</div>

{#if farms.every((farm) => farm.pivots.length === 0)}
  <section
    class="rounded-lg border border-dashed border-line bg-surface-raised px-6 py-10 text-center text-sm text-ink-muted"
  >
    No pivots yet. <Link href={newQuickSetup()} class="text-brand-600 hover:underline">Set up your first pivot</Link>.
  </section>
{:else}
  {#key date}
    <Form
      action={dailyEntries.update()}
      class="space-y-6"
      options={{ preserveScroll: true }}
      oninput={() => (dirty = true)}
      onchange={() => (dirty = true)}
      onSuccess={() => (dirty = false)}
    >
      {#snippet children({ errors, processing, isDirty })}
        {@const errs = errors as Record<string, string | string[]>}
        <input type="hidden" name="date" value={date} />
        <h2 class="text-lg font-medium">{formatDate(date, { weekday: true, year: true })}</h2>

        {#each farms as farm (farm.id)}
          {#if farm.pivots.length}
            <section class="space-y-3">
              <h3 class="font-medium text-ink-muted">{farm.name}</h3>
              {#each farm.pivots as pivot (pivot.id)}
                <div class="rounded-lg border border-line bg-surface-raised">
                  <div class="flex flex-wrap items-start gap-x-6 gap-y-3 border-b border-line p-4">
                    <div class="min-w-32">
                      <h4 class="font-medium">{pivot.name}</h4>
                      <p class="text-xs text-ink-muted">Pivot irrigation, for all its fields or some</p>
                    </div>
                    <div class="w-40">
                      {#if hours(pivot)}
                        <NumberField
                          label="Run hours"
                          name="pivots[{pivot.id}][run_hours]"
                          unitLabel="h"
                          value={pivot.irrigation?.run_hours ?? null}
                          error={e(errs, `pivots.${pivot.id}.run_hours`)}
                        />
                        <input type="hidden" name="pivots[{pivot.id}][inches]" value="" />
                      {:else}
                        <NumberField
                          label="Irrigation"
                          name="pivots[{pivot.id}][inches]"
                          quantity="depth"
                          value={pivot.irrigation?.inches ?? null}
                          error={e(errs, `pivots.${pivot.id}.inches`)}
                        />
                        <input type="hidden" name="pivots[{pivot.id}][run_hours]" value="" />
                      {/if}
                    </div>
                    {#if canUseHours(pivot)}
                      <label class="flex items-center gap-2 self-end pb-2 text-sm">
                        <input
                          type="checkbox"
                          class="rounded"
                          checked={hours(pivot)}
                          onchange={(event) => (byHours[pivot.id] = event.currentTarget.checked)}
                        />
                        Run hours
                      </label>
                    {/if}
                    {#if pivot.fields.length > 1}
                      <fieldset class="space-y-1 self-end pb-1">
                        <legend class="text-sm font-medium">Applied to</legend>
                        <input type="hidden" name="pivots[{pivot.id}][field_ids][]" value="" />
                        <div class="flex flex-wrap gap-x-4 gap-y-1">
                          {#each pivot.fields as field (field.id)}
                            <label class="flex items-center gap-1.5 text-sm">
                              <input
                                type="checkbox"
                                class="rounded"
                                name="pivots[{pivot.id}][field_ids][]"
                                value={field.id}
                                checked={pivot.irrigation?.field_ids == null ||
                                  pivot.irrigation.field_ids.includes(field.id)}
                              />
                              {field.name}
                            </label>
                          {/each}
                        </div>
                        {#if e(errs, `pivots.${pivot.id}.field_ids`)}<p class="text-xs text-status-irrigate">
                            {e(errs, `pivots.${pivot.id}.field_ids`)}
                          </p>{/if}
                      </fieldset>
                    {/if}
                  </div>

                  <div class="overflow-x-auto">
                    <table class="w-full text-sm">
                      <thead class="text-xs text-ink-muted">
                        <tr class="text-left">
                          <th class="px-4 py-2 font-medium">Field</th>
                          <th class="px-2 py-2 font-medium">Rain ({units.label('depth')})</th>
                          <th class="px-2 py-2 font-medium">Own irrigation ({units.label('depth')})</th>
                          <th class="px-2 py-2 font-medium">Moisture reading (%)</th>
                        </tr>
                      </thead>
                      <tbody class="divide-y divide-line">
                        {#each pivot.fields as field (field.id)}
                          <tr class="align-top">
                            <th scope="row" class="px-4 py-2 text-left font-normal">
                              <Link href={fieldRoutes.show(field.id)} class="hover:underline">{field.name}</Link>
                              <span class="block text-xs text-ink-muted">{field.crop ?? 'No crop'}</span>
                            </th>
                            <td class="w-36 px-2 py-2">
                              <NumberField
                                hideLabel
                                label="Rain on {field.name}"
                                name="fields[{field.id}][rain_in]"
                                quantity="depth"
                                value={field.entry?.rain_in ?? null}
                                placeholder={field.rain_model === null
                                  ? ''
                                  : `model ${units.format('depth', field.rain_model, { unit: false })}`}
                                error={e(errs, `fields.${field.id}.rain_in`)}
                              />
                            </td>
                            <td class="w-36 px-2 py-2">
                              <NumberField
                                hideLabel
                                label="Irrigation on {field.name} (replaces the pivot's)"
                                name="fields[{field.id}][irrigation_in]"
                                quantity="depth"
                                value={field.entry?.irrigation_in ?? null}
                                placeholder={pivotApplies(pivot, field) ? "pivot's" : ''}
                                error={e(errs, `fields.${field.id}.irrigation_in`)}
                              />
                            </td>
                            <td class="w-36 px-2 py-2">
                              <NumberField
                                hideLabel
                                label="Soil moisture reading on {field.name}"
                                name="fields[{field.id}][soil_moisture_pct]"
                                value={field.entry?.soil_moisture_pct ?? null}
                                error={e(errs, `fields.${field.id}.soil_moisture_pct`)}
                              />
                            </td>
                          </tr>
                        {/each}
                      </tbody>
                    </table>
                  </div>
                </div>
              {/each}
            </section>
          {/if}
        {/each}

        <div
          class="sticky bottom-0 -mx-4 flex items-center gap-3 border-t border-line bg-surface/95 px-4 py-3 backdrop-blur"
        >
          <Button type="submit" disabled={processing}>Save {formatDate(date)}</Button>
          <p class="text-sm text-ink-muted">
            {#if Object.keys(errs).length}<span class="text-status-irrigate"
                >Nothing was saved; please fix the highlighted values.</span
              >
            {:else if isDirty || dirty}Unsaved changes{:else}Leave rain blank to use the modeled value; enter 0 if your
              gauge read nothing.{/if}
          </p>
        </div>
      {/snippet}
    </Form>
  {/key}
{/if}
