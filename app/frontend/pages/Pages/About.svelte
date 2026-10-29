<script lang="ts">
  import { page } from '@inertiajs/svelte'

  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import Term from '@/lib/components/Term.svelte'
  import CanopyCurvePlot from '@/lib/docs/CanopyCurvePlot.svelte'
  import Introduction from '@/lib/docs/Introduction.svelte'
  import { GLOSSARY } from '@/lib/glossary'
  import { FULL_COVER_PCT, READING_EVERY } from '@/lib/guidance'
  import { units as unitsFor } from '@/lib/units'

  // The About page (PLAN.md Phase 6.5): WISP's documentation, replacing the legacy PDF user guide.
  // Public; the crop table comes from the plants table, the soil table from soil_types (with each
  // value's basis from db/reference/soil_types.yml), the glossary from lib/glossary.ts and the
  // reading advice from lib/guidance.ts, so they stay in step with the app.

  type Plant = { key: string; name: string; root_zone_in: number; lai_curve: boolean; cover_curve: boolean }
  // A crop's percent cover curve, from db/reference/canopy_curves.yml (PagesController#canopy_curves)
  type CanopyCurve = {
    key: string
    name: string
    basis: string
    confidence: string
    confidence_label: string
    notes: string | null
    growth: { cc0: number; ccx: number; cgc: number }
    decline:
      | { type: 'aquacrop'; start_day: number; cdc: number }
      | { type: 'rule'; date: string; days: number; floor: number }
      | null
    days_to: { 50: number | null; 80: number | null }
    covers: number[]
    sources: { citation: string; url: string }[]
  }
  type Soil = {
    key: string
    name: string
    field_capacity: number
    perm_wilting_pt: number
    basis: 'wi_survey' | 'saxton_rawls' | 'legacy' | 'legacy_confirmed'
  }
  let {
    plants,
    canopy_curves: curves,
    soil_types: soils,
    defaults,
  }: {
    plants: Plant[]
    canopy_curves: CanopyCurve[]
    soil_types: Soil[]
    defaults: {
      mad_pct: number
      lead_days: number
      forecast_days: number
      shift_warning_days: number
      drop_warning: number
      fade_days: number
      fit_shift_days: number
      fit_noise_pct: number
    }
  } = $props()
  const withoutCurve = $derived(plants.filter((plant) => !plant.cover_curve).map((plant) => plant.name))

  const pct = (fraction: number) => `${+(fraction * 100).toFixed(2)}%`
  function declineText(decline: CanopyCurve['decline']): string {
    if (!decline) return "Holds its maximum cover until the planting's end date."
    if (decline.type === 'aquacrop') {
      return `Declines from day ${decline.start_day} after emergence, following AquaCrop's equation (CDC ${decline.cdc} a day).`
    }
    const [month, day] = decline.date.split('-').map(Number)
    const date = new Date(2000, month - 1, day).toLocaleDateString('en-US', { month: 'long', day: 'numeric' })
    return (
      `Starting ${date} (or once the canopy is full, if that comes later), cover eases down to ${decline.floor}% ` +
      `over ${decline.days} days, fastest at the halfway point, then holds until the end date.`
    )
  }

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const depth = (inches: number) => units.format('rootDepth', inches)

  const BASES: Record<Soil['basis'], string> = {
    wi_survey: 'Wisconsin soil survey',
    saxton_rawls: 'Saxton and Rawls (2006)',
    legacy: 'Original WISP',
    legacy_confirmed: 'Original WISP; the Wisconsin survey agrees',
  }
  // Water the soil holds for the crop between field capacity and the wilting point, per foot (or meter) of root zone
  const availableWater = (soil: Soil) => units.format('availableWater', soil.field_capacity - soil.perm_wilting_pt)

  const sections = [
    { id: 'introduction', title: 'What WISP is' },
    { id: 'how-it-works', title: 'How it works' },
    { id: 'getting-started', title: 'Getting started' },
    { id: 'day-to-day', title: 'Day to day' },
    { id: 'ground-truthing', title: 'Keeping the model on track' },
    { id: 'soils', title: 'Soils' },
    { id: 'crops', title: 'Crops' },
    { id: 'canopy', title: 'Canopy curves' },
    { id: 'glossary', title: 'Glossary' },
    { id: 'accessibility', title: 'Accessibility' },
    { id: 'contact', title: 'Credits and contact' },
  ]
