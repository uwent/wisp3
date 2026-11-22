<script lang="ts">
  import { Link, page, router } from '@inertiajs/svelte'
  import { tick } from 'svelte'
  import { MediaQuery } from 'svelte/reactivity'

  import Chart from '@/lib/charts/Chart.svelte'
  import { fieldChartOption, type FieldChartMode } from '@/lib/charts/fieldChart'
  import CollapsibleSection from '@/lib/components/CollapsibleSection.svelte'
  import FieldHeader from '@/lib/components/FieldHeader.svelte'
  import GlossaryText from '@/lib/components/GlossaryText.svelte'
  import Spinner from '@/lib/components/Spinner.svelte'
  import SeasonDetails from '@/lib/components/SeasonDetails.svelte'
  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import Term from '@/lib/components/Term.svelte'
  import ZoneWeather from '@/lib/components/ZoneWeather.svelte'
  import Cuttings from '@/lib/planting/Cuttings.svelte'
  import DailyTable from '@/lib/planting/DailyTable.svelte'
  import ForecastTable from '@/lib/planting/ForecastTable.svelte'
  import { addDays, currentYear, formatDate, relativeDay } from '@/lib/dates'
  import { KIND_NOUNS, type PivotKind } from '@/lib/geo'
  import { isExample } from '@/lib/permissions'
  import { guidance as guidanceFor } from '@/lib/guidance'
  import { outlook as outlookFor } from '@/lib/outlook'
  import { plotSize } from '@/lib/plantings'
  import { cellValue, type DayColumn } from '@/lib/fieldDays'
  import { pollWeather } from '@/lib/weatherPolling.svelte'
  import { rainSettingLink } from '@/lib/rainSetting'
  import { save } from '@/lib/save'
  import { seasonStats } from '@/lib/seasonStats'
  import { stickyHeight } from '@/lib/stickyBars'
  import { readStored, writeStored } from '@/lib/storage'
  import { count } from '@/lib/text'
  import { currentUnits, formatNumber } from '@/lib/units'
  import {
    dailyEntries,
    exportPlanting,
    fieldDays,
    planting as plantingRoute,
    plantings as plantingRoutes,
    setup,
  } from '@/routes'
  import type { Field, FieldDay, ForecastDay, Planting, PlantingSummary } from '@/types/serializers'

  let {
    field,
    pivot,
    farm,
    weather_updating,
    as_of,
    travel_dates,
    planting,
    exceeds_field_area,
    summary,
    days,
    forecast_days,
    weather_zone,
    forecast,
  }: {
    field: Field
    pivot: { id: number; name: string; kind: PivotKind; kind_name: string; pump_capacity_gpm: number | null }
    farm: { id: number; name: string }
    weather_updating: boolean
    /** Time travel (PLAN.md Phase 8 F): the earlier day the page shows, read-only; null for today */
    as_of: string | null
    /** The season's days before today, which time travel can pick; null if none */
    travel_dates: { from: string; to: string } | null
    planting: Planting
    /** Part-field plantings on the field at once add up to more than its area (a warning) */
    exceeds_field_area: boolean
    summary: PlantingSummary
    days: FieldDay[]
    forecast_days: FieldDay[]
    /** The zone the season ran on, and its week ahead for this year's plantings (not time travelling) */
    weather_zone: { id: number; name: string; location: string } | null
    forecast: ForecastDay[]
  } = $props()

  const units = $derived(currentUnits())
  // "pivot", "drip block"
  const noun = $derived(KIND_NOUNS[pivot.kind])
  // Time travelling, nothing on the page edits, and the projection is the weather that followed
  // Time travel, or the example farm (PLAN.md G.8), whose day is as_of when the season covers it
  // and which has no other day to travel to
  const example = $derived(isExample(page.props))
  const travelling = $derived(as_of !== null && !example)
  const readOnly = $derived(as_of !== null || example)
  const replay = $derived(summary?.projection_source === 'observed')

  // Whether the time travel card has scrolled up out of view, when the bar across the top takes over
  let cardGone = $state(false)
  function watchCard(card: HTMLElement) {
    const observer = new IntersectionObserver(([entry]) => {
      cardGone = !entry.isIntersecting && entry.boundingClientRect.top < 0
    })
    observer.observe(card)
    return () => {
      observer.disconnect()
      cardGone = false
    }
  }

  // The date picker for time travel, opened by the rewind-clock button; open while time travelling,
  // so the date in view can be changed or left
  // (a writable $derived: toggled by the button, reset whenever the page moves to another date)
  let travelOpen = $derived(as_of !== null)
  // The date picked, which View goes to: disabled on the date already in view
  let travelDate = $derived(as_of ?? travel_dates?.to ?? '')
  let dateInput: HTMLInputElement | undefined = $state()
  async function toggleTravel() {
    travelOpen = !travelOpen
    await tick()
    if (travelOpen) dateInput?.focus()
  }
  function travel(event: SubmitEvent) {
    event.preventDefault()
    const date = new FormData(event.currentTarget as HTMLFormElement).get('as_of')
    if (typeof date !== 'string' || !date) return
    router.get(plantingRoute(planting.id).url, { as_of: date })
  }

  // While the pivot's weather is being fetched, reload the season until it lands
  const weatherWait = pollWeather(() => (weather_updating ? [pivot.id] : []))
  const weatherState = $derived(weatherWait.state(weather_updating))
  const lai = $derived(planting?.et_method === 'lai')
  const outlook = $derived(summary && outlookFor(summary, units))
  // A field using only entered rain also has a projection with no rain (Q7)
  const hasDry = $derived(summary?.projection.some((day) => day.dry_ad !== null) ?? false)
  const stats = $derived(days.length ? seasonStats(days) : null)
  // Part of the field (G.11): rain is the field's; irrigation, readings and notes are this planting's
  const plot = $derived(planting.partial ? plotSize(planting, units) : null)

  // Past the crop's typical season and still running (often the Nov 30 default): offer to end it
  // today (PLAN.md Phase 8 G.2)
  const overdue = $derived(
    !readOnly &&
      summary.phase === 'active' &&
      summary.date !== null &&
      planting.effective_season_days !== null &&
      summary.date > addDays(planting.emergence_date, planting.effective_season_days),
  )
  function endSeason() {
    const today = summary.date!
    if (
      !confirm(
        `End this ${planting.plant_name.toLowerCase()} season today, ${formatDate(today)}? WISP stops tracking it and asking for readings. Its days so far stay, and you can change the harvest date in setup.`,
      )
    )
      return
    router.patch(plantingRoutes.update(planting.id).url, { planting: { end_date: today } }, { preserveScroll: true })
  }
  const guidance = $derived(
    planting &&
      guidanceFor(
        planting,
        units,
        summary?.tasks ?? [],
        summary?.phase === 'active' ? summary.date : null,
        summary?.canopy_fit ?? null,
        summary?.canopy_thermal ?? null,
      ),
  )
  // Whether "More about how … is modeled" is open: closed until opened, then remembered in this browser (G.6)
  const GUIDANCE_KEY = 'wisp:planting-guidance-more'
  let guidanceOpen = $state(readStored(GUIDANCE_KEY) === true)
  function toggleGuidance(open: boolean) {
    guidanceOpen = open
    writeStored(GUIDANCE_KEY, open)
  }
  let chartMode = $state<FieldChartMode>('ad')
  // A phone's width: the soil water chart names its thresholds inside the plot
  const narrowChart = new MediaQuery('max-width: 639px')
  // The season summary: open, like every section, until closed; links in the summary open it
  let summaryOpen = $state(true)

  // What it takes to refill the root zone to field capacity today
  const refill = $derived(
    summary?.ad !== null && summary?.ad !== undefined ? Math.max(0, summary.ad_max - summary.ad) : null,
  )

  // Soil moisture at a given AD: moisture is linear in AD, from the irrigation point (AD 0) to field
  // capacity (AD at its maximum)
  const moistureAt = (ad: number) =>
    summary
      ? summary.pct_at_ad_zero + ((summary.field_capacity_pct - summary.pct_at_ad_zero) * ad) / summary.ad_max
      : null
  // An ended season's day counts beside its totals (G.6): "24 days"
  const counted = (n: number) => (summary?.phase === 'ended' ? ` (${count(n, 'day')})` : '')

  async function saveCell(day: FieldDay, column: DayColumn, text: string): Promise<string | null> {
    const parsed = cellValue(column, text, units)
    if (!parsed.ok) return parsed.error
    // Only the balance changes; the weather and the rest of the page stay as they are
    return save(
      fieldDays.update({ fieldId: field.id, date: day.date }),
      { day: { [column]: parsed.value }, planting_id: planting!.id },
      { only: ['summary', 'days', 'forecast_days', 'errors'] },
    )
  }

  // "3 days ago" during the season; a plain date once it's over
  const when = (date: string) =>
    summary?.phase === 'active' && summary.date ? relativeDay(date, summary.date) : formatDate(date)
