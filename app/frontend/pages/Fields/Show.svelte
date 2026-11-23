<script lang="ts">
  import { Link, page } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import CollapsibleSection from '@/lib/components/CollapsibleSection.svelte'
  import EditableCell from '@/lib/components/EditableCell.svelte'
  import FieldHeader from '@/lib/components/FieldHeader.svelte'
  import SeasonTimeline from '@/lib/components/SeasonTimeline.svelte'
  import Spinner from '@/lib/components/Spinner.svelte'
  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import Term from '@/lib/components/Term.svelte'
  import ZoneWeather from '@/lib/components/ZoneWeather.svelte'
  import { currentYear, formatDate, today as todayDate } from '@/lib/dates'
  import { KIND_NOUNS, type PivotKind } from '@/lib/geo'
  import { isExample } from '@/lib/permissions'
  import { outlook } from '@/lib/outlook'
  import { cardWhen, cropName, plotSize, seasonDates, seasonLine } from '@/lib/plantings'
  import { cellLabel, cellText, cellValue, depthUnitName as depthUnit } from '@/lib/fieldDays'
  import { pollWeather } from '@/lib/weatherPolling.svelte'
  import { rainSettingLink, rainSettingOwner } from '@/lib/rainSetting'
  import { rainOverridden } from '@/lib/provenance'
  import { save } from '@/lib/save'
  import PlantingDialog from '@/lib/setup/PlantingDialog.svelte'
  import { currentUnits } from '@/lib/units'
  import { fieldDays, pivots, planting as plantingRoute } from '@/routes'
  import type { Field, ForecastDay, GenericCurve, Plant, PlantingSummary, SoilType } from '@/types/serializers'

  // The field page: the land, not one crop on it. The season's plantings on
  // a timeline and with their status today, the field's own rain and irrigation (which every
  // planting on it shares; each planting's balance is on its own page). Which rain counts is its
  // irrigation group's setting, or its farm's (lib/rainSetting.ts).
  type FieldDayRow = {
    date: string
    rain: number | null
    rain_source: 'entered' | 'model' | 'forecast' | 'none' | 'missing'
    rain_model: number | null
    irrigation: number | null
    irrigation_source: 'entered' | 'none'
    notes: string | null
  }

  let {
    field,
    pivot,
    farm,
    year,
    weather_updating,
    weather_zone,
    forecast,
    plantings,
    days,
    plants,
    soil_types,
    generic_curves,
  }: {
    field: Field
    pivot: {
      id: number
      name: string
      kind: PivotKind
      kind_name: string
      pump_capacity_gpm: number | null
      /** Whether days without entered rain take the modeled rain: its group's setting, else its farm's */
      use_model_precip: boolean
      pivot_group: { id: number; name: string } | null
    }
    farm: { id: number; name: string }
    year: number
    years: number[]
    weather_updating: boolean
    weather_zone: { id: number; name: string; location: string } | null
    forecast: ForecastDay[]
    /** The season's plantings with their status today */
    plantings: PlantingSummary[]
    /** The field's own rain and irrigation, newest first */
    days: FieldDayRow[]
    plants: Plant[]
    soil_types: SoilType[]
    generic_curves: GenericCurve[]
  } = $props()

  const units = $derived(currentUnits())
  // "pivot", "drip block"
  const noun = $derived(KIND_NOUNS[pivot.kind])
  const today = todayDate()
  const seasonPlantings = $derived(field.plantings.filter((p) => p.year === year))
  const statusById = $derived(Object.fromEntries(plantings.map((s) => [s.planting_id, s.status])))
  // Only plantings in season today have a status worth a dot
  const dots = $derived(
    Object.fromEntries(plantings.filter((s) => s.phase === 'active').map((s) => [s.planting_id, s.status])),
  )
  const anyPartial = $derived(seasonPlantings.some((p) => p.partial))
  let plantingDialog: PlantingDialog | undefined = $state()

  // While the pivot's weather is being fetched, reload until it lands
  const weatherWait = pollWeather(() => (weather_updating ? [pivot.id] : []))
  const weatherState = $derived(weatherWait.state(weather_updating))

  type Column = 'rain_in' | 'irrigation_in' | 'notes'
  const depth = (value: number | null) => units.format('depth', value, { unit: false })
  const depthUnitName = $derived(depthUnit(units))
  const inputText = (day: FieldDayRow, column: Column) => cellText(day, column, units)

  // Saved to the field's own entry (no planting_id); the plantings' statuses follow
  async function saveCell(day: FieldDayRow, column: Column, text: string): Promise<string | null> {
    const parsed = cellValue(column, text, units)
    if (!parsed.ok) return parsed.error
    return save(
      fieldDays.update({ fieldId: field.id, date: day.date }),
      { day: { [column]: parsed.value } },
      { only: ['plantings', 'days', 'errors'] },
    )
  }

  // The example farm is only viewed
  const readOnly = $derived(isExample(page.props))
