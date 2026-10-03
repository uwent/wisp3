<script lang="ts">
  import { Link, page, router } from '@inertiajs/svelte'

  import Chart from '@/lib/charts/Chart.svelte'
  import { fieldChartOption, type FieldChartMode } from '@/lib/charts/fieldChart'
  import { weatherChartOption, weatherPanels } from '@/lib/charts/weatherCharts'
  import EditableCell from '@/lib/components/EditableCell.svelte'
  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import { formatDate, relativeDay } from '@/lib/dates'
  import { ET_SOURCE_LABELS, rainOverridden } from '@/lib/provenance'
  import { save } from '@/lib/save'
  import { formatNumber, parseNumber, units as unitsFor } from '@/lib/units'
  import { exportPlanting, fieldDays, fieldGroups, fields, pivots, setup } from '@/routes'
  import type { Field, FieldDay, Planting, PlantingSummary, WeatherPanelDay } from '@/types/serializers'

  let {
    field,
    pivot,
    farm,
    field_groups,
    planting,
    summary,
    days,
    weather,
  }: {
    field: Field
    pivot: { id: number; name: string; pump_capacity_gpm: number | null }
    farm: { id: number; name: string }
    field_groups: { id: number; name: string }[]
    planting: Planting | null
    summary: PlantingSummary | null
    days: FieldDay[]
    weather: WeatherPanelDay[]
  } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const lai = $derived(planting?.et_method === 'lai')
  const rows = $derived([...days].reverse())
  let chartMode = $state<FieldChartMode>('ad')
  let showWeather = $state(true)

  const panels = $derived(
    weatherPanels(units, { fieldCapacity: field.effective_field_capacity, wiltingPoint: field.effective_perm_wilting_pt }),
  )

  // What it takes to refill the root zone to field capacity today
  const refill = $derived(summary?.ad !== null && summary?.ad !== undefined ? Math.max(0, summary.ad_max - summary.ad) : null)

  type Column = 'rain_in' | 'irrigation_in' | 'soil_moisture_pct' | 'canopy' | 'notes'
  const COLUMNS: Column[] = ['rain_in', 'irrigation_in', 'soil_moisture_pct', 'canopy', 'notes']

  function inputText(day: FieldDay, column: Column): string {
    switch (column) {
      case 'rain_in':
        return day.rain_source === 'entered' ? units.input('depth', day.rain) : ''
      case 'irrigation_in':
        return day.irrigation_source === 'entered' ? units.input('depth', day.irrigation) : ''
      case 'soil_moisture_pct':
        return day.moisture_source === 'entered' ? String(day.soil_moisture_pct) : ''
      case 'canopy':
        return day.canopy_entered === null ? '' : String(day.canopy_entered)
      case 'notes':
        return day.notes ?? ''
    }
  }

  async function saveCell(day: FieldDay, column: Column, text: string): Promise<string | null> {
    let value: number | string | null
    if (column === 'notes') {
      value = text.trim() || null
    } else {
      const parsed = column === 'rain_in' || column === 'irrigation_in' ? units.parse('depth', text) : parseNumber(text)
      if (!parsed.ok) return parsed.error
      value = parsed.value
    }
    return save(fieldDays.update({ fieldId: field.id, date: day.date }), {
      day: { [column]: value },
      planting_id: planting!.id,
    })
  }

  const cellLabel = (day: FieldDay, what: string) => `${what}, ${formatDate(day.date, { weekday: true })}`
  const depth = (value: number | null) => units.format('depth', value, { unit: false })
  // "3 days ago" during the season; a plain date once it's over
  const when = (date: string) => (summary?.phase === 'active' && summary.date ? relativeDay(date, summary.date) : formatDate(date))
</script>

<svelte:head><title>{field.name} · WISP</title></svelte:head>

