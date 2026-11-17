<script lang="ts">
  import { Link } from '@inertiajs/svelte'

  import CollapsibleSection from '@/lib/components/CollapsibleSection.svelte'
  import EditableCell from '@/lib/components/EditableCell.svelte'
  import { formatDate } from '@/lib/dates'
  import { cellLabel, cellText, depthUnitName, irrigationFrom, type DayColumn } from '@/lib/fieldDays'
  import { ET_SOURCE_LABELS, rainOverridden } from '@/lib/provenance'
  import { formatNumber, type Units } from '@/lib/units'
  import { fields, pivots } from '@/routes'
  import type { FieldDay, Planting } from '@/types/serializers'

  // The planting page's daily values (PLAN.md §11): the season's days, latest first, its entries
  // edited in their cells (EditableCell, one grid); read-only while time travelling (asOf). plot: a
  // planting on part of the field (G.11), its size, whose rain is the field's
  let {
    days,
    planting,
    fieldId,
    pivotId,
    units,
    noun,
    plot,
    asOf,
    readOnly,
    onsave,
  }: {
    days: FieldDay[]
    planting: Planting
    fieldId: number
    pivotId: number
    units: Units
    noun: string
    plot: string | null
    asOf: string | null
    readOnly: boolean
    onsave: (day: FieldDay, column: DayColumn, text: string) => Promise<string | null>
  } = $props()

  const depth = (value: number | null) => units.format('depth', value, { unit: false })
  const lai = $derived(planting.et_method === 'lai')
  const rows = $derived([...days].reverse())
  const inputText = (day: FieldDay, column: DayColumn) => cellText(day, column, units)
  const saveCell = (day: FieldDay, column: DayColumn, text: string) => onsave(day, column, text)
</script>

