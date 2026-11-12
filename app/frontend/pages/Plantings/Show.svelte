<script lang="ts">
  import { Form, Link, page, router } from '@inertiajs/svelte'
  import { tick } from 'svelte'

  import Chart from '@/lib/charts/Chart.svelte'
  import { fieldChartOption, type FieldChartMode } from '@/lib/charts/fieldChart'
  import { weatherPanels } from '@/lib/charts/weatherCharts'
  import WeatherSection from '@/lib/charts/WeatherSection.svelte'
  import Button from '@/lib/components/Button.svelte'
  import CollapsibleSection from '@/lib/components/CollapsibleSection.svelte'
  import EditableCell from '@/lib/components/EditableCell.svelte'
  import FieldHeader from '@/lib/components/FieldHeader.svelte'
  import GlossaryText from '@/lib/components/GlossaryText.svelte'
  import Spinner from '@/lib/components/Spinner.svelte'
  import SeasonDetails from '@/lib/components/SeasonDetails.svelte'
  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import Term from '@/lib/components/Term.svelte'
  import { addDays, formatDate, relativeDay } from '@/lib/dates'
  import { guidance as guidanceFor } from '@/lib/guidance'
  import { outlook as outlookFor } from '@/lib/outlook'
  import { plotSize } from '@/lib/plantings'
  import { poll, weatherUpdate } from '@/lib/poll'
  import { ET_SOURCE_LABELS, rainOverridden } from '@/lib/provenance'
  import { save } from '@/lib/save'
  import { seasonStats } from '@/lib/seasonStats'
  import { stickyHeight } from '@/lib/stickyBars'
  import { fileSlug } from '@/lib/csv'
  import { formatNumber, parseNumber, units as unitsFor, type Units } from '@/lib/units'
  import {
    exportPlanting,
    fieldDays,
    fields,
    pivots,
    planting as plantingRoute,
    plantings as plantingRoutes,
    plantingCutting,
    plantingCuttings,
    setup,
    weatherPivot,
  } from '@/routes'
  import type { Field, FieldDay, Planting, PlantingSummary, WeatherPanelDay } from '@/types/serializers'

  let {
    field,
    pivot,
    farm,
    weather_updating,
    as_of,
    travel_dates,
    planting,
    summary,
    days,
    forecast_days,
    weather,
  }: {
    field: Field
    pivot: { id: number; name: string; pump_capacity_gpm: number | null }
    farm: { id: number; name: string }
    weather_updating: boolean
    /** Time travel (PLAN.md Phase 8 F): the earlier day the page shows, read-only; null for today */
    as_of: string | null
    /** The season's days before today, which time travel can pick; null if none */
    travel_dates: { from: string; to: string } | null
    planting: Planting
    summary: PlantingSummary
    days: FieldDay[]
    forecast_days: FieldDay[]
    weather: WeatherPanelDay[]
  } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  // Time travelling, nothing on the page edits, and the projection is the weather that followed
  const readOnly = $derived(as_of !== null)
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
  const lai = $derived(planting?.et_method === 'lai')
  const rows = $derived([...days].reverse())
  const outlook = $derived(summary && outlookFor(summary, units))
  const projectionByDate = $derived(new Map(summary?.projection.map((day) => [day.date, day]) ?? []))
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
      planting.season_days !== null &&
      summary.date > addDays(planting.emergence_date, planting.season_days),
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
      ),
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
  const thresholdName = $derived(summary?.target_in === null ? 'of reaching 0 AD' : 'of falling below target')
  const depthUnitName = $derived(units.label('depth') === 'mm' ? 'millimeters' : 'inches')
  let chartMode = $state<FieldChartMode>('ad')
  // The season's sections, closed until opened; links in the summary open them
  let summaryOpen = $state(false)

  // Crop ET and rain by date, through the projection, as a string so the weather charts rebuild only
  // when they change (an edit to irrigation or a reading reloads the days, but leaves both alone)
  const balanceJson = $derived(
    JSON.stringify(
      [...days, ...forecast_days].map(({ date, adj_et, rain, rain_source, rain_model }) => ({
        date,
        adj_et,
        rain,
        rain_source,
        rain_model,
      })),
    ),
  )
  // In some units: the user's for the charts, imperial (as stored) for their CSVs (WeatherSection)
  const panels = $derived.by(() => {
    const balance: Pick<FieldDay, 'date' | 'adj_et' | 'rain' | 'rain_source' | 'rain_model'>[] = JSON.parse(balanceJson)
    return (u: Units) =>
      weatherPanels(u, {
        field: { fieldCapacity: field.effective_field_capacity, wiltingPoint: field.effective_perm_wilting_pt },
        cropEt: Object.fromEntries(balance.map((day) => [day.date, day.adj_et])),
        fieldRain: Object.fromEntries(
          balance.map(({ date, rain, rain_source, rain_model }) => [date, { rain, rain_source, rain_model }]),
        ),
      })
  })

  // What it takes to refill the root zone to field capacity today
  const refill = $derived(
    summary?.ad !== null && summary?.ad !== undefined ? Math.max(0, summary.ad_max - summary.ad) : null,
  )

  type Column = 'rain_in' | 'irrigation_in' | 'soil_moisture_pct' | 'canopy' | 'notes'

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
  const when = (date: string) =>
    summary?.phase === 'active' && summary.date ? relativeDay(date, summary.date) : formatDate(date)
