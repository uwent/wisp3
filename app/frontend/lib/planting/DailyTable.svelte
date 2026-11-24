<script lang="ts">
  import { Link } from '@inertiajs/svelte'

  import CollapsibleSection from '@/lib/components/CollapsibleSection.svelte'
  import EditableCell from '@/lib/components/EditableCell.svelte'
  import { formatDate } from '@/lib/dates'
  import { cellLabel, cellText, depthUnitName, type DayColumn } from '@/lib/fieldDays'
  import { ET_SOURCE_LABELS, rainOverridden } from '@/lib/provenance'
  import { formatNumber, type Units } from '@/lib/units'
  import { fields, systems } from '@/routes'
  import type { FieldDay, Planting } from '@/types/serializers'

  // The planting page's daily values: the season's days, latest first, its entries
  // edited in their cells (EditableCell, one grid); read-only while time travelling (asOf). plot: a
  // planting on part of the field, its size, whose rain is the field's
  let {
    days,
    planting,
    fieldId,
    systemId,
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
    systemId: number
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
  const head = 'sticky top-0 z-20 bg-surface-raised shadow-[inset_0_-1px_0_var(--color-line)]'
</script>

<CollapsibleSection title="Daily values" storageKey="daily">
  <div class="space-y-2">
    <p class="text-xs text-ink-muted">
      {#if readOnly}
        The season up to {formatDate(asOf)}. Depths are in {depthUnitName(units)}.
      {:else}
        Click a rain, irrigation, soil moisture, {lai ? 'LAI' : 'cover'} or notes cell to enter a value, and press Enter to
        save and move down. Clear a rain cell to go back to the modeled value. Depths are in {depthUnitName(units)}.
        From the keyboard, use the arrow keys to move between cells, and press Enter or start typing to edit one.
        {#if plot}
          Rain is the whole field's, so it's the same for every planting on it; irrigation, soil moisture readings and
          notes entered here are this planting's own. Irrigation entered for the whole field (on the
          <Link href={fields.show(fieldId)} class="text-brand-600 underline underline-offset-2">Field</Link> tab) fills it
          in when it had the field's amount.
        {/if}
      {/if}
    </p>
    <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
    <div
      class="max-h-144 overflow-auto rounded-lg border border-line bg-surface-raised"
      tabindex={readOnly ? 0 : undefined}
      role={readOnly ? 'region' : undefined}
      aria-label={readOnly ? 'Daily values' : undefined}
    >
      <table class="w-full text-sm">
        <!-- The headings stick, not the thead: a collapsed table's borders don't move with a sticky row, so
             each heading draws its rule as a shadow (DataTable does the same). The Date column stays at the
             left as the rest scroll under it. -->
        <thead class="text-xs text-ink-muted">
          <tr class="text-right">
            <th class="{head} left-0 z-30 px-3 py-2 text-left font-medium shadow-[inset_-1px_-1px_0_var(--color-line)]"
              >Date</th
            >
            <th class="{head} p-2 font-medium">Reference ET</th>
            <th class="{head} p-2 font-medium">Crop ET</th>
            <th class="{head} p-2 font-medium">Rain</th>
            <th class="{head} p-2 font-medium">Irrigation</th>
            <th class="{head} p-2 font-medium">Soil moisture reading (%)</th>
            <th class="{head} p-2 font-medium">{lai ? 'LAI' : 'Cover (%)'}</th>
            <th class="{head} p-2 font-medium">AD</th>
            <th class="{head} p-2 font-medium">Soil moisture (%)</th>
            <th class="{head} p-2 font-medium">Drainage</th>
            <th class="{head} p-2 text-left font-medium">Notes</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-line">
          {#each rows as day, row (day.date)}
            <tr class="text-right {day.ad <= 0 ? 'bg-status-irrigate/5' : ''}">
              <th
                scope="row"
                class="sticky left-0 z-10 px-3 py-1 text-left font-normal whitespace-nowrap shadow-[inset_-1px_0_0_var(--color-line)] {day.ad <=
                0
                  ? 'bg-[color-mix(in_oklab,var(--color-status-irrigate)_5%,var(--color-surface-raised))]'
                  : 'bg-surface-raised'}">{formatDate(day.date, { weekday: true })}</th
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
                  {/if}
                  <!-- A plot's view of its field's irrigation, when it differs (the field's isn't this plot's) -->
                  {#if day.field_inches !== null && day.field_inches !== day.irrigation}
                    <span class="block text-xs text-ink-muted">field {depth(day.field_inches)}</span>
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
      Rain in gray is modeled for the {noun}'s location; bold values are ones you entered.{#if plot}{' '}Under a plot's
        irrigation, the field's when it differs.{/if} Irrigation can also be entered for all the {noun}'s fields at once
      on the
      <Link href={systems.show(systemId)} class="text-brand-600 underline underline-offset-2"
        >{noun}'s irrigation page</Link
      > or the Daily entry page. * Crop ET is estimated from the past week because that day's weather is missing.
      {lai ? 'LAI' : 'Cover'} in gray is estimated: {planting?.effective_canopy_interpolation === 'curve'
        ? "the crop's typical curve, adjusted to your readings"
        : 'straight lines between your readings'}.
    </p>
  </div>
</CollapsibleSection>