<CollapsibleSection title="Daily values" storageKey="daily">
  <div class="space-y-2">
    <p class="text-xs text-ink-muted">
      {#if readOnly}
        The season up to {formatDate(asOf)}. Depths are in {depthUnitName(units)}.
      {:else}
        Click a rain, irrigation, soil moisture, {lai ? 'LAI' : 'cover'} or notes cell to enter a value, and press Enter to
        save and move down. Clear a cell to go back to the modeled value or the {noun}'s. Depths are in {depthUnitName(
          units,
        )}. From the keyboard, use the arrow keys to move between cells, and press Enter or start typing to edit one.
        {#if plot}
          Rain is the whole field's, so it's the same for every planting on it; irrigation, soil moisture readings and
          notes entered here are this planting's own. Irrigation entered for the whole field (on the
          <Link href={fields.show(fieldId)} class="text-brand-600 underline underline-offset-2">Field</Link> tab) applies
          here unless you enter this planting's own.
        {/if}
      {/if}
    </p>
    <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
    <div
      class="max-h-[36rem] overflow-auto rounded-lg border border-line bg-surface-raised"
      tabindex={readOnly ? 0 : undefined}
      role={readOnly ? 'region' : undefined}
      aria-label={readOnly ? 'Daily values' : undefined}
    >
      <table class="w-full text-sm">
        <thead class="sticky top-0 z-10 border-b border-line bg-surface-raised text-xs text-ink-muted">
          <tr class="text-right">
            <th class="px-3 py-2 text-left font-medium">Date</th>
            <th class="px-2 py-2 font-medium">Reference ET</th>
            <th class="px-2 py-2 font-medium">Crop ET</th>
            <th class="px-2 py-2 font-medium">Rain</th>
            <th class="px-2 py-2 font-medium">Irrigation</th>
            <th class="px-2 py-2 font-medium">Soil moisture reading (%)</th>
            <th class="px-2 py-2 font-medium">{lai ? 'LAI' : 'Cover (%)'}</th>
            <th class="px-2 py-2 font-medium">AD</th>
            <th class="px-2 py-2 font-medium">Soil moisture (%)</th>
            <th class="px-2 py-2 font-medium">Drainage</th>
            <th class="px-2 py-2 text-left font-medium">Notes</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-line">
          {#each rows as day, row (day.date)}
            <tr class="text-right {day.ad <= 0 ? 'bg-status-irrigate/5' : ''}">
              <th scope="row" class="px-3 py-1 text-left font-normal whitespace-nowrap"
                >{formatDate(day.date, { weekday: true })}</th
              >
              <td class="px-2 py-1 tabular-nums {day.et0_source === 'missing' ? 'text-ink-muted' : ''}"
                >{depth(day.et0)}</td
              >
              <td class="px-2 py-1 tabular-nums" title={ET_SOURCE_LABELS[day.et_source]}>
                {depth(day.adj_et)}{#if day.et_source === 'gap_fill'}<span class="text-ink-muted">*</span>{/if}
              </td>
              <td class="px-1 py-0.5">
                <EditableCell
                  grid="days"
                  {row}
                  col={0}
                  text={inputText(day, 'rain_in')}
                  label={cellLabel(day, 'Rain')}
                  {readOnly}
                  onsave={(t) => saveCell(day, 'rain_in', t)}
                >
                  {#if day.rain_source === 'model' || day.rain_source === 'missing' || day.rain_source === 'none'}
                    <span class="text-ink-muted">{depth(day.rain)}</span>
                  {:else}
                    <span class="font-medium">{depth(day.rain)}</span>
                    {#if rainOverridden(day)}<span class="block text-xs text-ink-muted"
                        >modeled {depth(day.rain_model)}</span
                      >{/if}
                  {/if}
                </EditableCell>
              </td>
              <td class="px-1 py-0.5">
                <EditableCell
                  grid="days"
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
                    {#if irrigationFrom(day.irrigation_source, noun)}<span class="ml-1 text-xs text-brand-600"
                        >{irrigationFrom(day.irrigation_source, noun)}</span
                      >{/if}
                    {#if day.irrigation_source === 'entered' && day.field_inches !== null}
                      <span class="block text-xs text-ink-muted">field {depth(day.field_inches)}</span>
                    {:else if day.irrigation_source === 'entered' && day.pivot_inches !== null}
                      <span class="block text-xs text-ink-muted">{noun} {depth(day.pivot_inches)}</span>
                    {/if}
                  {/if}
                </EditableCell>
              </td>
              <td class="px-1 py-0.5">
                <EditableCell
                  grid="days"
                  {row}
                  col={2}
                  text={inputText(day, 'soil_moisture_pct')}
                  label={cellLabel(day, 'Soil moisture reading')}
                  {readOnly}
                  onsave={(t) => saveCell(day, 'soil_moisture_pct', t)}
                >
                  {#if day.soil_moisture_pct !== null}
                    <span class="font-medium">{day.soil_moisture_pct}</span>
                  {:else}<span class="text-ink-muted">–</span>{/if}
                </EditableCell>
              </td>
              <td class="px-1 py-0.5">
                <EditableCell
                  grid="days"
                  {row}
                  col={3}
                  text={inputText(day, 'canopy')}
                  label={cellLabel(day, lai ? 'LAI' : 'Percent cover')}
                  {readOnly}
                  onsave={(t) => saveCell(day, 'canopy', t)}
                >
                  {#if day.canopy_entered !== null}<span class="font-medium"
                      >{formatNumber(day.canopy_entered, lai ? 2 : 0)}</span
                    >
                  {:else}<span class="text-ink-muted">{formatNumber(day.canopy, lai ? 2 : 0)}</span>{/if}
                </EditableCell>
              </td>
              <td class="px-2 py-1 font-medium tabular-nums {day.ad <= 0 ? 'text-status-irrigate-ink' : ''}"
                >{depth(day.ad)}</td
              >
              <td class="px-2 py-1 tabular-nums">{formatNumber(day.pct_moisture, 1)}</td>
              <td class="px-2 py-1 text-ink-muted tabular-nums"
                >{day.deep_drainage > 0 ? depth(day.deep_drainage) : ''}</td
              >
              <td class="px-1 py-0.5 text-left">
                <EditableCell
                  grid="days"
                  {row}
                  col={4}
                  align="left"
                  text={inputText(day, 'notes')}
                  label={cellLabel(day, 'Notes')}
                  {readOnly}
                  onsave={(t) => saveCell(day, 'notes', t)}
                >
                  <span class="block max-w-48 truncate text-ink-muted">{day.notes ?? ''}&nbsp;</span>
                </EditableCell>
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
    <p class="text-xs text-ink-muted">
      Rain in gray is modeled for the {noun}'s location; bold values are ones you entered.{#if plot}{' '}Irrigation
        marked “from field” was entered for the whole field.{/if} Irrigation marked “from {noun}” was entered on the
      <Link href={pivots.show(pivotId)} class="text-brand-600 underline underline-offset-2"
        >{noun}'s irrigation page</Link
      > or on the Daily entry page. * Crop ET is estimated from the past week because that day's weather is missing.
      {lai ? 'LAI' : 'Cover'} in gray is estimated: {planting?.effective_canopy_interpolation === 'curve'
        ? "the crop's typical curve, adjusted to your readings"
        : 'straight lines between your readings'}.
    </p>
  </div>
</CollapsibleSection>
