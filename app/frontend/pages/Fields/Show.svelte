<script lang="ts">
  import { Link, page, router } from '@inertiajs/svelte'
  import { slide } from 'svelte/transition'

  import Chart from '@/lib/charts/Chart.svelte'
  import { fieldChartOption, type FieldChartMode } from '@/lib/charts/fieldChart'
  import { weatherPanels } from '@/lib/charts/weatherCharts'
  import WeatherSection from '@/lib/charts/WeatherSection.svelte'
  import EditableCell from '@/lib/components/EditableCell.svelte'
  import GlossaryText from '@/lib/components/GlossaryText.svelte'
  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import Term from '@/lib/components/Term.svelte'
  import { formatDate, relativeDay } from '@/lib/dates'
  import { guidance as guidanceFor } from '@/lib/guidance'
  import { outlook as outlookFor } from '@/lib/outlook'
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
    forecast_days,
    weather,
  }: {
    field: Field
    pivot: { id: number; name: string; pump_capacity_gpm: number | null }
    farm: { id: number; name: string }
    field_groups: { id: number; name: string }[]
    planting: Planting | null
    summary: PlantingSummary | null
    days: FieldDay[]
    forecast_days: FieldDay[]
    weather: WeatherPanelDay[]
  } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const lai = $derived(planting?.et_method === 'lai')
  const rows = $derived([...days].reverse())
  const outlook = $derived(summary && outlookFor(summary, units))
  const projectionByDate = $derived(new Map(summary?.projection.map((day) => [day.date, day]) ?? []))
  const guidance = $derived(
    planting && guidanceFor(planting, days, units, summary?.phase === 'active' ? summary.date : null),
  )
  // Whether "How … is modeled" is open: open until closed, then remembered in this browser
  const GUIDANCE_KEY = 'wisp:field-guidance-open'
  let guidanceOpen = $state(true)
  try {
    guidanceOpen = localStorage.getItem(GUIDANCE_KEY) !== 'false'
  } catch {
    // Storage blocked: stay open
  }
  function toggleGuidance(open: boolean) {
    guidanceOpen = open
    try {
      localStorage.setItem(GUIDANCE_KEY, String(open))
    } catch {
      // Storage blocked: only this page view remembers
    }
  }
  const thresholdName = $derived(summary?.target_in === null ? 'at 0 AD' : 'below target')
  let chartMode = $state<FieldChartMode>('ad')
  let forecastOpen = $state(true)
  let dailyOpen = $state(true)

  // Crop ET by date, as a string so the weather charts rebuild only when it changes (an edit to
  // rain or irrigation reloads the days, but leaves ET alone)
  const cropEtJson = $derived(JSON.stringify(Object.fromEntries(days.map((day) => [day.date, day.adj_et]))))
  const panels = $derived(
    weatherPanels(units, {
      field: { fieldCapacity: field.effective_field_capacity, wiltingPoint: field.effective_perm_wilting_pt },
      cropEt: JSON.parse(cropEtJson),
    }),
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
    // Only the balance changes; the weather and the rest of the page stay as they are
    return save(
      fieldDays.update({ fieldId: field.id, date: day.date }),
      { day: { [column]: value }, planting_id: planting!.id },
      { only: ['summary', 'days', 'forecast_days', 'errors'] },
    )
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
  {#if summary.weather_pending}
    <p role="status" class="rounded-lg border border-brand-500/40 bg-brand-50 px-4 py-3 text-sm">
      Weather for this pivot is on the way, usually within a few minutes of adding it. Until it arrives there's no ET,
      so the water balance below stays flat.
    </p>
  {/if}
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
          <strong class="tabular-nums">{units.format('depth', summary.ad)}</strong> <Term id="ad">allowable depletion</Term> of
          {units.format('depth', summary.ad_max)}, <strong>{formatNumber(summary.pct_moisture, 1)}%</strong> soil moisture.
        </p>
        {#if outlook}
          <div class="rounded-md border px-3 py-2 text-sm {outlook.urgent ? 'border-status-irrigate/50 bg-status-irrigate/5' : 'border-line'}">
            <p class="font-medium">{outlook.headline}</p>
            <p class="text-ink-muted">{outlook.detail}{#if outlook.chance}{' '}{outlook.chance}{/if}</p>
          </div>
        {:else if summary.phase === 'active' && refill !== null && refill > 0.005}
          <p class="text-sm">Refilling to field capacity takes about <strong>{units.format('depth', refill)}</strong>.</p>
        {/if}
      {/if}
    </div>

    <dl class="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
      <div><dt class="text-ink-muted">At <Term id="field_capacity">field capacity</Term></dt><dd class="tabular-nums">{units.format('depth', summary.ad_max)} AD</dd></div>
      <div>
        <dt class="text-ink-muted">Target</dt>
        <dd class="tabular-nums">{summary.target_in === null ? 'Not set' : `${units.format('depth', summary.target_in)} AD`}</dd>
      </div>
      <div><dt class="text-ink-muted">Irrigate at</dt><dd class="tabular-nums">0 AD ({formatNumber(summary.pct_at_ad_zero, 1)}% moisture)</dd></div>
      <div><dt class="text-ink-muted">Root zone</dt><dd class="tabular-nums">{units.format('rootDepth', planting.max_root_zone_depth)}, <Term id="mad">MAD</Term> {Math.round(planting.mad_frac * 100)}%</dd></div>
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
        <dt class="text-ink-muted"><Term id="crop_et">Crop ET</Term></dt><dd>{units.format('depth', summary.totals.adj_et)}</dd>
        <dt class="text-ink-muted"><Term id="deep_drainage">Deep drainage</Term></dt><dd>{units.format('depth', summary.totals.deep_drainage)}</dd>
      </dl>
      {#if summary.totals.entered_rain_days}
        <p class="mt-2 text-xs text-ink-muted">
          On the {summary.totals.entered_rain_days} days with entered rain, your gauge read
          {units.format('depth', summary.totals.entered_rain)} and the model {units.format('depth', summary.totals.entered_rain_model)}.
        </p>
      {/if}
    </div>

    {#if guidance}
      <details
        class="border-t border-line pt-3 text-sm lg:col-span-3"
        open={guidanceOpen}
        ontoggle={(event) => toggleGuidance(event.currentTarget.open)}
      >
        <summary class="cursor-pointer font-medium">{guidance.title}</summary>
        <div class="mt-2 max-w-3xl space-y-2 text-ink-muted">
          <GlossaryText paragraphs={guidance.paragraphs} />
        </div>
        {#if guidance.readings.length}
          <ul class="mt-3 flex flex-wrap gap-2" aria-label="Last readings">
            {#each guidance.readings as reading (reading.label)}
              <li
                class="rounded-md border px-2.5 py-1 text-xs
                  {reading.due ? 'border-status-caution/60 bg-status-caution/10' : 'border-line'}"
              >
                <span class="font-medium">{reading.label}:</span>
                {reading.last}{#if reading.note}{' '}<span class="text-ink-muted">· {reading.note}</span>{/if}
              </li>
            {/each}
          </ul>
        {/if}
      </details>
    {/if}
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
          fieldChartOption({
            days,
            forecastDays: forecast_days,
            summary: summary!,
            rootZoneDepth: planting!.max_root_zone_depth,
            units,
            mode: chartMode,
            palette,
          })}
      />
      <p class="text-xs text-ink-muted">
        Dots on the line mark soil moisture readings. A dashed outline shows the modeled rain on days you entered your own.
        {#if forecast_days.length}
          After today the dashed line follows the forecast, with planned irrigation; the shaded band is the range of
          {summary?.ensemble_size ? `${summary.ensemble_size} forecast scenarios (10th to 90th percentile)` : 'forecast scenarios, once they arrive'}.
        {/if}
        Scroll or drag the bar below to see the whole season.
      </p>
    </section>

    {#if forecast_days.length}
      <!-- The projection, and planned irrigation -->
      <section class="space-y-2">
        <div class="flex items-center justify-between">
          <h2 class="font-medium">Next {forecast_days.length} days</h2>
          <button type="button" class="text-sm text-brand-600 hover:underline" onclick={() => (forecastOpen = !forecastOpen)} aria-expanded={forecastOpen}>
            {forecastOpen ? 'Hide' : 'Show'}
          </button>
        </div>
        {#if forecastOpen}
          <div class="space-y-2" transition:slide={{ duration: 200 }}>
            <p class="text-xs text-ink-muted">
              The forecast for this pivot run through the water balance. Plan irrigation by entering it on a future day; it
              counts as applied when the day comes, so change or clear it if plans change. Depths in {units.label('depth')}.
            </p>
            <div class="overflow-auto rounded-lg border border-line bg-surface-raised">
              <table class="w-full text-sm">
                <thead class="border-b border-line text-xs text-ink-muted">
                  <tr class="text-right">
                    <th class="px-3 py-2 text-left font-medium">Date</th>
                    <th class="px-2 py-2 font-medium">Crop ET</th>
                    <th class="px-2 py-2 font-medium">Rain</th>
                    <th class="px-2 py-2 font-medium">Planned irrigation</th>
                    <th class="px-2 py-2 font-medium">AD</th>
                    {#if summary?.ensemble_size}
                      <th class="px-2 py-2 font-medium">Range (10–90%)</th>
                      <th class="px-2 py-2 font-medium">Chance {thresholdName} by then</th>
                    {/if}
                  </tr>
                </thead>
                <tbody class="divide-y divide-line">
                  {#each forecast_days as day, row (day.date)}
                    {@const band = projectionByDate.get(day.date)}
                    <tr class="text-right {day.ad <= (summary?.threshold ?? 0) ? 'bg-status-irrigate/5' : ''}">
                      <th scope="row" class="px-3 py-1 text-left font-normal whitespace-nowrap">{formatDate(day.date, { weekday: true })}</th>
                      <td class="px-2 py-1 text-ink-muted tabular-nums">{depth(day.adj_et)}</td>
                      <td class="px-2 py-1 tabular-nums">
                        {#if day.rain_source === 'forecast' || day.rain_source === 'none'}<span class="text-ink-muted">{depth(day.rain)}</span>
                        {:else}<span class="font-medium">{depth(day.rain)}</span>{/if}
                      </td>
                      <td class="px-1 py-0.5">
                        <EditableCell grid="forecast" {row} col={0} text={inputText(day, 'irrigation_in')} label={cellLabel(day, 'Planned irrigation')} onsave={(t) => saveCell(day, 'irrigation_in', t)}>
                          {#if day.irrigation_source === 'none'}<span class="text-ink-muted">–</span>
                          {:else}
                            <span class="font-medium">{depth(day.irrigation)}</span>
                            {#if day.irrigation_source !== 'entered'}<span class="ml-1 text-xs text-brand-600">{day.irrigation_source}</span>{/if}
                          {/if}
                        </EditableCell>
                      </td>
                      <td class="px-2 py-1 font-medium tabular-nums {day.ad <= 0 ? 'text-status-irrigate' : ''}">{depth(day.ad)}</td>
                      {#if summary?.ensemble_size}
                        <td class="px-2 py-1 text-ink-muted tabular-nums whitespace-nowrap">
                          {band?.p10 != null && band.p90 != null ? `${depth(band.p10)} to ${depth(band.p90)}` : ''}
                        </td>
                        <td class="px-2 py-1 tabular-nums">{band?.chance != null ? `${Math.round(band.chance * 100)}%` : ''}</td>
                      {/if}
                    </tr>
                  {/each}
                </tbody>
              </table>
            </div>
          </div>
        {/if}
      </section>
    {/if}

    <!-- Daily grid -->
    <section class="space-y-2">
      <div class="flex items-center justify-between">
        <h2 class="font-medium">Daily values</h2>
        <button type="button" class="text-sm text-brand-600 hover:underline" onclick={() => (dailyOpen = !dailyOpen)} aria-expanded={dailyOpen}>
          {dailyOpen ? 'Hide' : 'Show'}
        </button>
      </div>
      {#if dailyOpen}
        <div class="space-y-2" transition:slide={{ duration: 200 }}>
          <p class="text-xs text-ink-muted">
            Click a rain, irrigation, moisture, {lai ? 'LAI' : 'cover'} or notes cell to enter a value; Enter saves and moves
            down. Clear a cell to go back to the modeled or pivot value. Depths in {units.label('depth')}.
          </p>
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
        </div>
      {/if}
    </section>
  {/if}

  <WeatherSection {panels} days={weather} {units}>
    Soil moisture is the model's own estimate, not this field's balance; it's shown against the field's capacity and
    wilting point for comparison.
  </WeatherSection>
{/if}