</script>

<svelte:head><title>{field.name} · WISP</title></svelte:head>

<FieldHeader {field} {pivot} {farm} {units} {year} current="field">
  {#snippet actions()}
    {#if !readOnly}
      <Button variant="secondary" class="px-3 py-1.5" onclick={() => plantingDialog?.open(field)}>Add a planting</Button
      >
    {/if}
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
              {plotSize(summary, units) ?? 'Whole field'} · {summary.phase === 'ended'
                ? cardWhen(summary, today)
                : seasonDates(summary)}
            </p>
            <!-- The outlook leads, with moisture and AD beneath it; an ended season in a line -->
            {#if look}<p class="text-sm font-medium {look.urgent ? 'text-status-irrigate-ink' : ''}">
                {look.headline}
              </p>{/if}
            {#if summary.phase === 'ended' && !summary.weather_pending}
              <p class="text-xs text-ink-muted">{seasonLine(summary.totals, units, summary.rainfed)}</p>
            {:else if summary.phase === 'active' && !summary.weather_pending}
              <p class="text-xs text-ink-muted tabular-nums">
                {#if summary.pct_moisture !== null}{summary.pct_moisture.toFixed(1)}% soil moisture ·{' '}{/if}AD
                {units.format('depth', summary.ad)} of {units.format('depth', summary.ad_max)}
              </p>
            {/if}
          </Link>
        </li>
      {/each}
    </ul>
  {:else}
    <p class="text-sm text-ink-muted">
      Nothing planted on this field in {year}{readOnly ? '.' : ''}
      {#if !readOnly}<button
          type="button"
          class="text-brand-600 underline underline-offset-2"
          onclick={() => plantingDialog?.open(field)}>Add a planting</button
        > to start its water balance.{/if}
    </p>
  {/if}
</section>

<ZoneWeather zone={weather_zone} {forecast} {units} query={year === currentYear() ? {} : { year }} />

{#if days.length}
  <CollapsibleSection title="Rain and irrigation on the field" storageKey="field-days">
    <div class="space-y-2">
      <p class="text-xs text-ink-muted">
        What's entered here is the whole field's, so it counts for every planting on it.
        {#if anyPartial}
          A planting on part of the field has its own irrigation: the field's irrigation fills it in when it had the
          field's amount, and one entered on its page stays.
        {/if}
        {#if !readOnly}Click a cell to enter a value, and press Enter to save and move down. Clear a rain cell to go
          back to the modeled value.{/if}
        Depths are in {depthUnitName}.{readOnly
          ? ''
          : ' From the keyboard, use the arrow keys to move between cells, and press Enter or start typing to edit one.'}
      </p>
      <!-- The page's width: Date, Rain and Irrigation as wide as they need (w-px, no wrapping), Notes the rest -->
      <!-- Read-only, the grid has no cells to tab to, so the scrolling box takes focus -->
      <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
      <div
        class="max-h-[36rem] overflow-auto rounded-lg border border-line bg-surface-raised"
        tabindex={readOnly ? 0 : undefined}
        role={readOnly ? 'region' : undefined}
        aria-label={readOnly ? 'Rain and irrigation by day' : undefined}
      >
        <table class="w-full text-sm">
          <thead class="text-xs text-ink-muted">
            <tr class="text-right">
              <th
                class="sticky top-0 z-20 w-px bg-surface-raised px-3 py-2 text-left font-medium whitespace-nowrap shadow-[inset_0_-1px_0_var(--color-line)]"
                >Date</th
              >
              <th
                class="sticky top-0 z-20 w-px bg-surface-raised px-2 py-2 font-medium whitespace-nowrap shadow-[inset_0_-1px_0_var(--color-line)]"
                >Rain</th
              >
              <th
                class="sticky top-0 z-20 w-px bg-surface-raised px-2 py-2 font-medium whitespace-nowrap shadow-[inset_0_-1px_0_var(--color-line)]"
                >Irrigation</th
              >
              <th
                class="sticky top-0 z-20 bg-surface-raised px-2 py-2 text-left font-medium shadow-[inset_0_-1px_0_var(--color-line)]"
                >Notes</th
              >
            </tr>
          </thead>
          <tbody class="divide-y divide-line">
            {#each days as day, row (day.date)}
              <tr class="text-right">
                <th scope="row" class="w-px px-3 py-1 text-left font-normal whitespace-nowrap"
                  >{formatDate(day.date, { weekday: true })}</th
                >
                <td class="w-px px-1 py-0.5 whitespace-nowrap">
                  <EditableCell
                    grid="field-days"
                    {row}
                    col={0}
                    text={inputText(day, 'rain_in')}
                    label={cellLabel(day, 'Rain')}
                    {readOnly}
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
                <td class="w-px px-1 py-0.5 whitespace-nowrap">
                  <EditableCell
                    grid="field-days"
                    {row}
                    col={1}
                    text={inputText(day, 'irrigation_in')}
                    label={cellLabel(day, 'Irrigation')}
                    {readOnly}
                    onsave={(t) => saveCell(day, 'irrigation_in', t)}
                  >
                    {#if day.irrigation_source === 'none'}
                      <span class="text-ink-muted">–</span>
                    {:else}
                      <span class="font-medium">{depth(day.irrigation)}</span>
                    {/if}
                  </EditableCell>
                </td>
                <!-- max-w-0 lets a long note truncate to the column rather than widen it -->
                <td class="max-w-0 px-1 py-0.5 text-left">
                  <EditableCell
                    grid="field-days"
                    {row}
                    col={2}
                    align="left"
                    text={inputText(day, 'notes')}
                    label={cellLabel(day, 'Notes')}
                    {readOnly}
                    onsave={(t) => saveCell(day, 'notes', t)}
                  >
                    <span class="block truncate text-ink-muted">{day.notes ?? ''}&nbsp;</span>
                  </EditableCell>
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
      <p class="text-xs text-ink-muted">
        Rain in gray is modeled for the {noun}'s location; bold values are ones you entered. Irrigation can also be
        entered for all the {noun}'s fields at once on the
        <Link href={pivots.show(pivot.id)} class="text-brand-600 underline underline-offset-2"
          >{noun}'s irrigation page</Link
        > or the Daily entry page.
      </p>
      {#if !pivot.use_model_precip}
        <p class="text-xs">
          Rain: <Term id="entered_rain_only">only what you enter</Term>, {rainSettingOwner(pivot.pivot_group)} setting. Days
          without an entry count as dry.
          {#if !readOnly}
            <Link
              href={rainSettingLink(pivot.pivot_group?.id ?? null, farm.id)}
              class="text-brand-600 underline underline-offset-2">Change this</Link
            >
          {/if}
        </p>
      {/if}
    </div>
  </CollapsibleSection>
{/if}

<PlantingDialog bind:this={plantingDialog} {year} {plants} soilTypes={soil_types} genericCurves={generic_curves} />