<div class="flex flex-wrap items-end justify-between gap-3">
  <div class="min-w-0">
    <p class="text-sm text-ink-muted">
      {farm.name} · <Link href={pivots.show(pivot.id)} class="hover:underline">{pivot.name}</Link>
    </p>
    <h1 class="text-2xl font-semibold">{field.name}</h1>
    <p class="text-sm text-ink-muted">
      {units.format('area', field.area_acres)} · {field.soil_type_name} (field capacity {formatNumber(field.effective_field_capacity * 100, 1)}%,
      wilting point {formatNumber(field.effective_perm_wilting_pt * 100, 1)}%)
      {#if field_groups.length}
        · in {#each field_groups as group, i (group.id)}{i ? ', ' : ''}<Link href={fieldGroups.show(group.id)} class="text-brand-600 hover:underline">{group.name}</Link>{/each}
      {/if}
    </p>
  </div>
  <div class="flex flex-wrap items-center gap-2 text-sm">
    {#if field.plantings.length > 1}
      <label for="planting" class="sr-only">Season</label>
      <select
        id="planting"
        class="rounded-md text-sm"
        value={planting?.id}
        onchange={(e) => router.get(fields.show(field.id).url, { planting_id: e.currentTarget.value })}
      >
        {#each field.plantings as p (p.id)}<option value={p.id}>{p.year} {p.plant_name}</option>{/each}
      </select>
    {/if}
    {#if planting}
      <a href={exportPlanting(planting.id).url} class="rounded-md border border-line bg-surface-raised px-3 py-1.5 hover:bg-surface" download>
        Export CSV
      </a>
    {/if}
    <Link href={setup.show({ query: planting ? { year: planting.year } : {} })} class="rounded-md border border-line bg-surface-raised px-3 py-1.5 hover:bg-surface">
      Edit in setup
    </Link>
  </div>
</div>

{#if !planting || !summary}
  <section class="rounded-lg border border-dashed border-line bg-surface-raised px-6 py-12 text-center">
    <h2 class="text-lg font-medium">No crop on this field yet</h2>
    <p class="mt-2 text-sm text-ink-muted">Add this season's crop in setup to start the water balance.</p>
    <Link href={setup.show()} class="mt-4 inline-block text-sm text-brand-600 hover:underline">Go to setup</Link>
  </section>
{:else}
  <!-- Summary -->
  <section class="grid gap-4 rounded-lg border border-line bg-surface-raised p-4 sm:p-6 lg:grid-cols-3">
    <div class="space-y-2">
      <div class="flex items-center gap-3">
        <h2 class="text-lg font-medium">
          {planting.plant_name}{#if planting.variety}{' '}<span class="text-ink-muted">({planting.variety})</span>{/if}
        </h2>
        {#if summary.phase === 'active'}<StatusBadge status={summary.status} />{/if}
      </div>
      <p class="text-sm text-ink-muted">
        Emerged {formatDate(planting.emergence_date)} · season {formatDate(planting.season_start)} – {formatDate(planting.end_date, { year: true })}
      </p>
      {#if summary.phase === 'upcoming'}
        <p class="text-sm">The season starts {formatDate(summary.season_start, { year: true })}.</p>
      {:else}
        <p class="text-sm">
          {#if summary.phase === 'ended'}At the end of the season{:else}Today{/if}:
          <strong class="tabular-nums">{units.format('depth', summary.ad)}</strong> allowable depletion of
          {units.format('depth', summary.ad_max)}, <strong>{formatNumber(summary.pct_moisture, 1)}%</strong> soil moisture.
        </p>
        {#if summary.phase === 'active' && refill !== null && refill > 0.005}
          <p class="text-sm">Refilling to field capacity takes about <strong>{units.format('depth', refill)}</strong>.</p>
        {/if}
      {/if}
    </div>

    <dl class="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
      <div><dt class="text-ink-muted">At field capacity</dt><dd class="tabular-nums">{units.format('depth', summary.ad_max)} AD</dd></div>
      <div>
        <dt class="text-ink-muted">Target</dt>
        <dd class="tabular-nums">{summary.target_in === null ? 'Not set' : `${units.format('depth', summary.target_in)} AD`}</dd>
      </div>
      <div><dt class="text-ink-muted">Irrigate at</dt><dd class="tabular-nums">0 AD ({formatNumber(summary.pct_at_ad_zero, 1)}% moisture)</dd></div>
      <div><dt class="text-ink-muted">Root zone</dt><dd class="tabular-nums">{units.format('rootDepth', planting.max_root_zone_depth)}, MAD {Math.round(planting.mad_frac * 100)}%</dd></div>
      <div>
        <dt class="text-ink-muted">Last rain</dt>
        <dd>{summary.last_rain ? `${units.format('depth', summary.last_rain.inches)}, ${when(summary.last_rain.date)}` : 'None'}</dd>
      </div>
      <div>
        <dt class="text-ink-muted">Last irrigation</dt>
        <dd>{summary.last_irrigation ? `${units.format('depth', summary.last_irrigation.inches)}, ${when(summary.last_irrigation.date)}` : 'None'}</dd>
      </div>
    </dl>

    <div class="text-sm">
      <h3 class="font-medium">Season so far</h3>
      <dl class="mt-1 grid grid-cols-2 gap-x-4 gap-y-1 tabular-nums">
        <dt class="text-ink-muted">Rain</dt><dd>{units.format('depth', summary.totals.rain)}</dd>
        <dt class="text-ink-muted">Irrigation</dt><dd>{units.format('depth', summary.totals.irrigation)}</dd>
        <dt class="text-ink-muted">Crop ET</dt><dd>{units.format('depth', summary.totals.adj_et)}</dd>
        <dt class="text-ink-muted">Deep drainage</dt><dd>{units.format('depth', summary.totals.deep_drainage)}</dd>
      </dl>
      {#if summary.totals.entered_rain_days}
        <p class="mt-2 text-xs text-ink-muted">
          On the {summary.totals.entered_rain_days} days with entered rain, your gauge read
          {units.format('depth', summary.totals.entered_rain)} and the model {units.format('depth', summary.totals.entered_rain_model)}.
        </p>
      {/if}
    </div>
  </section>

  {#if days.length}
    <!-- Chart -->
    <section class="space-y-2 rounded-lg border border-line bg-surface-raised p-4">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h2 class="font-medium">Soil water</h2>
        <div class="flex overflow-hidden rounded-md border border-line text-xs" role="group" aria-label="Show">
          {#each [['ad', `AD (${units.label('depth')})`], ['moisture', 'Soil moisture (%)']] as const as [mode, name] (mode)}
            <button
              type="button"
              class="px-3 py-1.5 {chartMode === mode ? 'bg-brand-600 text-white dark:text-surface' : 'hover:bg-surface'}"
              aria-pressed={chartMode === mode}
              onclick={() => (chartMode = mode)}>{name}</button
            >
          {/each}
        </div>
      </div>
      <Chart
        height="26rem"
        label="Soil water and water inputs over the season; the daily table below has the same values"
        build={(palette) =>
          fieldChartOption({ days, summary: summary!, rootZoneDepth: planting!.max_root_zone_depth, units, mode: chartMode, palette })}
      />
      <p class="text-xs text-ink-muted">
        Dots on the line mark soil moisture readings. A dashed outline shows the modeled rain on days you entered your own.
        Scroll or drag the bar below to see the whole season.
      </p>
    </section>

    <!-- Daily grid -->
    <section class="space-y-2">
      <div class="flex flex-wrap items-end justify-between gap-2">
        <div>
          <h2 class="font-medium">Daily values</h2>
          <p class="text-xs text-ink-muted">
            Click a rain, irrigation, moisture, {lai ? 'LAI' : 'cover'} or notes cell to enter a value; Enter saves and moves
            down. Clear a cell to go back to the modeled or pivot value. Depths in {units.label('depth')}.
          </p>
        </div>
      </div>
      <div class="max-h-[36rem] overflow-auto rounded-lg border border-line bg-surface-raised">
        <table class="w-full text-sm">
          <thead class="sticky top-0 z-10 border-b border-line bg-surface-raised text-xs text-ink-muted">
            <tr class="text-right">
              <th class="px-3 py-2 text-left font-medium">Date</th>
              <th class="px-2 py-2 font-medium">Ref ET</th>
              <th class="px-2 py-2 font-medium">Crop ET</th>
              <th class="px-2 py-2 font-medium">Rain</th>
              <th class="px-2 py-2 font-medium">Irrigation</th>
              <th class="px-2 py-2 font-medium">Moisture reading (%)</th>
              <th class="px-2 py-2 font-medium">{lai ? 'LAI' : 'Cover (%)'}</th>
              <th class="px-2 py-2 font-medium">AD</th>
              <th class="px-2 py-2 font-medium">Moisture (%)</th>
              <th class="px-2 py-2 font-medium">Drainage</th>
              <th class="px-2 py-2 text-left font-medium">Notes</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-line">
            {#each rows as day, row (day.date)}
              <tr class="text-right {day.ad <= 0 ? 'bg-status-irrigate/5' : ''}">
                <th scope="row" class="px-3 py-1 text-left font-normal whitespace-nowrap">{formatDate(day.date, { weekday: true })}</th>
                <td class="px-2 py-1 tabular-nums {day.et0_source === 'missing' ? 'text-ink-muted' : ''}">{depth(day.et0)}</td>
                <td class="px-2 py-1 tabular-nums" title={ET_SOURCE_LABELS[day.et_source]}>
                  {depth(day.adj_et)}{#if day.et_source === 'gap_fill'}<span class="text-ink-muted">*</span>{/if}
                </td>
                <td class="px-1 py-0.5">
                  <EditableCell grid="days" {row} col={0} text={inputText(day, 'rain_in')} label={cellLabel(day, 'Rain')} onsave={(t) => saveCell(day, 'rain_in', t)}>
                    {#if day.rain_source === 'model' || day.rain_source === 'missing' || day.rain_source === 'none'}
                      <span class="text-ink-muted">{depth(day.rain)}</span>
                    {:else}
                      <span class="font-medium">{depth(day.rain)}</span>
                      {#if day.rain_source === 'group'}<span class="ml-1 text-xs text-brand-600">group</span>{/if}
                      {#if rainOverridden(day)}<span class="block text-xs text-ink-muted">model {depth(day.rain_model)}</span>{/if}
                    {/if}
                  </EditableCell>
                </td>
                <td class="px-1 py-0.5">
                  <EditableCell grid="days" {row} col={1} text={inputText(day, 'irrigation_in')} label={cellLabel(day, 'Irrigation')} onsave={(t) => saveCell(day, 'irrigation_in', t)}>
                    {#if day.irrigation_source === 'none'}
                      <span class="text-ink-muted">–</span>
                    {:else}
                      <span class="font-medium">{depth(day.irrigation)}</span>
                      {#if day.irrigation_source === 'pivot'}<span class="ml-1 text-xs text-brand-600">pivot</span>{/if}
                      {#if day.irrigation_source === 'group'}<span class="ml-1 text-xs text-brand-600">group</span>{/if}
                      {#if day.irrigation_source === 'entered' && day.pivot_inches !== null}
                        <span class="block text-xs text-ink-muted">pivot {depth(day.pivot_inches)}</span>
                      {/if}
                    {/if}
                  </EditableCell>
                </td>
                <td class="px-1 py-0.5">
                  <EditableCell grid="days" {row} col={2} text={inputText(day, 'soil_moisture_pct')} label={cellLabel(day, 'Soil moisture reading')} onsave={(t) => saveCell(day, 'soil_moisture_pct', t)}>
                    {#if day.soil_moisture_pct !== null}
                      <span class="font-medium">{day.soil_moisture_pct}</span>
                      {#if day.moisture_source === 'group'}<span class="ml-1 text-xs text-brand-600">group</span>{/if}
                    {:else}<span class="text-ink-muted">–</span>{/if}
                  </EditableCell>
                </td>
                <td class="px-1 py-0.5">
                  <EditableCell grid="days" {row} col={3} text={inputText(day, 'canopy')} label={cellLabel(day, lai ? 'LAI' : 'Percent cover')} onsave={(t) => saveCell(day, 'canopy', t)}>
                    {#if day.canopy_entered !== null}<span class="font-medium">{formatNumber(day.canopy_entered, lai ? 2 : 0)}</span>
                    {:else}<span class="text-ink-muted">{formatNumber(day.canopy, lai ? 2 : 0)}</span>{/if}
                  </EditableCell>
                </td>
                <td class="px-2 py-1 font-medium tabular-nums {day.ad <= 0 ? 'text-status-irrigate' : ''}">{depth(day.ad)}</td>
                <td class="px-2 py-1 tabular-nums">{formatNumber(day.pct_moisture, 1)}</td>
                <td class="px-2 py-1 tabular-nums text-ink-muted">{day.deep_drainage > 0 ? depth(day.deep_drainage) : ''}</td>
                <td class="px-1 py-0.5 text-left">
                  <EditableCell grid="days" {row} col={4} align="left" text={inputText(day, 'notes')} label={cellLabel(day, 'Notes')} onsave={(t) => saveCell(day, 'notes', t)}>
                    <span class="block max-w-48 truncate text-ink-muted">{day.notes ?? ''}&nbsp;</span>
                  </EditableCell>
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
      <p class="text-xs text-ink-muted">
        Muted rain is modeled for the pivot's location; bold values were entered.
        Irrigation marked “pivot” is entered on the
        <Link href={pivots.show(pivot.id)} class="text-brand-600 hover:underline">pivot's irrigation page</Link> or in daily entry.
        * Crop ET estimated from the past week because the day's weather is missing. {lai ? 'LAI' : 'Cover'} in muted text is interpolated between your readings.
      </p>
    </section>
  {/if}

  {#if weather.length}
    <section class="space-y-3">
      <div class="flex items-center justify-between">
        <h2 class="font-medium">Weather at this pivot</h2>
        <button type="button" class="text-sm text-brand-600 hover:underline" onclick={() => (showWeather = !showWeather)} aria-expanded={showWeather}>
          {showWeather ? 'Hide' : 'Show'}
        </button>
      </div>
      {#if showWeather}
        <p class="text-xs text-ink-muted">
          Modeled by Open-Meteo for the pivot's grid cell, with the forecast shaded. Soil moisture is the weather model's own
          estimate, not this field's balance; it's shown against the field's capacity and wilting point for comparison.
        </p>
        <div class="grid gap-3 md:grid-cols-2">
          {#each panels as panel (panel.key)}
            <div class="rounded-lg border border-line bg-surface-raised p-3">
              <h3 class="text-sm font-medium">{panel.title} <span class="font-normal text-ink-muted">({panel.unit(units)})</span></h3>
              <Chart height="12rem" label={panel.title} build={(palette) => weatherChartOption(panel, weather, units, palette)} />
            </div>
          {/each}
        </div>
      {/if}
    </section>
  {/if}
{/if}
