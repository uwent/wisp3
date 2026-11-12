<script lang="ts">
  import { Form, Link, page, router } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import CollapsibleSection from '@/lib/components/CollapsibleSection.svelte'
  import EditableCell from '@/lib/components/EditableCell.svelte'
  import FieldHeader from '@/lib/components/FieldHeader.svelte'
  import SeasonTimeline from '@/lib/components/SeasonTimeline.svelte'
  import Spinner from '@/lib/components/Spinner.svelte'
  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import { formatDate, isoDate } from '@/lib/dates'
  import { outlook } from '@/lib/outlook'
  import { cropName, plotSize, seasonDates } from '@/lib/plantings'
  import { poll, weatherUpdate } from '@/lib/poll'
  import { rainOverridden } from '@/lib/provenance'
  import { save } from '@/lib/save'
  import PlantingDialog from '@/lib/setup/PlantingDialog.svelte'
  import { units as unitsFor } from '@/lib/units'
  import { fieldDays, fields, pivots, planting as plantingRoute } from '@/routes'
  import type { Field, GenericCurve, Plant, PlantingSummary, SoilType } from '@/types/serializers'

  // The field page (PLAN.md Phase 8 G.11): the land, not one crop on it. The season's plantings on
  // a timeline and with their status today, the field's own rain and irrigation (which every
  // planting on it shares; each planting's balance is on its own page), and its rainfall setting.
  type FieldDayRow = {
    date: string
    rain: number | null
    rain_source: 'entered' | 'model' | 'forecast' | 'none' | 'missing'
    rain_model: number | null
    irrigation: number | null
    irrigation_source: 'entered' | 'pivot' | 'none'
    notes: string | null
  }

  let {
    field,
    pivot,
    farm,
    year,
    weather_updating,
    plantings,
    days,
    plants,
    soil_types,
    generic_curves,
  }: {
    field: Field
    pivot: { id: number; name: string; pump_capacity_gpm: number | null }
    farm: { id: number; name: string }
    year: number
    years: number[]
    weather_updating: boolean
    /** The season's plantings with their status today */
    plantings: PlantingSummary[]
    /** The field's own rain and irrigation, newest first */
    days: FieldDayRow[]
    plants: Plant[]
    soil_types: SoilType[]
    generic_curves: GenericCurve[]
  } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const today = isoDate(new Date())
  const seasonPlantings = $derived(field.plantings.filter((p) => p.year === year))
  const statusById = $derived(Object.fromEntries(plantings.map((s) => [s.planting_id, s.status])))
  // Only plantings in season today have a status worth a dot
  const dots = $derived(
    Object.fromEntries(plantings.filter((s) => s.phase === 'active').map((s) => [s.planting_id, s.status])),
  )
  const anyPartial = $derived(seasonPlantings.some((p) => p.partial))
  let plantingDialog: PlantingDialog | undefined = $state()

  // While the pivot's weather is being fetched, reload until it lands
  let timedOut = $state(false)
  $effect(() => {
    if (!weather_updating) return
    timedOut = false
    return poll(
      () => (weather_updating ? [pivot.id] : []),
      (done) => router.reload({ onFinish: done }),
      { ongiveup: () => (timedOut = true) },
    )
  })
  const weatherState = $derived(weatherUpdate(weather_updating, timedOut))

  type Column = 'rain_in' | 'irrigation_in' | 'notes'
  const depth = (value: number | null) => units.format('depth', value, { unit: false })
  const depthUnitName = $derived(units.label('depth') === 'mm' ? 'millimeters' : 'inches')
  const cellLabel = (day: FieldDayRow, what: string) => `${what}, ${formatDate(day.date, { weekday: true })}`

  function inputText(day: FieldDayRow, column: Column): string {
    if (column === 'rain_in') return day.rain_source === 'entered' ? units.input('depth', day.rain) : ''
    if (column === 'irrigation_in')
      return day.irrigation_source === 'entered' ? units.input('depth', day.irrigation) : ''
    return day.notes ?? ''
  }

  // Saved to the field's own entry (no planting_id); the plantings' statuses follow
  async function saveCell(day: FieldDayRow, column: Column, text: string): Promise<string | null> {
    let value: number | string | null
    if (column === 'notes') {
      value = text.trim() || null
    } else {
      const parsed = units.parse('depth', text)
      if (!parsed.ok) return parsed.error
      value = parsed.value
    }
    return save(
      fieldDays.update({ fieldId: field.id, date: day.date }),
      { day: { [column]: value } },
      { only: ['plantings', 'days', 'errors'] },
    )
  }

  // The operation's rainfall setting, which a field follows unless it has its own
  const operationUsesModel = $derived(page.props.auth.group?.use_model_precip ?? true)
  const rainSetting = $derived(field.use_model_precip === null ? '' : String(field.use_model_precip))
  // [value, label, hint]: blank follows the operation
  const rainOptions = $derived([
    ['', `Follow the operation's setting (${operationUsesModel ? 'modeled rain' : 'only the rain you enter'})`, null],
    ['true', 'Modeled rain for this pivot', 'Your own rain gauge readings replace it on the days you enter them.'],
    [
      'false',
      'Only the rain you enter',
      'Best if you read your gauge every day it rains. Days without an entry count as dry. The projection still uses the forecast rain, and also shows what happens if none falls.',
    ],
  ] as const)
