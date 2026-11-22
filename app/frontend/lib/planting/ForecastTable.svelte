<script lang="ts">
  import CollapsibleSection from '@/lib/components/CollapsibleSection.svelte'
  import EditableCell from '@/lib/components/EditableCell.svelte'
  import { formatDate } from '@/lib/dates'
  import { cellLabel, cellText, depthUnitName, type DayColumn } from '@/lib/fieldDays'
  import type { Units } from '@/lib/units'
  import type { FieldDay, PlantingSummary } from '@/types/serializers'

  // The planting page's projection (PLAN.md Phase 5): the days ahead, run through the balance with the
  // forecast, planned irrigation entered in its cells; time travelling (asOf), the days that followed,
  // read-only (replay: their weather was observed)
  let {
    days,
    summary,
    units,
    noun,
    asOf,
    replay,
    readOnly,
    onsave,
  }: {
    days: FieldDay[]
    summary: PlantingSummary
    units: Units
    /** "pivot", "drip block" */
    noun: string
    asOf: string | null
    replay: boolean
    readOnly: boolean
    onsave: (day: FieldDay, column: DayColumn, text: string) => Promise<string | null>
  } = $props()

  const depth = (value: number | null) => units.format('depth', value, { unit: false })
  const projectionByDate = $derived(new Map(summary?.projection.map((day) => [day.date, day]) ?? []))
  // A field using only entered rain also has a projection with no rain (Q7)
  const hasDry = $derived(summary?.projection.some((day) => day.dry_ad !== null) ?? false)
  const thresholdName = $derived(summary?.target_in === null ? 'of reaching 0 AD' : 'of falling below target')
  const inputText = (day: FieldDay, column: DayColumn) => cellText(day, column, units)
  const saveCell = (day: FieldDay, column: DayColumn, text: string) => onsave(day, column, text)
</script>

<!-- The projection, and planned irrigation -->
<CollapsibleSection
  title={replay ? `The ${days.length} days that followed` : `Next ${days.length} days`}
  storageKey="forecast"
>
  <div class="space-y-2">
    {#if replay}
      <p class="text-xs text-ink-muted">
        This is what happened after {formatDate(asOf)}: the weather that came for this location and what was entered for
        those days, run through the water balance where the forecast would have been. Depths are in
        {depthUnitName(units)}.
      </p>
    {:else}
      <p class="text-xs text-ink-muted">
        This is the forecast for this {noun}, run through the water balance. To plan irrigation, enter an amount on a
        future day. WISP counts it as applied when that day arrives, so change or clear it if your plans change. Depths
        are in {depthUnitName(units)}. From the keyboard, use the arrow keys to move between cells, and press Enter or
        start typing to edit one.
      </p>
    {/if}
    <!-- Read-only, nothing inside takes focus, so the box does, to scroll from the keyboard -->
    <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
    <div
      class="overflow-auto rounded-lg border border-line bg-surface-raised"
      tabindex={readOnly ? 0 : undefined}
      role={readOnly ? 'region' : undefined}
      aria-label={readOnly ? 'The days that followed' : undefined}
    >
      <table class="w-full text-sm">
        <thead class="border-b border-line text-xs text-ink-muted">
          <tr class="text-right">
            <th class="px-3 py-2 text-left font-medium">Date</th>
            <th class="px-2 py-2 font-medium">Crop ET</th>
            <th class="px-2 py-2 font-medium">Rain</th>
            <th class="px-2 py-2 font-medium">{replay ? 'Irrigation' : 'Planned irrigation'}</th>
            <th class="px-2 py-2 font-medium">AD</th>
            {#if hasDry}<th class="px-2 py-2 font-medium">AD if no rain</th>{/if}
            {#if summary?.ensemble_size}
              <th class="px-2 py-2 font-medium">Likely range</th>
              <th class="px-2 py-2 font-medium">Chance {thresholdName} by then</th>
            {/if}
          </tr>
        </thead>
        <tbody class="divide-y divide-line">
          {#each days as day, row (day.date)}
            {@const band = projectionByDate.get(day.date)}
            <tr class="text-right {day.ad <= (summary?.threshold ?? 0) ? 'bg-status-irrigate/5' : ''}">
              <th scope="row" class="px-3 py-1 text-left font-normal whitespace-nowrap"
                >{formatDate(day.date, { weekday: true })}</th
              >
              <td class="px-2 py-1 text-ink-muted tabular-nums">{depth(day.adj_et)}</td>
              <td class="px-2 py-1 tabular-nums">
                {#if day.rain_source === 'forecast' || day.rain_source === 'model' || day.rain_source === 'none'}<span
                    class="text-ink-muted">{depth(day.rain)}</span
                  >
                {:else}<span class="font-medium">{depth(day.rain)}</span>{/if}
              </td>
              <td class="px-1 py-0.5">
                <EditableCell
                  grid="forecast"
                  {row}
                  col={0}
                  text={inputText(day, 'irrigation_in')}
                  label={cellLabel(day, 'Planned irrigation')}
                  {readOnly}
                  onsave={(t) => saveCell(day, 'irrigation_in', t)}
                >
                  {#if day.irrigation_source === 'none'}<span class="text-ink-muted">–</span>
                  {:else}
                    <span class="font-medium">{depth(day.irrigation)}</span>
                  {/if}
                </EditableCell>
              </td>
              <td class="px-2 py-1 font-medium tabular-nums {day.ad <= 0 ? 'text-status-irrigate-ink' : ''}"
                >{depth(day.ad)}</td
              >
              {#if hasDry}
                {@const dryAd = band?.dry_ad ?? null}
                <td
                  class="px-2 py-1 text-ink-muted tabular-nums {dryAd !== null && dryAd <= 0
                    ? 'text-status-irrigate-ink'
                    : ''}">{depth(dryAd)}</td
                >
              {/if}
              {#if summary?.ensemble_size}
                <td class="px-2 py-1 whitespace-nowrap text-ink-muted tabular-nums">
                  {band?.p10 != null && band.p90 != null ? `${depth(band.p10)} to ${depth(band.p90)}` : ''}
                </td>
                <td class="px-2 py-1 tabular-nums">{band?.chance != null ? `${Math.round(band.chance * 100)}%` : ''}</td
                >
              {/if}
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  </div>
</CollapsibleSection>