</script>

<svelte:head><title>About WISP</title></svelte:head>

<div class="grid gap-8 lg:grid-cols-[12rem_1fr]">
  <nav aria-label="On this page" class="hidden lg:block">
    <ul class="sticky top-6 space-y-1 text-sm">
      {#each sections as section (section.id)}
        <li>
          <a href="#{section.id}" class="block rounded px-2 py-1 text-ink-muted hover:bg-surface-raised hover:text-ink"
            >{section.title}</a
          >
        </li>
      {/each}
    </ul>
  </nav>

  <article class="prose max-w-3xl min-w-0 prose-headings:scroll-mt-6 prose-headings:font-display">
    <h1>About WISP</h1>

    <h2 id="introduction">What WISP is</h2>
    <Introduction />

    <h2 id="how-it-works">How it works</h2>
    <h3>The water balance</h3>
    <p>
      WISP treats each field's root zone as a single bucket. How big the bucket is depends on the soil and the crop: it
      is the water held between <Term id="field_capacity">field capacity</Term> and the <Term id="wilting_point"
        >wilting point</Term
      >, over the depth of the root zone. The crop can use a share of that water without stress, set by its
      <Term id="mad">MAD</Term> ({defaults.mad_pct}% unless you change it). WISP tracks how much of that share is left,
      the <Term id="ad">allowable depletion (AD)</Term>, from day to day:
    </p>
    <ul>
      <li><strong>Rain and irrigation</strong> add to it.</li>
      <li>
        <strong>The crop's water use</strong> (<Term id="crop_et">crop ET</Term>) takes from it. It is the day's
        <Term id="reference_et">reference ET</Term>, worked out from the weather, adjusted for how much of the ground
        the crop covers (<Term id="percent_cover">percent cover</Term> or <Term id="lai">LAI</Term>).
      </li>
      <li>
        Water beyond field capacity drains below the roots and is counted as <Term id="deep_drainage"
          >deep drainage</Term
        >.
      </li>
      <li>A soil moisture reading you enter resets the balance to what you measured.</li>
    </ul>
    <p>
      A full root zone has AD at its maximum. At 0 AD the crop has used its allowance and it's time to irrigate; below 0
      it is increasingly stressed. The balance is recalculated from the start of the season every time you open a page,
      so a value you correct from last week is reflected in today's numbers right away.
    </p>

    <h3>Weather</h3>
    <p>
      Each pivot's weather comes from <a href="https://open-meteo.com/" target="_blank" rel="noopener">Open-Meteo</a>,
      for an area about 9 km across around its location. It's updated at 5 am, 11 am and 5 pm Central and includes rain,
      reference ET (FAO-56 Penman-Monteith), temperature, humidity, wind, and modeled soil moisture and soil
      temperature. Recent days are revised as better data arrives, then settled. Modeled rain can miss a local storm, so
      you can enter your own rain gauge readings in its place on any day. For a whole operation or a single field, you
      can also choose to count only the rain you enter. The days ahead still use the forecast rain, and the outlook for
      such a field also says when it would need water if no rain fell.
    </p>

    <h3>The outlook</h3>
    <p>
      WISP runs each field's balance forward through the next {defaults.forecast_days} days of forecast, counting any irrigation
      you've planned, to find the day it would reach 0 AD, or the target you've set for the field. That day is its
      <strong>Irrigate by</strong> date, along with how much water would refill the root zone then. It also runs the balance
      through 31 forecast scenarios, slightly different versions of the forecast, so you can see how sure that date is. If
      "24 of 31 forecast scenarios reach it by then," the other seven don't, so rain could well push the date back.
    </p>
    <p>Each field gets a status for today:</p>
    <table>
      <tbody>
        <tr><td><StatusBadge status="full" /></td><td>Near field capacity: AD at 90% of its maximum or more.</td></tr>
        <tr><td><StatusBadge status="ok" /></td><td>Above its target, or above half its maximum AD without one.</td></tr
        >
        <tr>
          <td><StatusBadge status="caution" /></td>
          <td>
            Below its target (or half its maximum AD) but still above 0, or expected to reach the irrigation point
            within
            {defaults.lead_days} days.
          </td>
        </tr>
        <tr><td><StatusBadge status="irrigate" /></td><td>At or below the irrigation point (0 AD) today.</td></tr>
      </tbody>
    </table>

    <h2 id="getting-started">Getting started</h2>
    <h3>Your account and operation</h3>
    <p>
      Create an account with your email address. You can sign in with a password, or have WISP email you a sign-in link
      and code. Your account comes with an operation of your own. To work on the same farms as other people, add them to
      the operation by their email address (Operation and members, in the account menu). Every member can set up fields
      and enter data. Owners can also change the operation's settings and members, and delete farms, pivots and fields.
    </p>
    <h3>Farms, pivots, fields and crops</h3>
    <p>WISP organizes everything the way irrigation is managed:</p>
    <ul>
      <li><strong>Farm:</strong> any set of pivots you want to see together, such as one location.</li>
      <li>
        <strong>Pivot:</strong> one irrigation system, placed on the map. Its location sets its weather, so put it where it
        really is.
      </li>
      <li>
        <strong>Field:</strong> the land under a pivot that's managed alike, with one crop and one soil. A pivot split
        between two crops is two fields. The soil type sets field capacity and wilting point (see
        <a href="#soils">Soils</a>); when you place the pivot, WISP suggests one from the USDA soil survey. If you know
        better values for your field, from the
        <a href="https://websoilsurvey.nrcs.usda.gov/" target="_blank" rel="noopener">Web Soil Survey</a> or your own measurements,
        enter them instead.
      </li>
      <li>
        <strong>Crop (planting):</strong> a crop on a field for one season, with its emergence date, root zone depth,
        MAD and the way its canopy is tracked. Typical values for each crop are in the <a href="#crops">table below</a>.
        A field can have more than one planting a year, for double cropping.
      </li>
    </ul>
    <p>
      The quickest start is <strong>Set up a pivot</strong> on the Setup page: place the pivot, then add its fields and
      crops in one form. Everything can be changed later in Setup. Each spring,
      <strong>Copy last season's crops</strong>
      brings your crops forward a year with the same settings.
    </p>

    <h2 id="day-to-day">Day to day</h2>
    <ul>
      <li>
        <strong>Dashboard:</strong> every field by farm and pivot, with its status, AD and outlook, and the last rain and
        irrigation.
      </li>
      <li>
        <strong>Map:</strong> shows each pivot where it is, colored by its most urgent field, with each field's status at
        its center. The fields are listed beside the map, most urgent first or north to south. Choose "Needs water within
        3 days" (or 7) to see which pivots to irrigate this week. Click a pivot, or a field in the list, to see its fields
        and weather. Layers add radar, rain over the last 24 or 72 hours, the National Weather Service's forecast rain, and
        the U.S. Drought Monitor; point at the map, or tap it, to see their values at that spot.
      </li>
      <li>
        <strong>Daily entry:</strong> rain, irrigation and soil moisture for every field on one day. Irrigation can be entered
        once for a pivot and its fields. Leave rain blank to use the modeled rain. Enter 0 if your gauge showed no rain.
      </li>
      <li>
        <strong>Field groups</strong> (in Setup): fields that share readings, such as the same rain gauge. A value you enter
        for a group applies to every field in it.
      </li>
      <li>
        <strong>A field's page:</strong> its status and outlook, a chart of the season, the next
        {defaults.forecast_days} days, every day's values, and the weather. Click a cell to enter or correct a value. Plan
        irrigation by entering it on a future day: it counts as applied when the day comes, so change it if plans change.
        Export the season as a CSV file.
      </li>
      <li>
        <strong>Alerts:</strong> a morning email at about 6 am. It groups your fields by operation, farm, weather zone (pivots
        that share the same weather) and pivot, and gives each zone's weather, which fields to irrigate or watch, and which
        readings are due. You choose which fields it covers, which of those it lists (all, only those in season, only those
        needing irrigation or readings, or only those needing irrigation), and how often it comes: daily during the season,
        daily all year (with weather out of season too), only when a field needs irrigation, or never.
      </li>
    </ul>

    <h2 id="ground-truthing">Keeping the model on track</h2>
    <p>
      The balance is only as good as what goes into it, and small errors add up over a season. These readings matter
      most:
    </p>
    <ul>
      <li>
        <strong>Irrigation:</strong> enter every application, by pivot or by field. WISP can't know about water it isn't told
        about.
      </li>
      <li>
        <strong>Rain:</strong> rain is patchy, and the weather model's estimate for your pivot can miss a storm or catch one
        that missed you. A rain gauge at or near the field, read daily, is the best way to correct it. If you read it every
        day it rains, set the field to use only the rain you enter; the season details on its page compare your gauge with
        the model.
      </li>
      <li>
        <strong>Soil moisture:</strong> a measured root zone moisture resets the balance, correcting any drift. Enter
        one about every {READING_EVERY} days, from sensors at about 25% and 75% of the root zone depth (see the
        <a href="#crops">crop table</a>).
      </li>
      <li>
        <strong>Canopy:</strong> with percent cover, enter it about weekly from emergence until the canopy covers about
        {FULL_COVER_PCT}% of the ground; between and after readings WISP follows the crop's
        <a href="#canopy">canopy curve</a>, adjusted to them. For row crops, divide the average canopy width by the row
        spacing. LAI is available for field corn, which follows a growth curve unless you enter readings.
      </li>
      <li>
        <strong>Root zone depth:</strong> the defaults are typical; the depth your crop actually roots to is best measured
        in the field at full canopy. For potatoes, measure from the top of the hill.
      </li>
    </ul>
    <p>Each field's page shows when soil moisture and canopy were last entered, and flags them when one is due.</p>

    <h2 id="soils">Soils</h2>
    <p>
      A field's soil type sets how much water its root zone can hold: from <Term id="field_capacity"
        >field capacity</Term
      >, as wet as it stays once it has drained, down to the <Term id="wilting_point">wilting point</Term>, where the
      crop can take no more. Both are shares of the soil's volume, and the difference between them, over the root zone
      depth, is the water available to the crop. If you know better values for a field, from the
      <a href="https://websoilsurvey.nrcs.usda.gov/" target="_blank" rel="noopener">Web Soil Survey</a> or your own measurements,
      enter them for the field and they replace its soil type's.
    </p>
    <p>
      When you place a pivot, WISP looks up the USDA soil survey under it and suggests the soil type that covers most of
      it, from the surface layer of each map unit's main soil; the pivot map's <strong>Soil types</strong> button shows them
      around the pivot. It's a suggestion: check it against what you know of the field.
    </p>
    <div class="not-prose overflow-x-auto rounded-lg border border-line bg-surface-raised">
      <table class="w-full text-sm">
        <thead class="border-b border-line text-left text-xs text-ink-muted">
          <tr>
            <th class="px-3 py-2 font-medium">Soil</th>
            <th class="px-3 py-2 text-right font-medium">Field capacity</th>
            <th class="px-3 py-2 text-right font-medium">Wilting point</th>
            <th class="px-3 py-2 text-right font-medium">Available water</th>
            <th class="px-3 py-2 font-medium">Source of values</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-line">
          {#each soils as soil (soil.key)}
            <tr>
              <th scope="row" class="px-3 py-1.5 text-left font-normal">{soil.name}</th>
              <td class="px-3 py-1.5 text-right tabular-nums">{pct(soil.field_capacity)}</td>
              <td class="px-3 py-1.5 text-right tabular-nums">{pct(soil.perm_wilting_pt)}</td>
              <td class="px-3 py-1.5 text-right whitespace-nowrap tabular-nums">{availableWater(soil)}</td>
              <td class="px-3 py-1.5">{BASES[soil.basis]}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
    <p>
      The values were reviewed in 2026. Most are medians of the surface layers in Wisconsin's soil survey (USDA NRCS
      SSURGO, every county), from dozens to thousands of soils for each texture. Sandy clay loam, which Wisconsin's
      survey has only below the surface, takes the texture averages of
      <a href="https://doi.org/10.2136/sssaj2005.0117" target="_blank" rel="noopener">Saxton and Rawls (2006)</a>. Silt
      and clay keep WISP's original values, as Wisconsin has too few of them to set new ones; sand's original values
      match the survey. Muck holds far more water than any mineral soil, but drained, farmed muck changes over the
      years, so a soil moisture reading is worth more there.
    </p>

    <h2 id="crops">Crops</h2>
    <p>
      Every crop can use percent cover. LAI is available only for crops that have an LAI growth curve, so far just field
      corn; more will be added as validated curves become available. Typical root zone depths are from Table 3.4 of the
      NRCS National Engineering Handbook, part 652 (mint from FAO-56), and suggested sensor depths are 25% and 75% of
      the root zone depth. Every crop starts with a MAD of
      {defaults.mad_pct}% and a season from April 1 to November 30; you can change any of these for your planting.
    </p>
    <div class="not-prose overflow-x-auto rounded-lg border border-line bg-surface-raised">
      <table class="w-full text-sm">
        <thead class="border-b border-line text-left text-xs text-ink-muted">
          <tr>
            <th class="px-3 py-2 font-medium">Crop</th>
            <th class="px-3 py-2 text-right font-medium">Root zone</th>
            <th class="px-3 py-2 text-right font-medium">Sensor depths</th>
            <th class="px-3 py-2 font-medium">Canopy methods</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-line">
          {#each plants as plant (plant.key)}
            <tr>
              <th scope="row" class="px-3 py-1.5 text-left font-normal">{plant.name}</th>
              <td class="px-3 py-1.5 text-right tabular-nums">{depth(plant.root_zone_in)}</td>
              <td class="px-3 py-1.5 text-right whitespace-nowrap tabular-nums">
                {depth(plant.root_zone_in * 0.25)} and {depth(plant.root_zone_in * 0.75)}
              </td>
              <td class="px-3 py-1.5"
                >{plant.cover_curve ? 'Percent cover, with a curve' : 'Percent cover, readings only'}{plant.lai_curve
                  ? '; LAI with a curve'
                  : ''}</td
              >
            </tr>
          {/each}
        </tbody>
      </table>
    </div>

    <h2 id="canopy">Canopy curves</h2>
    <p>
      A crop's water use follows its canopy, so WISP needs the canopy every day of the season. Every crop with a card
      below has a typical <Term id="canopy_curve">canopy curve</Term>: its percent cover by day since emergence. With no
      readings WISP follows it from the emergence date.
    </p>
    <p>
      <strong>Your readings adjust the curve, in two steps.</strong> First WISP fits the curve to them: it can run
      earlier or later, grow faster or slower, and be fuller or thinner. Each change is held back by how much crops
      typically vary from field to field (about {defaults.fit_shift_days} days in timing), and each reading pulls by how far
      it is from the curve, allowing about {defaults.fit_noise_pct} points for how precise a reading by eye is. So one or
      two readings barely move the curve, and as readings add up it fits them more closely. Readings of 80% or more count
      as "at least 80%", since many growers stop there.
    </p>
    <p>
      Then the canopy passes through every reading. At each one WISP takes the ratio of your reading to the fitted
      curve, draws straight lines between those ratios (from 1 at emergence), and over the {defaults.fade_days} days after
      your latest reading eases the ratio back to 1, so the canopy returns to the fitted curve, including its late-season
      decline. It never goes above the larger of the fitted curve's maximum and your highest reading. In Setup, a planting
      can use straight lines between readings instead, as earlier versions of WISP did.
    </p>
    <p>
      Tested against Wisconsin growers' 2026 readings, following the curve cut the error in the next week's canopy cover
      in half compared with straight lines. Fitting the curve and letting each reading's effect fade cut the error over
      the rest of the season by about 40% compared with holding the last reading's ratio all season.
    </p>
    <p>
      <strong>When your readings and the curve disagree,</strong> the field page says so. That happens if readings
      between 10% and 80% run more than {defaults.shift_warning_days} days ahead of or behind the curve (often a sign that
      the emergence date is off), or if a reading drops by more than {defaults.drop_warning} points while the curve is still
      growing or holding steady. Either way, WISP keeps following the curve through your readings.
    </p>
    <p>
      <strong>How the curves were made.</strong> Growth follows the canopy cover equations of FAO's AquaCrop model, with
      three numbers per crop: the cover just after emergence (CC₀), the maximum cover (CCx), and a growth rate (CGC).
      Some crops also decline late in the season. Where FAO's AquaCrop has a crop file, WISP uses its values by calendar
      day. They matched Wisconsin 2026 readings within a few days for potato, field corn and snap bean, and were
      adjusted to match for soybean and sweet corn. For other crops the timing comes from the stage lengths in FAO-56.
      Each card says which source was used and how well it has been checked. The research notes, data screening and
      scripts are in
      <a href="https://github.com/uwent/wisp3/tree/main/docs/canopy" target="_blank" rel="noopener"
        >the WISP source code</a
      >.
    </p>
    <!-- Focusable so keyboard users can scroll it (WCAG 2.1.1) -->
    <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
    <pre class="text-xs" tabindex="0" aria-label="Canopy curve equations"><code
        >growth:  CC = CC₀ · e^(CGC·t)                   while CC ≤ CCx/2
         CC = CCx − ¼ · CCx² / CC₀ · e^(−CGC·t)  after, up to CCx
decline: CC = CCx · [1 − 0.05 · (e^(3.33·CDC·t′ / (CCx + 2.29)) − 1)]
t: days since emergence; t′: days since the decline starts</code
      ></pre>
    <p>
      <strong>Crops without a curve</strong> ({withoutCurve.join(', ')}) use only the cover you enter: WISP draws
      straight lines between your readings and assumes no cover until the first one. We found no published canopy values
      for onion to check against; alfalfa and mint are cut and regrow during the season; and we found no source for
      asparagus fern growth after harvest.
    </p>
    <p>
      <strong>LAI</strong> is offered only for crops with an LAI curve, so far field corn, whose curve comes from the Wisconsin
      Irrigation Scheduler (WIS v6.3.11) spreadsheet and peaks at about 4 around 80 days after emergence. Estimating LAI from
      percent cover would put crop water use 20 to 40% below the percent cover method while the canopy develops, so WISP doesn't
      offer it.
    </p>
    <p class="text-sm text-ink-muted">
      Each curve is drawn for a crop that emerges on May 15, over {curves[0]?.covers.length - 1} days.
    </p>
    <div class="not-prose grid gap-4 sm:grid-cols-2">
      {#each curves as curve (curve.key)}
        <section
          id="canopy-{curve.key}"
          aria-labelledby="canopy-{curve.key}-name"
          class="scroll-mt-6 space-y-2 rounded-lg border border-line bg-surface-raised p-3 text-sm"
        >
          <div class="flex flex-wrap items-baseline justify-between gap-x-2">
            <h3 id="canopy-{curve.key}-name" class="font-display font-semibold">{curve.name}</h3>
            <span class="text-xs text-ink-muted">{curve.confidence_label}</span>
          </div>
          <CanopyCurvePlot
            covers={curve.covers}
            label="{curve.name} canopy cover by day since emergence{curve.days_to[50] !== null
              ? `: 50% on day ${curve.days_to[50]}`
              : ''}{curve.days_to[80] !== null ? `, 80% on day ${curve.days_to[80]}` : ''}"
          />
          <p>
            {#if curve.days_to[50] !== null}50% cover on day {curve.days_to[50]}{/if}{#if curve.days_to[80] !== null},
              80% on day {curve.days_to[80]}{/if}. {declineText(curve.decline)}
          </p>
          <p class="text-ink-muted">
            {curve.basis}. Starting cover (CC₀) {pct(curve.growth.cc0)}, maximum cover (CCx) {pct(curve.growth.ccx)},
            growth rate (CGC) {curve.growth.cgc} a day.
          </p>
          {#if curve.notes}<p class="text-ink-muted">{curve.notes}</p>{/if}
          <details class="text-xs text-ink-muted">
            <summary class="cursor-pointer">Sources</summary>
            <ul class="mt-1 list-disc space-y-1 pl-4">
              {#each curve.sources as source (source.url)}
                <li>
                  {source.citation}
                  <a href={source.url} target="_blank" rel="noopener" class="break-all text-brand-600 hover:underline"
                    >{source.url}</a
                  >
                </li>
              {/each}
            </ul>
          </details>
        </section>
      {/each}
    </div>

    <h2 id="glossary">Glossary</h2>
    <dl>
      {#each GLOSSARY as entry (entry.id)}
        <dt id="glossary-{entry.id}" class="scroll-mt-6">{entry.term}</dt>
        <dd>{entry.definition}</dd>
      {/each}
    </dl>

    <h2 id="accessibility">Accessibility</h2>
    <p>
      WISP aims to meet the Web Content Accessibility Guidelines (WCAG) 2.1 at level AA, and is checked against them
      with automated tests on every page, in light and dark mode, and by hand.
    </p>
    <ul>
      <li>
        Everything works from the keyboard. "Skip to main content" is the first stop on each page, and in the daily
        grids the arrow keys move between cells, Enter or typing edits one, and Escape cancels.
      </li>
      <li>
        Each weather chart has a "Summary and data" link with the chart in words and its daily values as a table. The
        field chart's values are in the daily table below it.
      </li>
      <li>
        Field status is shown with an icon and a word as well as a color. Pages follow your system's dark mode and
        reduced motion settings, and work with text enlarged to 200% and on screens as narrow as 320 pixels.
      </li>
      <li>
        Dragging a pivot's handles on the map needs a mouse or touch, but every handle also has a box below the map
        where you can type the same values. The optional map layers (radar, rain, drought) are images from outside
        services and are described by their legends and by the values shown under the pointer.
      </li>
    </ul>
    <p>
      If something in WISP is hard to use with your browser, screen reader or other assistive technology, please tell us
      at <a href="mailto:agweather@cals.wisc.edu">agweather@cals.wisc.edu</a>, with the page and what happened. We'll
      fix it, or help you get the same information another way.
    </p>

    <h2 id="contact">Credits and contact</h2>
    <p>
      WISP was developed by the Departments of Soil Science and Biological Systems Engineering at the University of
      Wisconsin–Madison, building on the Wisconsin Irrigation Scheduler (WIS) and UW Extension publication A3600. It is
      maintained by the <a href="https://vegento.russell.wisc.edu/" target="_blank" rel="noopener"
        >Vegetable Entomology Lab</a
      >
      in the UW–Madison Department of Entomology. Questions, comments and bug reports are welcome at
      <a href="mailto:agweather@cals.wisc.edu">agweather@cals.wisc.edu</a>.
    </p>
  </article>
</div>