</script>

<svelte:head><title>{field.name} · WISP</title></svelte:head>

<FieldHeader {field} {pivot} {farm} {units} {year} current="field">
  {#snippet actions()}
    <Button variant="secondary" class="px-3 py-1.5" onclick={() => plantingDialog?.open(field)}>Add a planting</Button>
  {/snippet}
</FieldHeader>

{#if weatherState === 'updating'}
  <p role="status" class="flex items-center gap-1.5 text-sm text-ink-muted"><Spinner />Updating weather…</p>
{:else if weatherState === 'failed'}
  <p role="status" class="text-sm text-status-caution-ink">Weather update failed. Refresh the page to try again.</p>
{/if}

<section class="space-y-3 rounded-lg border border-line bg-surface-raised p-4" aria-labelledby="season-heading">
  <h2 id="season-heading" class="font-medium">Plantings in {year}</h2>
  {#if seasonPlantings.length}
    <SeasonTimeline
      plantings={seasonPlantings}
      {year}
      {today}
      {units}
      label="Plantings on {field.name}, {year}"
      href={(p) => plantingRoute(p.id).url}
      status={dots}
    />
    <ul class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      {#each plantings as summary (summary.planting_id)}
        {@const look = summary.phase === 'active' ? outlook(summary, units) : null}
        <li>
          <Link
            href={plantingRoute(summary.planting_id)}
            class="block h-full space-y-1 rounded-md border border-line p-3 hover:border-brand-500"
          >
            <div class="flex items-start justify-between gap-2">
              <p class="min-w-0 font-medium">{cropName(summary)}</p>
              {#if summary.phase === 'active'}
                <StatusBadge status={statusById[summary.planting_id]} size="sm" />
              {:else}
                <span class="shrink-0 rounded-full border border-line px-2 py-0.5 text-xs text-ink-muted"
                  >{summary.phase === 'ended' ? 'Season ended' : 'Upcoming'}</span
                >
              {/if}
            </div>
            <p class="text-xs text-ink-muted">
              {plotSize(summary, units) ?? 'Whole field'} · {seasonDates(summary)}
            </p>
            {#if summary.phase !== 'upcoming' && !summary.weather_pending}
              <p class="text-sm">
                AD {summary.phase === 'ended' ? 'at season end' : 'today'}
                <span class="font-semibold tabular-nums">{units.format('depth', summary.ad)}</span>
                <span class="text-xs text-ink-muted">of {units.format('depth', summary.ad_max)}</span>
              </p>
            {/if}
            {#if look}<p class="text-sm {look.urgent ? 'font-medium text-status-irrigate-ink' : ''}">
                {look.headline}
              </p>{/if}
          </Link>
        </li>
      {/each}
    </ul>
  {:else}
    <p class="text-sm text-ink-muted">
      Nothing planted on this field in {year}.
      <button
        type="button"
        class="text-brand-600 underline underline-offset-2"
        onclick={() => plantingDialog?.open(field)}>Add a planting</button
      > to start its water balance.
    </p>
  {/if}
</section>

{#if days.length}
  <CollapsibleSection title="Rain and irrigation on the field" storageKey="field-days">
    <div class="space-y-2">
      <p class="text-xs text-ink-muted">
        What's entered here is the whole field's, so it counts for every planting on it.
        {#if anyPartial}
          A planting on part of the field can also have its own irrigation, entered on its page, which it uses instead
          of the field's that day.
        {/if}
        Click a cell to enter a value, and press Enter to save and move down. Clear a cell to go back to the modeled or pivot
        value. Depths are in {depthUnitName}. From the keyboard, use the arrow keys to move between cells, and press
        Enter or start typing to edit one.
      </p>
      <div class="max-h-[36rem] max-w-3xl overflow-auto rounded-lg border border-line bg-surface-raised">
        <table class="w-full text-sm">
          <thead class="sticky top-0 z-10 border-b border-line bg-surface-raised text-xs text-ink-muted">
            <tr class="text-right">
              <th class="px-3 py-2 text-left font-medium">Date</th>
              <th class="px-2 py-2 font-medium">Rain</th>
              <th class="px-2 py-2 font-medium">Irrigation</th>
              <th class="px-2 py-2 text-left font-medium">Notes</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-line">
            {#each days as day, row (day.date)}
              <tr class="text-right">
                <th scope="row" class="px-3 py-1 text-left font-normal whitespace-nowrap"
                  >{formatDate(day.date, { weekday: true })}</th
                >
                <td class="px-1 py-0.5">
                  <EditableCell
                    grid="field-days"
                    {row}
                    col={0}
                    text={inputText(day, 'rain_in')}
                    label={cellLabel(day, 'Rain')}
                    onsave={(t) => saveCell(day, 'rain_in', t)}
                  >
                    {#if day.rain_source === 'entered'}
                      <span class="font-medium">{depth(day.rain)}</span>
                      {#if rainOverridden(day)}<span class="block text-xs text-ink-muted"
                          >modeled {depth(day.rain_model)}</span
                        >{/if}
                    {:else}
                      <span class="text-ink-muted">{depth(day.rain)}</span>
                    {/if}
                  </EditableCell>
                </td>
                <td class="px-1 py-0.5">
                  <EditableCell
                    grid="field-days"
                    {row}
                    col={1}
                    text={inputText(day, 'irrigation_in')}
                    label={cellLabel(day, 'Irrigation')}
                    onsave={(t) => saveCell(day, 'irrigation_in', t)}
                  >
                    {#if day.irrigation_source === 'none'}
                      <span class="text-ink-muted">–</span>
                    {:else}
                      <span class="font-medium">{depth(day.irrigation)}</span>
                      {#if day.irrigation_source !== 'entered'}<span class="ml-1 text-xs text-brand-600"
                          >from {day.irrigation_source}</span
                        >{/if}
                    {/if}
                  </EditableCell>
                </td>
                <td class="px-1 py-0.5 text-left">
                  <EditableCell
                    grid="field-days"
                    {row}
                    col={2}
                    align="left"
                    text={inputText(day, 'notes')}
                    label={cellLabel(day, 'Notes')}
                    onsave={(t) => saveCell(day, 'notes', t)}
                  >
                    <span class="block max-w-64 truncate text-ink-muted">{day.notes ?? ''}&nbsp;</span>
                  </EditableCell>
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
      <p class="text-xs text-ink-muted">
        Rain in gray is modeled for the pivot's location; bold values are ones you entered. Irrigation marked “from
        pivot” was entered on the
        <Link href={pivots.show(pivot.id)} class="text-brand-600 underline underline-offset-2"
          >pivot's irrigation page</Link
        > or on the Daily entry page.
      </p>
    </div>
  </CollapsibleSection>
{/if}

<CollapsibleSection title="Rainfall preferences" id="rainfall" storageKey="rainfall">
  <Form
    action={fields.update(field.id)}
    class="max-w-xl space-y-3 rounded-lg border border-line bg-surface-raised p-4"
    options={{ preserveScroll: true }}
  >
    {#snippet children({ processing })}
      <fieldset class="space-y-2">
        <legend class="text-sm font-medium">Which rain this field's plantings use</legend>
        {#each rainOptions as [value, label, hint] (value)}
          <label class="flex items-start gap-3 text-sm">
            <input type="radio" name="field[use_model_precip]" {value} checked={rainSetting === value} class="mt-0.5" />
            <span
              >{label}{#if hint}<span class="block text-ink-muted">{hint}</span>{/if}</span
            >
          </label>
        {/each}
      </fieldset>
      <p class="text-xs text-ink-muted">
        This only changes which rain the balance uses. Nothing is copied or deleted, so you can switch back at any time.
      </p>
      <Button type="submit" disabled={processing}>Save</Button>
    {/snippet}
  </Form>
</CollapsibleSection>

<PlantingDialog bind:this={plantingDialog} {year} {plants} soilTypes={soil_types} genericCurves={generic_curves} />