</script>

<svelte:head
  ><title>{travelling ? `As of ${formatDate(as_of)} · ` : ''}{planting.plant_name} · {field.name} · WISP</title
  ></svelte:head
>

<FieldHeader {field} {pivot} {farm} {units} year={planting.year} current={planting.id}>
  {#snippet actions()}
    {#if !readOnly}
      <a
        href={exportPlanting(planting.id).url}
        title="Download this season's daily values as a CSV file"
        class="rounded-md border border-line bg-surface-raised px-3 py-1.5 hover:bg-surface"
        download
      >
        Export CSV
      </a>
    {/if}
    {#if !readOnly}
      <Link
        href={setup.show({ query: { year: planting.year, planting: planting.id } })}
        title="Edit this planting on the setup page"
        class="rounded-md border border-line bg-surface-raised px-3 py-1.5 hover:bg-surface"
      >
        Edit in setup
      </Link>
    {/if}
    {#if travel_dates}
      <!-- Time travel: the clock stays at the row's right end, its date picker flying out to its left -->
      <div class="flex items-center gap-1">
        {#if travelOpen}
          <form id="time-travel" class="flex items-center gap-1" onsubmit={travel}>
            <label for="as-of" class="sr-only">Date to view</label>
            <input
              bind:this={dateInput}
              id="as-of"
              name="as_of"
              type="date"
              required
              min={travel_dates.from}
              max={travel_dates.to}
              bind:value={travelDate}
              title={`A day from ${formatDate(travel_dates.from)} to ${formatDate(travel_dates.to, { year: true })}`}
              class="rounded-md px-2 py-1.5 text-sm"
            />
            <button
              type="submit"
              disabled={!travelDate || travelDate === as_of}
              title={travelDate && travelDate === as_of
                ? 'Already viewing this date; pick another'
                : 'View this field as it was on the date picked'}
              class="rounded-md border border-line bg-surface-raised px-3 py-1.5 enabled:hover:bg-surface disabled:opacity-50"
              >View</button
            >
            {#if as_of}
              <Link
                href={plantingRoute(planting.id)}
                class="rounded-md border border-line bg-surface-raised px-3 py-1.5 hover:bg-surface"
                aria-label="Return to today"
                title="Return to today">Today</Link
              >
            {/if}
          </form>
        {/if}
        <button
          type="button"
          class="rounded-md border border-line bg-surface-raised p-1.5 hover:bg-surface
            {travelOpen || as_of ? 'text-brand-600' : 'text-ink-muted'}"
          aria-label="View this field on an earlier date"
          title="View this field on an earlier date"
          aria-expanded={travelOpen}
          aria-controls="time-travel"
          onclick={toggleTravel}
        >
          <!-- A clock with an arrow turning back -->
          <svg
            viewBox="0 0 24 24"
            class="size-5"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8" />
            <path d="M3 3v5h5" />
            <path d="M12 7v5l4 2" />
          </svg>
        </button>
      </div>
    {/if}
  {/snippet}
</FieldHeader>

{#if travelling}
  <!-- Time travel (PLAN.md Phase 8 F): this card explains it, and once it scrolls away a slim bar
       across the top of the window keeps the date and the way back in view -->
  <div role="status" class="rounded-lg border border-brand-500/40 bg-brand-50 px-4 py-3 text-sm" {@attach watchCard}>
    <p>
      Viewing {field.name} as of <strong>{formatDate(as_of, { year: true })}</strong>, with what's entered for the days
      up to then. Nothing can be changed here, and in place of the forecast, the days after it show what happened next.
      <Link
        href={plantingRoute(planting.id)}
        class="font-medium whitespace-nowrap text-brand-600 underline underline-offset-2">Return to today</Link
      >
    </p>
    <p class="mt-1 text-xs text-ink-muted">
      WISP doesn't keep a history of edits, so a value entered or changed later for one of these days shows as it is
      now.
    </p>
  </div>
  {#if cardGone}
    <div
      class="fixed inset-x-0 top-[var(--app-bar-h,0px)] z-40 border-b border-brand-500/40 bg-brand-50 shadow-sm"
      {@attach stickyHeight('--page-bar-h')}
      data-testid="time-travel-bar"
    >
      <p class="mx-auto flex max-w-6xl flex-wrap items-center gap-x-3 px-4 py-2 text-sm">
        <span>Viewing {field.name} as of <strong>{formatDate(as_of, { year: true })}</strong></span>
        <Link href={plantingRoute(planting.id)} class="font-medium text-brand-600 underline underline-offset-2"
          >Return to today</Link
        >
      </p>
    </div>
  {/if}
{/if}

{#if summary.weather_pending}
  <p role="status" class="flex items-start gap-2 rounded-lg border border-brand-500/40 bg-brand-50 px-4 py-3 text-sm">
    {#if weatherState === 'updating'}<Spinner class="mt-0.5" />{/if}
    <span>
      {#if weatherState === 'failed'}
        Weather update failed. Refresh the page to try again. Until weather arrives, WISP can't estimate crop water use,
        so the numbers below won't change.
      {:else}
        Weather for this location is on its way, usually within a few minutes of adding the {noun}. Until it arrives,
        WISP can't estimate crop water use, so the numbers below won't change.{#if weatherState === 'updating'}{' This page updates when it arrives.'}{/if}
      {/if}
    </span>
  </p>
{:else if weatherState === 'updating' && summary.phase !== 'ended'}
  <p role="status" class="flex items-center gap-1.5 text-sm text-ink-muted"><Spinner />Updating weather…</p>
{:else if weatherState === 'failed' && summary.phase !== 'ended'}
  <p role="status" class="text-sm text-status-caution-ink">Weather update failed. Refresh the page to try again.</p>
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
      Emerged {formatDate(planting.emergence_date)}{planting.vine_kill_date
        ? ` · vine kill ${formatDate(planting.vine_kill_date)}`
        : ''} · season {formatDate(planting.season_start)} – {formatDate(planting.end_date, { year: true })}
    </p>
    {#if overdue}
      <div class="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-md border border-line px-3 py-2 text-sm">
        <p class="text-ink-muted">
          Past {planting.season_days === null ? 'a typical' : 'its'}
          {planting.plant_name.toLowerCase()} season ({planting.effective_season_days} days from emergence). Harvested?
        </p>
        <button type="button" class="font-medium text-brand-600 underline underline-offset-2" onclick={endSeason}
          >End the season today</button
        >
      </div>
    {/if}
    {#if plot}
      <p class="text-sm">
        Part of the field: {plot}{#if planting.own_soil}{' '}<span class="text-ink-muted"
            >· its own soil ({formatNumber(summary.field_capacity_pct, 1)}% field capacity)</span
          >{/if}
      </p>
      {#if exceeds_field_area}
        <p role="status" class="rounded-md border border-status-caution/60 bg-status-caution/10 px-3 py-2 text-sm">
          The plantings on this field in season together cover more than its {units.format('area', field.area_acres)}.
          Check their sizes, or the field's area in setup.
        </p>
      {/if}
    {/if}
    {#if summary.phase === 'upcoming'}
      <p class="text-sm">The season starts {formatDate(summary.season_start, { year: true })}.</p>
    {:else}
      <!-- The outlook leads (G.6), then where the soil is -->
      {#if outlook}
        <div
          class="rounded-md border px-3 py-2 text-sm {outlook.urgent
            ? 'border-status-irrigate/50 bg-status-irrigate/5'
            : 'border-line'}"
        >
          <p class="font-medium">{outlook.headline}</p>
          <p class="text-ink-muted">
            {outlook.detail}{#if outlook.chance}{' '}{outlook.chance}{/if}
          </p>
          {#if outlook.dry}<p class="text-ink-muted">{outlook.dry}</p>{/if}
        </div>
      {:else if summary.phase === 'active' && refill !== null && refill > 0.005}
        <p class="text-sm">
          Refilling to field capacity takes about <strong>{units.format('depth', refill)}</strong>.
        </p>
      {/if}
      <p class="text-sm">
        {#if summary.phase === 'ended'}At the end of the season{:else if as_of}On {formatDate(as_of)}{:else}Today{/if}:
        <strong class="tabular-nums">{formatNumber(summary.pct_moisture, 1)}%</strong> soil moisture,
        <strong class="tabular-nums">{units.format('depth', summary.ad)}</strong>
        <Term id="ad">allowable depletion</Term> of {units.format('depth', summary.ad_max)}.
      </p>
    {/if}
  </div>

  <dl class="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
    <div>
      <dt class="text-ink-muted"><Term id="field_capacity">Field capacity</Term></dt>
      <dd class="tabular-nums">
        {formatNumber(summary.field_capacity_pct, 1)}% moisture (AD {units.format('depth', summary.ad_max)})
      </dd>
    </div>
    <div>
      <dt class="text-ink-muted">Target</dt>
      <dd class="tabular-nums">
        {summary.target_in === null
          ? 'Not set'
          : `${formatNumber(moistureAt(summary.target_in), 1)}% moisture (AD ${units.format('depth', summary.target_in)})`}
      </dd>
    </div>
    <div>
      <dt class="text-ink-muted">Irrigation point</dt>
      <dd class="tabular-nums">{formatNumber(summary.pct_at_ad_zero, 1)}% moisture (AD 0)</dd>
    </div>
    <div>
      <dt class="text-ink-muted">Root zone</dt>
      <dd class="tabular-nums">
        {units.format('rootDepth', planting.max_root_zone_depth)}, <Term id="mad">MAD</Term>
        {Math.round(planting.mad_frac * 100)}%
      </dd>
    </div>
    <div>
      <dt class="text-ink-muted">Last rain</dt>
      <dd>
        {summary.last_rain
          ? `${units.format('depth', summary.last_rain.inches)}, ${when(summary.last_rain.date)}`
          : 'None'}
      </dd>
    </div>
    <div>
      <dt class="text-ink-muted">Last irrigation</dt>
      <dd>
        {summary.last_irrigation
          ? `${units.format('depth', summary.last_irrigation.inches)}, ${when(summary.last_irrigation.date)}`
          : 'None'}
      </dd>
    </div>
  </dl>

  <div class="text-sm">
    <h3 class="font-medium">{summary.phase === 'ended' ? 'Season totals' : 'Totals so far'}</h3>
    <dl class="mt-1 grid grid-cols-2 gap-x-4 gap-y-1 tabular-nums">
      <dt class="text-ink-muted">Rain</dt>
      <dd>{units.format('depth', summary.totals.rain)}{counted(summary.totals.rain_days)}</dd>
      <dt class="text-ink-muted">Irrigation</dt>
      <dd>{units.format('depth', summary.totals.irrigation)}{counted(summary.totals.irrigation_days)}</dd>
      <dt class="text-ink-muted"><Term id="crop_et">Crop ET</Term></dt>
      <dd>{units.format('depth', summary.totals.adj_et)}</dd>
      <dt class="text-ink-muted"><Term id="deep_drainage">Deep drainage</Term></dt>
      <dd>{units.format('depth', summary.totals.deep_drainage)}{counted(summary.totals.drainage_days)}</dd>
      {#if summary.phase === 'ended'}
        <dt class="text-ink-muted">Below the irrigation point</dt>
        <dd>{summary.totals.stress_days ? count(summary.totals.stress_days, 'day') : 'Never'}</dd>
      {/if}
    </dl>
    {#if !summary.use_model_precip}
      <p class="mt-2 text-xs">
        Rain: <Term id="entered_rain_only">only what you enter</Term>, plus the forecast for the days ahead.
        {#if !readOnly}
          <Link
            href={rainSettingLink(summary.rain_group_id, summary.rain_farm_id)}
            class="text-brand-600 underline underline-offset-2">Change this</Link
          >
        {/if}
      </p>
    {/if}
    {#if summary.totals.entered_rain_days}
      <p class="mt-2 text-xs text-ink-muted">
        {summary.totals.entered_rain_days === 1
          ? 'On the day you entered rain'
          : `On the ${summary.totals.entered_rain_days} days you entered rain`}, your gauge read
        {units.format('depth', summary.totals.entered_rain)} and the model estimated {units.format(
          'depth',
          summary.totals.entered_rain_model,
        )}.
        <a
          href="#season-summary"
          class="text-brand-600 underline underline-offset-2"
          onclick={() => (summaryOpen = true)}>Compare day by day</a
        >
      </p>
    {/if}
  </div>

  {#if guidance && (guidance.readings.length || guidance.warning || guidance.irrigationCheck)}
    <!-- The readings that keep the model on track, each with when it was last entered; due ones marked (G.6) -->
    <div class="space-y-2 border-t border-line pt-3 text-sm lg:col-span-3">
      <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
        <h3 class="font-medium">Data entry</h3>
        {#if !readOnly && summary.phase === 'active'}
          <Link href={dailyEntries.show()} class="text-brand-600 underline underline-offset-2">Daily entry →</Link>
        {/if}
      </div>
      {#if guidance.irrigationCheck && !readOnly}
        <!-- Below the irrigation point for days with no irrigation entered: did they irrigate and not enter it? -->
        <p class="rounded-md border border-status-caution/60 bg-status-caution/10 px-3 py-2">
          <Link
            href={dailyEntries.show({ query: { date: guidance.irrigationCheck.date } })}
            class="underline underline-offset-2">{guidance.irrigationCheck.todo}</Link
          >
        </p>
      {/if}
      {#if guidance.warning}
        <p role="status" class="rounded-md border border-status-caution/60 bg-status-caution/10 px-3 py-2">
          {guidance.warning}
        </p>
      {/if}
      {#if guidance.readings.length}
        <ul class="flex flex-wrap gap-2" aria-label="Readings">
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
    </div>
  {/if}
  {#if guidance}
    <!-- Two sentences first, the rest on request (G.6), the card's full width -->
    <div class="border-t border-line pt-3 text-sm lg:col-span-3">
      <h3 class="font-medium">{guidance.title}</h3>
      <div class="mt-1 text-ink-muted">
        <GlossaryText paragraphs={[guidance.summary]} />
      </div>
      <details class="mt-2" open={guidanceOpen} ontoggle={(event) => toggleGuidance(event.currentTarget.open)}>
        <summary class="cursor-pointer text-brand-600 hover:underline">{guidance.more}</summary>
        <div class="mt-2 space-y-2 text-ink-muted">
          <GlossaryText paragraphs={guidance.paragraphs} />
        </div>
      </details>
    </div>
  {/if}
</section>

{#if planting.takes_cuttings}<Cuttings {planting} {readOnly} />{/if}

<ZoneWeather
  zone={weather_zone}
  {forecast}
  {units}
  query={planting.year === currentYear() ? {} : { year: planting.year }}
/>

{#if days.length}
  <!-- Chart -->
  <CollapsibleSection title="Soil water" storageKey="soil-water">
    {#snippet actions()}
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
    {/snippet}
    <div class="space-y-2 rounded-lg border border-line bg-surface-raised p-4">
      <Chart
        height="44rem"
        label="Soil water, water inputs and their totals, and the crop canopy over the season; the daily table below has the same values"
        build={(palette, view) =>
          fieldChartOption({
            days,
            forecastDays: forecast_days,
            summary: summary!,
            rootZoneDepth: planting!.max_root_zone_depth,
            units,
            mode: chartMode,
            palette,
            canopy: lai ? 'lai' : 'cover',
            vineKill: planting!.vine_kill_date,
            cuttings: planting!.cuttings.map((cutting) => cutting.date),
            view,
            narrow: narrowChart.current,
          })}
      />
      <p class="text-xs text-ink-muted">
        Dots on the line mark soil moisture readings. A dashed outline beside the rain shows the modeled rain where the
        balance didn't use it. The totals add up rain and irrigation from the first day in view, so zooming changes
        them. The bottom panel is the crop's {lai ? 'LAI' : 'canopy cover'} as the balance models it, with dots for your readings{#if planting?.canopy_curve}{' '}and
          a thin dashed line for the {planting.plant_name.toLowerCase()}
          curve as it would be without them{/if}. Scroll or drag the bar below to see the whole season.
      </p>
      {#if forecast_days.length && replay}
        <p class="text-xs text-ink-muted">
          After {formatDate(as_of)} the dashed line follows what happened next: the weather that came, and the rain, irrigation
          and soil moisture readings entered for those days.
          {#if hasDry}The dotted line is the same with no rain at all, since this field counts only the rain you enter.{/if}
        </p>
      {:else if forecast_days.length}
        <p class="text-xs text-ink-muted">
          After today the dashed line follows the forecast, including any irrigation you've planned. The shaded band
          shows where most of the {summary?.ensemble_size
            ? `${summary.ensemble_size} forecast scenarios fall (all but the highest and lowest tenth)`
            : 'forecast scenarios fall, once they are available'}.
          {#if hasDry}The dotted line is the same with no rain at all, since this field counts only the rain you enter.{/if}
        </p>
      {/if}
    </div>
  </CollapsibleSection>

  {#if forecast_days.length}
    <ForecastTable days={forecast_days} {summary} {units} {noun} asOf={as_of} {replay} {readOnly} onsave={saveCell} />
  {/if}

  <DailyTable
    {days}
    {planting}
    fieldId={field.id}
    pivotId={pivot.id}
    {units}
    {noun}
    {plot}
    asOf={as_of}
    {readOnly}
    onsave={saveCell}
  />
{/if}

<!-- The season in numbers, and settings for this field's balance (its setup is on the setup page) -->
{#if stats}
  <CollapsibleSection title="Season summary" id="season-summary" storageKey="season-summary" bind:open={summaryOpen}>
    <SeasonDetails {stats} {units} useModelPrecip={summary.use_model_precip} />
  </CollapsibleSection>
{/if}