</script>

<svelte:head
  ><title>{as_of ? `As of ${formatDate(as_of)} · ` : ''}{planting.plant_name} · {field.name} · WISP</title></svelte:head
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
        href={setup.show({ query: { year: planting.year } })}
        title="Change this field, its pivot or its plantings on the setup page"
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

{#if as_of}
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
        Weather for this pivot is on its way, usually within a few minutes of adding it. Until it arrives, WISP can't
        estimate crop water use, so the numbers below won't change.{#if weatherState === 'updating'}{' This page updates when it arrives.'}{/if}
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
          Past a typical {planting.plant_name.toLowerCase()} season ({planting.season_days} days from emergence). Harvested?
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
      {#if planting.exceeds_field_area}
        <p role="status" class="rounded-md border border-status-caution/60 bg-status-caution/10 px-3 py-2 text-sm">
          The plantings on this field in season together cover more than its {units.format('area', field.area_acres)}.
          Check their sizes, or the field's area in setup.
        </p>
      {/if}
    {/if}
    {#if summary.phase === 'upcoming'}
      <p class="text-sm">The season starts {formatDate(summary.season_start, { year: true })}.</p>
    {:else}
      <p class="text-sm">
        {#if summary.phase === 'ended'}At the end of the season{:else if as_of}On {formatDate(as_of)}{:else}Today{/if}:
        <strong class="tabular-nums">{units.format('depth', summary.ad)}</strong>
        <Term id="ad">allowable depletion</Term> of
        {units.format('depth', summary.ad_max)}, <strong>{formatNumber(summary.pct_moisture, 1)}%</strong> soil moisture.
      </p>
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
    {/if}
  </div>

  <dl class="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
    <div>
      <dt class="text-ink-muted">At <Term id="field_capacity">field capacity</Term></dt>
      <dd class="tabular-nums">{units.format('depth', summary.ad_max)} AD</dd>
    </div>
    <div>
      <dt class="text-ink-muted">Target</dt>
      <dd class="tabular-nums">
        {summary.target_in === null ? 'Not set' : `${units.format('depth', summary.target_in)} AD`}
      </dd>
    </div>
    <div>
      <dt class="text-ink-muted">Irrigate at</dt>
      <dd class="tabular-nums">0 AD ({formatNumber(summary.pct_at_ad_zero, 1)}% moisture)</dd>
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
    <h3 class="font-medium">Totals so far</h3>
    <dl class="mt-1 grid grid-cols-2 gap-x-4 gap-y-1 tabular-nums">
      <dt class="text-ink-muted">Rain</dt>
      <dd>{units.format('depth', summary.totals.rain)}</dd>
      <dt class="text-ink-muted">Irrigation</dt>
      <dd>{units.format('depth', summary.totals.irrigation)}</dd>
      <dt class="text-ink-muted"><Term id="crop_et">Crop ET</Term></dt>
      <dd>{units.format('depth', summary.totals.adj_et)}</dd>
      <dt class="text-ink-muted"><Term id="deep_drainage">Deep drainage</Term></dt>
      <dd>{units.format('depth', summary.totals.deep_drainage)}</dd>
    </dl>
    {#if !summary.use_model_precip}
      <p class="mt-2 text-xs">
        Rain: <Term id="entered_rain_only">only what you enter</Term>, plus the forecast for the days ahead.
        {#if !readOnly}
          <Link href="{fields.show(field.id).url}#rainfall" class="text-brand-600 underline underline-offset-2"
            >Change this</Link
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

  {#if guidance?.warning}
    <p
      role="status"
      class="rounded-md border border-status-caution/60 bg-status-caution/10 px-3 py-2 text-sm lg:col-span-3"
    >
      {guidance.warning}
    </p>
  {/if}
  {#if guidance}
    <!-- The readings stay in view when the explanation is collapsed -->
    <div class="border-t border-line pt-3 text-sm lg:col-span-3">
      <details open={guidanceOpen} ontoggle={(event) => toggleGuidance(event.currentTarget.open)}>
        <summary class="cursor-pointer font-medium">{guidance.title}</summary>
        <div class="mt-2 max-w-3xl space-y-2 text-ink-muted">
          <GlossaryText paragraphs={guidance.paragraphs} />
        </div>
      </details>
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
    </div>
  {/if}
</section>

{#if planting.takes_cuttings}
  <!-- A perennial's cuttings: each restarts its canopy (PLAN.md Phase 8 G.3) -->
  <section class="space-y-3 rounded-lg border border-line bg-surface-raised p-4" aria-labelledby="cuttings-heading">
    <div>
      <h2 id="cuttings-heading" class="font-medium">Cuttings</h2>
      <p class="text-sm text-ink-muted">
        Each cutting drops the canopy to stubble that day, and it regrows from there on the perennial curve, corrected
        by the readings you enter after it.
      </p>
    </div>
    {#if planting.cuttings.length}
      <ul class="flex flex-wrap gap-2 text-sm" aria-label="Cuttings">
        {#each planting.cuttings as cutting (cutting.id)}
          <li class="flex items-center gap-2 rounded-md border border-line px-2.5 py-1">
            Cut {formatDate(cutting.date, { weekday: true })}
            {#if !readOnly}
              <button
                type="button"
                class="text-xs text-status-irrigate-ink hover:underline"
                aria-label="Remove the {formatDate(cutting.date)} cutting"
                onclick={() => {
                  if (confirm(`Remove the ${formatDate(cutting.date)} cutting?`))
                    router.delete(plantingCutting({ plantingId: planting.id, id: cutting.id }).url, {
                      preserveScroll: true,
                    })
                }}>Remove</button
              >
            {/if}
          </li>
        {/each}
      </ul>
    {:else}
      <p class="text-sm text-ink-muted">No cuttings yet this season.</p>
    {/if}
    {#if !readOnly}
      <Form
        action={plantingCuttings(planting.id)}
        class="flex flex-wrap items-end gap-2"
        options={{ preserveScroll: true }}
        resetOnSuccess
      >
        {#snippet children({ errors, processing })}
          <div class="space-y-1">
            <label for="cutting-date" class="block text-sm font-medium">Cut on</label>
            <input
              id="cutting-date"
              type="date"
              name="cutting[date]"
              required
              min={addDays(planting.emergence_date, 1)}
              max={planting.end_date}
              class="block rounded-md text-sm"
            />
          </div>
          <Button type="submit" variant="secondary" disabled={processing}>Add cutting</Button>
          {#if errors.date || errors.base}<p class="w-full text-sm text-status-irrigate-ink">
              {errors.date ?? errors.base}
            </p>{/if}
        {/snippet}
      </Form>
    {/if}
  </section>
{/if}

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
        height="40rem"
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
    <!-- The projection, and planned irrigation -->
    <CollapsibleSection
      title={replay ? `The ${forecast_days.length} days that followed` : `Next ${forecast_days.length} days`}
      storageKey="forecast"
    >
      <div class="space-y-2">
        {#if replay}
          <p class="text-xs text-ink-muted">
            This is what happened after {formatDate(as_of)}: the weather that came for this pivot and what was entered
            for those days, run through the water balance where the forecast would have been. Depths are in
            {depthUnitName}.
          </p>
        {:else}
          <p class="text-xs text-ink-muted">
            This is the forecast for this pivot, run through the water balance. To plan irrigation, enter an amount on a
            future day. WISP counts it as applied when that day arrives, so change or clear it if your plans change.
            Depths are in {depthUnitName}. From the keyboard, use the arrow keys to move between cells, and press Enter
            or start typing to edit one.
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
              {#each forecast_days as day, row (day.date)}
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
                        {#if day.irrigation_source !== 'entered'}<span class="ml-1 text-xs text-brand-600"
                            >{day.irrigation_source}</span
                          >{/if}
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
                    <td class="px-2 py-1 tabular-nums"
                      >{band?.chance != null ? `${Math.round(band.chance * 100)}%` : ''}</td
                    >
                  {/if}
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </div>
    </CollapsibleSection>
  {/if}

  <!-- Daily grid -->
  <CollapsibleSection title="Daily values" storageKey="daily">
    <div class="space-y-2">
      <p class="text-xs text-ink-muted">
        {#if readOnly}
          The season up to {formatDate(as_of)}. Depths are in {depthUnitName}.
        {:else}
          Click a rain, irrigation, soil moisture, {lai ? 'LAI' : 'cover'} or notes cell to enter a value, and press Enter
          to save and move down. Clear a cell to go back to the modeled or pivot value. Depths are in {depthUnitName}.
          From the keyboard, use the arrow keys to move between cells, and press Enter or start typing to edit one.
          {#if plot}
            Rain is the whole field's, so it's the same for every planting on it; irrigation, soil moisture readings and
            notes entered here are this planting's own. Irrigation entered for the whole field (on the
            <Link href={fields.show(field.id)} class="text-brand-600 underline underline-offset-2">Field</Link> tab) applies
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
                      {#if day.irrigation_source === 'pivot'}<span class="ml-1 text-xs text-brand-600">from pivot</span
                        >{/if}
                      {#if day.irrigation_source === 'field'}<span class="ml-1 text-xs text-brand-600">from field</span
                        >{/if}
                      {#if day.irrigation_source === 'entered' && day.field_inches !== null}
                        <span class="block text-xs text-ink-muted">field {depth(day.field_inches)}</span>
                      {:else if day.irrigation_source === 'entered' && day.pivot_inches !== null}
                        <span class="block text-xs text-ink-muted">pivot {depth(day.pivot_inches)}</span>
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
        Rain in gray is modeled for the pivot's location; bold values are ones you entered.{#if plot}{' '}Irrigation
          marked “from field” was entered for the whole field.{/if} Irrigation marked “from pivot” was entered on the
        <Link href={pivots.show(pivot.id)} class="text-brand-600 underline underline-offset-2"
          >pivot's irrigation page</Link
        > or on the Daily entry page. * Crop ET is estimated from the past week because that day's weather is missing.
        {lai ? 'LAI' : 'Cover'} in gray is estimated: {planting?.effective_canopy_interpolation === 'curve'
          ? "the crop's typical curve, adjusted to your readings"
          : 'straight lines between your readings'}.
      </p>
    </div>
  </CollapsibleSection>
{/if}

<WeatherSection
  {panels}
  days={weather}
  {units}
  exports={{
    place: `${farm.name} / ${pivot.name} / ${field.name}`,
    file: `wisp-${fileSlug(field.name)}-${planting?.year}`,
    href: weatherPivot(pivot.id, { query: { year: planting?.year } }).url,
  }}
>
  Precipitation also shows the rain you entered for this field, with the modeled rain its balance doesn't use outlined.
  Soil moisture is the model's own estimate, not this field's balance; it's shown against the field's capacity and
  wilting point for comparison.
</WeatherSection>

<!-- The season in numbers, and settings for this field's balance (its setup is on the setup page) -->
{#if stats}
  <CollapsibleSection title="Season summary" id="season-summary" storageKey="season-summary" bind:open={summaryOpen}>
    <SeasonDetails {stats} {units} useModelPrecip={summary.use_model_precip} />
  </CollapsibleSection>
{/if}
