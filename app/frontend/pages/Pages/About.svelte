<script lang="ts">
  import { page } from '@inertiajs/svelte'

  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import Term from '@/lib/components/Term.svelte'
  import CanopyCurvePlot from '@/lib/docs/CanopyCurvePlot.svelte'
  import Introduction from '@/lib/docs/Introduction.svelte'
  import WeatherCorrectionsTable, { type WeatherCorrection } from '@/lib/docs/WeatherCorrectionsTable.svelte'
  import { GLOSSARY } from '@/lib/glossary'
  import { FULL_COVER_PCT, READING_EVERY } from '@/lib/guidance'
  import { units as unitsFor } from '@/lib/units'

  // The About page (PLAN.md Phase 6.5): WISP's documentation, replacing the legacy PDF user guide.
  // Public; the crop table comes from the plants table, the soil table from soil_types (with each
  // value's basis from db/reference/soil_types.yml), the glossary from lib/glossary.ts and the
  // reading advice from lib/guidance.ts, and the weather corrections from
  // db/reference/weather_corrections, so they stay in step with the app.

  type Plant = {
    key: string
    name: string
    root_zone_in: number
    /** FAO-56 Table 17's basal crop coefficient at full cover, mid season and at harvest (C22) */
    kcb_mid: number
    kcb_end: number
    lai_curve: boolean
    cover_curve: boolean
    /** The generic curve a crop without its own follows by default (G.3) */
    generic_curve: string | null
  }
  type GenericCurve = { key: string; name: string; basis: string; season: string | null; crops: string[] }
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
    /** The curve in growing degree days (°C days), which plantings run on (PLAN.md §9 C23) */
    thermal: {
      base_c: number
      upper_c: number
      cgc: number
      decline_start: number | null
      cdc: number | null
      basis: string
    } | null
    /** Typical days from emergence to harvest (PLAN.md Phase 8 G.2) */
    season: { days: number; basis: string } | null
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
    generic_curves,
    soil_types: soils,
    weather_corrections: corrections,
    defaults,
  }: {
    plants: Plant[]
    canopy_curves: CanopyCurve[]
    generic_curves: GenericCurve[]
    soil_types: Soil[]
    weather_corrections: WeatherCorrection[]
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
  const withoutCurve = $derived(plants.filter((plant) => !plant.cover_curve).map((plant) => plant.name.toLowerCase()))

  const pct = (fraction: number) => `${+(fraction * 100).toFixed(2)}%`
  function declineText(decline: CanopyCurve['decline']): string {
    if (!decline) return "Holds its maximum cover until the planting's end date."
    if (decline.type === 'aquacrop') {
      return `Declines from day ${decline.start_day} after emergence in a typical season, following AquaCrop's equation (CDC ${decline.cdc} a day).`
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
    { id: 'weather', title: 'Weather' },
    { id: 'glossary', title: 'Glossary' },
    { id: 'accessibility', title: 'Accessibility' },
    { id: 'privacy', title: 'Privacy' },
    { id: 'wisp-3', title: "What's new in WISP 3" },
    { id: 'history', title: 'History' },
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
      WISP treats each planting's root zone as a single bucket. How big the bucket is depends on the soil and the crop:
      it is the water held between <Term id="field_capacity">field capacity</Term> and the <Term id="wilting_point"
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
        the crop covers (<Term id="percent_cover">percent cover</Term> or <Term id="lai">LAI</Term>), for the crop
        itself (its <Term id="kc">crop coefficient</Term>; see <a href="#crops">Crops</a>), and for the water
        evaporating from the soil between the plants, which is most just after rain or irrigation.
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
      Each irrigation system's weather comes from <a href="https://open-meteo.com/" target="_blank" rel="noopener"
        >Open-Meteo</a
      >, for an area about 9 km across around its location. It's updated at 5 am, 11 am and 5 pm Central and includes
      rain, reference ET (FAO-56 Penman-Monteith), temperature, humidity, wind, and modeled soil moisture and soil
      temperature. Recent days are revised as better data arrives, then settled. Modeled rain can miss a local storm, so
      you can enter your own rain gauge readings in its place on any day. For a whole operation or a single field, you
      can also choose to count only the rain you enter. The days ahead still use the forecast rain, and the outlook for
      such a field also says when it would need water if no rain fell.
    </p>

    <h3>The outlook</h3>
    <p>
      WISP runs each planting's balance forward through the next {defaults.forecast_days} days of forecast, counting any irrigation
      you've planned, to find the day it would reach 0 AD, or the target you've set for the planting. That day is its
      <strong>Irrigate by</strong> date, along with how much water would refill the root zone then. It also runs the balance
      through 31 forecast scenarios, slightly different versions of the forecast, so you can see how sure that date is. If
      "24 of 31 forecast scenarios reach it by then," the other seven don't, so rain could well push the date back.
    </p>
    <p>Each planting gets a status for today:</p>
    <!-- Badges on one line, each beside its explanation, centered (typography aligns cells by baseline) -->
    <table class="[&_td]:align-middle [&_td:first-child]:whitespace-nowrap">
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
        <tr>
          <td><StatusBadge status="needs_canopy" /></td>
          <td>
            A planting set to readings only (no canopy curve) with no percent cover reading yet, so WISP can't estimate
            its water use. Enter a reading to start.
          </td>
        </tr>
      </tbody>
    </table>

    <h2 id="getting-started">Getting started</h2>
    <h3>Your account and operation</h3>
    <p>
      Create an account with your email address. You can sign in with a password, or have WISP email you a sign-in link
      and code. Your account comes with an operation of your own. To work on the same farms as other people, add them to
      the operation by their email address (Operation and members, in the account menu). Every member can set up fields
      and enter data. Owners can also change the operation's settings and members, and delete farms, irrigation systems
      and fields.
    </p>
    <h3>Farms, irrigation systems, fields and plantings</h3>
    <p>WISP organizes everything the way irrigation is managed:</p>
    <ul>
      <li><strong>Farm:</strong> any set of irrigation systems you want to see together, such as one location.</li>
      <li>
        <strong>Irrigation system:</strong> a place watered one way, placed on the map. Its location sets its weather,
        so put it where it really is. It's one of these:
        <ul>
          <li><strong>Pivot</strong> (center pivot): a circle, or part of one.</li>
          <li><strong>Linear</strong>: the rectangle the machine travels along.</li>
          <li>
            <strong>Traveler:</strong> a hard hose reel or big gun moved between fields. Set up a traveler at each field (or
            set of fields) it waters, and give each the machine's name under Equipment; enter irrigation on the one for the
            field it ran on that day. Weather comes from where it is, so one traveler can't stand for fields miles apart.
          </li>
          <li>
            <strong>Solid set</strong> and <strong>Drip:</strong> a block of sprinklers, or drip tape or emitters, placed
            at the block.
          </li>
          <li><strong>Location:</strong> just where the field is, for anything else.</li>
        </ul>
        Only a pivot and a linear have a shape; the others are a point, and their area is their fields'. With a flow rate
        (a pivot's pump capacity), any of them can take irrigation as hours run.
      </li>
      <li>
        <strong>Irrigation group</strong> (optional): systems on one farm that you want together, such as those near one rain
        gauge. Setup lists them together, the map outlines them, and on Daily entry rain typed for the group fills in every
        field of its systems.
      </li>
      <li>
        <strong>Field:</strong> a piece of land watered by one irrigation system, with one soil. A pivot split between
        two fields you manage separately is two fields. The soil type sets field capacity and wilting point (see
        <a href="#soils">Soils</a>); when you place the irrigation system, WISP suggests one from the USDA soil survey.
        If you know better values for your field, from the
        <a href="https://websoilsurvey.nrcs.usda.gov/" target="_blank" rel="noopener">Web Soil Survey</a> or your own
        measurements, enter them instead.
        <p>
          A field can have a <strong>shape</strong> (optional): copied from its pivot's or linear's, drawn on the map,
          or read from a file, with <strong>Draw/import field shape</strong> on the field's page.
          <strong>Import field shapes</strong> in Setup reads FSA field boundaries (Common Land Units) or boundaries exported
          from John Deere Operations Center, Climate FieldView or Google Earth, as a zipped shapefile, GeoJSON, or KML, and
          matches each to a field of the same name or adds it as a new field. The file is read in your browser; only the shapes
          you save are sent. On the map a field with a shape is drawn in white with its name, and each of its plantings' status
          badges sits at its center. A new or changed shape sets the field's area to its acres unless you type another (with
          a warning if the two are far apart), and the soil survey's main soil in it is offered for its soil; the water balance
          doesn't use the shape otherwise. An irrigation system doesn't move with its fields' shapes, since its location sets
          the weather, so Setup lists any field shape that isn't under its pivot or linear, or is more than a quarter mile
          from its traveler, drip block or other system without a shape.
        </p>
      </li>
      <li>
        <strong>Planting:</strong> a crop on a field for one season, with its emergence date, harvest date, root zone
        depth, MAD and the way its canopy is tracked. The harvest date starts at the crop's typical season after
        emergence (on each crop's card below; November 30 for crops without one, and never later), and the season ends
        there: WISP stops tracking it and asking for readings. Change it to your own date, or, once a planting is past
        its typical season, use <strong>End the season today</strong> on its page. Typical values for each crop are in
        the <a href="#crops">table below</a>. Each planting has its own water balance and its own page.
      </li>
    </ul>
    <p>
      Most plantings cover the <strong>whole field</strong>. A field can grow one after another in a year (double
      cropping, or successions in a market garden: <strong>Add the next planting</strong> starts one the day after
      another ends). To grow several crops side by side, as on a research field, make each planting
      <strong>part of the field</strong>: a plot of a given length and width, or just its area. Plots in season at once
      can't add up to more than the field without a warning, and none can be larger than it. A plot grows on the field's
      soil unless you give it its own.
    </p>
    <p>
      <strong>What's entered where:</strong> rain falls on the whole field, so it's entered for the field (on the field's
      page, a planting's page or Daily entry) and counts for every planting on it. Irrigation entered for the field, or applied
      by its irrigation system, counts for every planting too. A plot can also have its own irrigation and soil moisture readings,
      entered on its page, which it uses instead of the field's on those days.
    </p>
    <p>
      The quickest start is <strong>Get started</strong> on the dashboard of a new account. One form names a farm,
      places its irrigation system on the map, and lists the fields it waters with their soil; the system and the fields
      can each wait if you'd rather set them up later. Setup then shows the next steps: the fields still to add (by
      hand, or with
      <strong>Import field shapes</strong>), and a planting for each field this season. Until the first planting is in,
      the dashboard keeps a checklist of what's left. Everything can be changed later in Setup, where each field shows
      its season's plantings on a timeline; click one to change it. Each spring,
      <strong>Copy last season's plantings</strong>
      brings your plantings forward a year with the same settings.
    </p>

    <h2 id="day-to-day">Day to day</h2>
    <ul>
      <li>
        <strong>Dashboard:</strong> every field by farm and irrigation system, with its status, AD and outlook, and the last
        rain and irrigation. A field growing several plantings at once lists each, and sorts by the one that needs water soonest.
      </li>
      <li>
        <strong>Map:</strong> one season at a time. Each irrigation system is drawn where it is, in its own color: a
        pivot or linear as its shape, the others as their kind's symbol. Each field shows a status badge per planting,
        at the center of its shape if it has one, and each irrigation group is outlined. Beside the map the operation is
        listed farm by farm, most urgent first or north to south; <strong>Irrigate: Soon</strong> or
        <strong>Now</strong> narrows it to fields needing water within 3 days or today. Choose a farm or group to zoom to
        it, or a system or field, on the map or in the list, to see its plantings and weather. Layers add radar, rain over
        the last 24 or 72 hours, the National Weather Service's forecast rain, and the U.S. Drought Monitor; point at the
        map, or tap it, to see their values at that spot.
      </li>
      <li>
        <strong>Daily entry:</strong> rain, irrigation, soil moisture and percent cover for every field on one day, a table
        per farm. Rain typed for an irrigation system or group fills in its fields, and you can change any of them before
        saving. Irrigation can be entered once for a system and its fields. Leave rain blank to use the modeled rain. Enter
        0 if your gauge showed no rain.
      </li>
      <li>
        <strong>A field's page:</strong> its plantings this season on a timeline, each one's status, the rain and irrigation
        entered for the whole field, which rain it uses, and the week ahead. Tabs at the top open each planting.
      </li>
      <li>
        <strong>A planting's page:</strong> its status and outlook, a chart of the season, the next
        {defaults.forecast_days} days, every day's values, its crop ET, and the week ahead. Click a cell to enter or correct
        a value. Plan irrigation by entering it on a future day: it counts as applied when the day comes, so change it if
        plans change. Export the season as a CSV file. To see the page as it was on an earlier day of the season (for training,
        a demonstration, or looking back at a decision), use the clock button at the top right and pick a date. The page then
        shows what was entered up to that day, and in place of the forecast, what happened next: the weather that came, and
        the rain and irrigation entered for those days. Nothing can be changed while viewing an earlier day, and values entered
        or corrected since show as they are now.
      </li>
      <li>
        <strong>Weather:</strong> irrigation systems close together share a weather zone, one cell of the weather model's
        grid. The Weather tab lists your zones with each one's week ahead: the sky, high and low, rain and its chance, and
        reference ET. Open a zone for its year so far: rain, ET, sunshine, growing degree days (since January 1, since the
        first day in view, and since a planting went in), temperature, humidity, wind and the soil, with each chart's values
        and the whole year to download. Field, planting and irrigation system pages show their zone's week ahead and link
        to it.
      </li>
      <li>
        <strong>Alerts:</strong> a morning email at about 6 am. It groups your fields by operation, farm, weather zone (irrigation
        systems that share the same weather) and irrigation system, and gives each zone's weather, which fields to irrigate
        or watch, and which readings are due. You choose which fields it covers, which of those it lists (all, only those
        in season, only those needing irrigation or readings, or only those needing irrigation), and how often it comes: daily
        during the season, daily all year (with weather out of season too), only when a field needs irrigation, or never.
      </li>
    </ul>

    <h2 id="ground-truthing">Keeping the model on track</h2>
    <p>
      The balance is only as good as what goes into it, and small errors add up over a season. These readings matter
      most:
    </p>
    <ul>
      <li>
        <strong>Irrigation:</strong> enter every application, by irrigation system or by field. WISP can't know about water
        it isn't told about. It counts what you enter as the water that reached the crop, so enter what a gun or traveler
        actually put down after drift, if you know it. Drip goes in as the depth over the field's whole area (what run hours
        work out); WISP doesn't yet model the part of the soil drip wets, or mulch.
      </li>
      <li>
        <strong>Rain:</strong> rain is patchy, and the weather model's estimate for your field can miss a storm or catch one
        that missed you. A rain gauge at or near the field, read daily, is the best way to correct it. If you read it every
        day it rains, set the field to use only the rain you enter; the season details on its page compare your gauge with
        the model.
      </li>
      <li>
        <strong>Soil moisture:</strong> a measured root zone moisture resets the balance, correcting any drift. Enter
        one about every {READING_EVERY} days, from sensors at about 25% and 75% of the root zone depth (see the
        <a href="#crops">crop table</a>). UW Extension's
        <a href="/publications/a3600-02-methods-to-monitor-soil-moisture.pdf" target="_blank" rel="noopener"
          >Methods to Monitor Soil Moisture</a
        > (A3600-02, PDF) compares the kinds of sensor and where to put them.
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
    <p>Each planting's page shows when soil moisture and canopy were last entered, and flags them when one is due.</p>

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
      When you place an irrigation system, WISP looks up the USDA soil survey under it (around it, for one without a
      shape) and suggests the soil type that covers most of it, from the surface layer of each map unit's main soil; the
      setup map's <strong>Soil types</strong> button shows them around it. The soil menu for a new field then lists the soils
      found there first, with their shares, and notes when the one chosen isn't the main one. It's a suggestion: check it
      against what you know of the field.
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
      Every crop can use percent cover. LAI is available only for crops that have an LAI growth curve, so far field corn
      and corn silage (the same curve); more will be added as validated curves become available. Typical root zone
      depths are from Table 3.4 of the NRCS National Engineering Handbook, part 652 (mint from FAO-56; dry bean, sugar
      beet and sorghum from University of Nebraska Extension tables), and suggested sensor depths are 25% and 75% of the
      root zone depth. Every crop starts with a MAD of
      {defaults.mad_pct}% and a season from April 1 to its typical harvest (November 30 for crops without one); you can
      change any of these for your planting.
    </p>
    <p>
      <strong>Crop coefficients.</strong> WISP follows FAO-56's dual crop coefficient, which counts the crop's own water use
      and the soil's evaporation separately. The crop's share rises with its canopy to its value at full cover (FAO-56 Table
      17, the table below): about 10% more than the reference grass for potato, soybean or sweet corn, 15% for field corn,
      less for many vegetables. It's adjusted each day for the wind and humidity, as FAO-56 does (a dry, windy day raises
      a tall crop's water use more than a short one's), and from the time the canopy starts to decline (late July for potato)
      it eases toward the crop's value at harvest. The soil's share comes from the wet surface between the plants: after rain
      or irrigation, bare wet soil evaporates about as much as a full crop, and less as the surface dries over the next few
      days, more slowly on finer soils. Drip wets only part of the surface, so less evaporates. The canopy shades the soil
      as it fills in, so evaporation matters most while the crop is small and after vine kill.
    </p>
    <p>
      <strong>Season length.</strong> Each crop with a curve has a typical season, from emergence to harvest (on its card
      below). If your variety or region runs longer or shorter, such as oats farther south or an earlier corn hybrid, set
      the planting's season length: WISP stretches or shortens the crop's whole curve to fit, its growth and its decline alike,
      and suggests the harvest date from it. Your canopy readings then adjust the stretched curve as they would the typical
      one.
    </p>
    <p>
      <strong>Winter crops.</strong> A planting can run across the new year, but WISP models the irrigated season: enter winter
      wheat or rye from spring green-up, using that date as its emergence.
    </p>
    <p>
      <strong>Crops WISP doesn't model.</strong> Cranberries are managed by flooding, frost protection and the water table
      rather than by a root zone's water balance, and ginseng grows under shade, which changes its water use in ways WISP's
      reference ET doesn't account for. Neither is in the crop list.
    </p>
    <!-- Wider than a phone with its Kcb columns: a scrolling region must be reachable by keyboard (axe) -->
    <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
    <div
      class="not-prose overflow-x-auto rounded-lg border border-line bg-surface-raised"
      role="region"
      aria-label="Crops"
      tabindex="0"
    >
      <table class="w-full text-sm">
        <thead class="border-b border-line text-left text-xs text-ink-muted">
          <tr>
            <th class="px-3 py-2 font-medium">Crop</th>
            <th class="px-3 py-2 text-right font-medium">Root zone</th>
            <th class="px-3 py-2 text-right font-medium">Sensor depths</th>
            <th class="px-3 py-2 text-right font-medium"
              ><abbr title="Basal crop coefficient at full cover, mid season">Kcb</abbr></th
            >
            <th class="px-3 py-2 text-right font-medium">Kcb at harvest</th>
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
              <td class="px-3 py-1.5 text-right tabular-nums">{plant.kcb_mid.toFixed(2)}</td>
              <td class="px-3 py-1.5 text-right tabular-nums">{plant.kcb_end.toFixed(2)}</td>
              <td class="px-3 py-1.5"
                >{plant.cover_curve
                  ? 'Percent cover, with a curve'
                  : plant.generic_curve
                    ? `Percent cover, generic curve (${plant.generic_curve.toLowerCase()})`
                    : 'Percent cover, readings only'}{plant.lai_curve ? '; LAI with a curve' : ''}</td
              >
            </tr>
          {/each}
        </tbody>
      </table>
    </div>

    <h2 id="canopy">Canopy curves</h2>
    <p>
      A crop's water use follows its canopy, so WISP needs the canopy every day of the season. Every crop with a card
      below has a typical <Term id="canopy_curve">canopy curve</Term>: its percent cover as it grows from emergence.
      With no readings WISP follows it from the emergence date.
    </p>
    <p>
      <strong>The curves run on warmth, not the calendar.</strong> Crops grow faster in warm weather, so WISP counts a curve's
      time in growing degree days at the field's weather location: the season's weather so far, then the forecast, then normal
      temperatures (the average of the last 20 years) for the rest of the season. Each curve was converted from days so that,
      emerging on its typical date in a typical Central Sands season, it matches the curve drawn on its card; in a warm spring
      the canopy closes sooner, and in a cool one, or after an early April emergence, later. Against four seasons of potato
      canopy measured at the Central Sands flux towers (emerged April 21 to May 23), it put 80% cover 3 to 11 days early,
      where counting days ran from 3 days late to 21 days early, three weeks for April emergence. Against Wisconsin growers'
      2026 readings, mostly from mid to late May emergence, it was a little less close than counting days (5 days off on average,
      against 3 for the day curves, which were tuned to those readings), so readings still matter. Until WISP has a location's
      normal temperatures (usually within a day of adding an irrigation system there), its curves run by days. Potato's late-July
      decline keeps its date, and field corn's LAI curve runs by days.
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
      <strong>When your readings and the curve disagree,</strong> the planting's page says so. That happens if readings
      between 10% and 80% run more than {defaults.shift_warning_days} days ahead of or behind the curve (often a sign that
      the emergence date is off), or if a reading drops by more than {defaults.drop_warning} points while the curve is still
      growing or holding steady. Either way, WISP keeps following the curve through your readings.
    </p>
    <p>
      <strong>How the curves were made.</strong> Growth follows the canopy cover equations of FAO's AquaCrop model, with
      three numbers per crop: the cover just after emergence (CC₀), the maximum cover (CCx), and a growth rate (CGC).
      Some crops also decline late in the season. Where FAO's AquaCrop has a crop file, WISP starts from its values by
      calendar day. They matched Wisconsin 2026 readings within a few days for potato, field corn and snap bean, and
      were adjusted to match for soybean and sweet corn. For other crops the timing comes from the stage lengths in
      FAO-56. Each is then converted to growing degree days (above), with base and upper temperatures from AquaCrop's
      crop files, or assumed for crops without one: 40 °F for cool-season vegetables, 50 °F for warm-season ones. Each
      card says which source was used and how well it has been checked. The research notes, data screening and scripts
      are in
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
t: growing degree days since emergence (°C days, AquaCrop's method; days on the cards)
t′: growing degree days since the decline starts</code
      ></pre>
    <p>
      <strong>Crops without their own curve</strong> ({withoutCurve.join(', ')}) follow a generic one, a rough shape
      that your percent cover readings correct the same way, so enter one now and then. We found no published canopy
      values for onion to check against; alfalfa and mint are cut and regrow during the season; and we found no source
      for asparagus fern growth after harvest. The planting form offers each generic curve for these crops:
    </p>
    <ul>
      {#each generic_curves as curve (curve.key)}
        <li>
          <strong>{curve.name}</strong>{curve.crops.length ? ` (for ${curve.crops.join(', ').toLowerCase()})` : ''}: {curve.basis}.{#if curve.season}{' '}Typical
            season: {curve.season}.{/if}
        </li>
      {/each}
    </ul>
    <p>
      Or choose <strong>No curve: readings only</strong>: WISP then draws straight lines between your readings and
      assumes no cover until the first one, so it can't estimate the crop's water use until you enter a reading, and
      shows
      <StatusBadge status="needs_canopy" size="sm" /> until then.
    </p>
    <p>
      <strong>LAI</strong> is offered only for crops with an LAI curve, so far field corn (and corn silage), whose curve comes
      from the Wisconsin Irrigation Scheduler (WIS v6.3.11) spreadsheet and peaks at about 4 around 80 days after emergence.
      Estimating LAI from percent cover would put crop water use 20 to 40% below the percent cover method while the canopy
      develops, so WISP doesn't offer it.
    </p>
    <p class="text-sm text-ink-muted">
      Each curve is drawn by days for a crop that emerges on May 15 in a typical season, over {curves[0]?.covers
        .length - 1} days. In the field it runs by growing degree days, as each card says.
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
          {#if curve.thermal}
            <p class="text-ink-muted">
              In growing degree days: base {curve.thermal.base_c} °C, upper {curve.thermal.upper_c} °C, growth rate {curve
                .thermal.cgc} a degree day{curve.thermal.decline_start
                ? `, decline from ${curve.thermal.decline_start} degree days (CDC ${curve.thermal.cdc} a degree day)`
                : ''}. {curve.thermal.basis}.
            </p>
          {/if}
          {#if curve.notes}<p class="text-ink-muted">{curve.notes}</p>{/if}
          {#if curve.season}
            <p class="text-ink-muted">
              Typical season: {curve.season.days} days from emergence to harvest ({curve.season.basis}).
            </p>
          {/if}
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

    <h2 id="weather">Weather</h2>
    <p>
      WISP's weather comes from <a href="https://open-meteo.com/" target="_blank" rel="noopener">Open-Meteo</a>, for the
      grid cell (about 9 km across) around each irrigation system: the National Blend of Models (NBM) where it has a
      value, and Open-Meteo's best match of other models where it doesn't. The last week is refreshed as the models
      revise it; the next {defaults.forecast_days} days are the latest forecast, and the field chart's range of outcomes comes
      from the 31 runs of the GFS ensemble forecast. The week ahead's chance of rain is the share of those runs with at least
      0.01 in that day, and its sky is the day's most severe weather in the forecast (a thunderstorm, fog, freezing rain or
      snow), or how cloudy the day is on average.
    </p>
    <h3 id="weather-corrections">Weather corrections</h3>
    <p>
      Checked against 80 Wisconet weather stations across Wisconsin in 2025 and 2026, Open-Meteo's solar radiation reads
      15–20% high and its humidity runs dry, so its <Term id="reference_et">reference ET</Term> came out about 16% above what
      the stations' own measurements give. WISP corrects both, hour by hour, and works out reference ET itself from the corrected
      hours with the same FAO-56 equation. The corrections and the evidence for them come from AgWeather, the UW–Madison weather
      service, which made the comparison. Each day of weather records which corrections it went through, and the weather downloads
      include the values before them.
    </p>
    <WeatherCorrectionsTable {corrections} />
    <p>
      The corrections were fitted in Wisconsin. Irrigation systems elsewhere get them too until they're checked against
      stations in other states.
    </p>
    <h3 id="et-validation">Checked against measured water use</h3>
    <p>
      Reference ET and crop coefficients are estimates, so we checked WISP's crop water use against measurements. From
      2018 to 2023, UW–Madison researchers (Ammara Talib, Ankur Desai and colleagues), funded in part by the Wisconsin
      Potato and Vegetable Growers Association, ran flux towers in center-pivot irrigated potato fields in the Central
      Sands, one each season. A flux tower measures the water vapor rising from a field, so it measures the crop's water
      use directly. Their study found that the ET WISP used until WISP 3, from AgWeather, ran 20–35% above what the
      towers measured, and traced the error to how it estimated the heat a field loses to the sky.
    </p>
    <p>
      We ran WISP 3's method over the same six potato seasons. At full canopy, its potato water use came within 3% of
      what the towers measured when worked out from the towers' own weather readings, and about 9% above when worked out
      from the weather WISP uses (3% leaving out the 2023 drought). Those comparisons include the standard correction
      for what towers like these miss: they account for only about 80% of the energy reaching a field, and over a
      well-watered crop nearly all of the rest goes into water use. On the same comparison, the old AgWeather ET ran 13%
      high, and the researchers' adjusted version of it 15% low.
    </p>
    <p>
      The analysis, its data and scripts are in
      <a href="https://github.com/uwent/wisp3/tree/main/docs/et-validation" target="_blank" rel="noopener"
        >the WISP source code</a
      >. Over the whole season, with the researchers' crop dates and canopy cover for four of the seasons, it showed
      that WISP's earlier method missed the water evaporating from wet soil while the canopy was small and after vine
      kill, and kept the crop's full water use into August. WISP now counts that evaporation and eases the crop's water
      use toward harvest, as described under <a href="#crops">Crops</a>: against the towers it's within 1% at full
      canopy and 5% over the season, and still somewhat high while the canopy is small and after vine kill.
    </p>

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
        Dragging a pivot's or linear's handles on the map needs a mouse or touch, but every handle also has a box below
        the map where you can type the same values. Drawing a field's shape also needs a mouse or touch; a shape can
        instead be copied from its pivot or linear with one button, or read from a file. The optional map layers (radar,
        rain, drought) are images from outside services and are described by their legends and by the values shown under
        the pointer.
      </li>
    </ul>
    <p>
      If something in WISP is hard to use with your browser, screen reader or other assistive technology, please tell us
      at <a href="mailto:agweather@cals.wisc.edu">agweather@cals.wisc.edu</a>, with the page and what happened. We'll
      fix it, or help you get the same information another way.
    </p>

    <h2 id="privacy">Privacy</h2>
    <p>
      WISP's public pages (this one, the home page, signing in and signing up, and the example farm) use Google
      Analytics to count visits and see how people find WISP. Google Analytics isn't used once you're signed in, and
      never sees your farms or their data.
    </p>
    <p>
      Inside your account, WISP notes the days you use it and which parts (the dashboard, the map, daily entry and so
      on), so we can see what's useful and what to improve. It doesn't record what you look at or when. Your farm data
      stays in WISP: it isn't shared or sold, and deleting your account deletes the farms only you can reach.
    </p>

    <h2 id="wisp-3">What's new in WISP 3</h2>
    <p>
      WISP 3 is a rebuild of WISP 2012 for the 2027 season. The water balance is the same checkbook; what's new is
      mostly around it:
    </p>
    <ul>
      <li>
        <strong>Weather for each irrigation system,</strong> from Open-Meteo, corrected against Wisconsin weather
        stations (see <a href="#weather">Weather</a>), in place of AgWeather.
      </li>
      <li>
        <strong>An outlook:</strong> the balance runs on through the 16-day forecast and its range of scenarios, so each planting
        shows when it will need water, how much, and how sure the forecast is.
      </li>
      <li>
        <strong>Crop water use</strong> from each crop's FAO-56 crop coefficient and a typical canopy curve, which your
        cover readings correct (see <a href="#crops">Crops</a>), checked against flux towers in Central Sands potato
        fields (see <a href="#et-validation">Checked against measured water use</a>).
      </li>
      <li>
        <strong>Plantings on part of a field,</strong> side by side, each with its own balance and page, and a page that can
        show any earlier day of the season.
      </li>
      <li>
        <strong>A map</strong> of the operation with field outlines, and every kind of irrigation system: pivots, linears,
        travelers, solid set and drip.
      </li>
      <li>
        <strong>Less to enter:</strong> one page for the whole operation's daily readings, irrigation entered once for a system,
        and a morning email of what needs water.
      </li>
      <li>
        <strong>Seasons kept</strong> from year to year, with last season's setup copied forward; operations shared with other
        members; CSV downloads; and pages that work on a phone and with assistive technology.
      </li>
    </ul>

    <h2 id="history">History</h2>
    <p>
      WISP began on paper. UW Extension publication A3600, <cite
        >Irrigation Management in Wisconsin: The Wisconsin Irrigation Scheduling Program (WISP)</cite
      >, by David Curwen (Horticulture) and Leonard Massie (Biological Systems Engineering), taught growers to schedule
      irrigation like balancing a checkbook: rain and irrigation as deposits, the crop's water use as withdrawals, kept
      day by day on an accounting form. Its table for adjusting ET to the crop's percent cover is still part of WISP.
      Spreadsheets and desktop programs carried the method onto computers.
    </p>
    <p>
      In the 1990s, scientists in UW–Madison's Department of Soil Science and its Cooperative Institute for
      Meteorological Satellite Studies began estimating each day's sunshine and ET across Wisconsin from satellite data,
      the start of the AgWeather service that supplied WISP's weather until WISP 3.
    </p>
    <p>
      WISP moved to the web as WISP 2012, developed in the Departments of Soil Science and Biological Systems
      Engineering. John Panuska and Scott Sanford revised A3600 alongside it (now
      <a href="/publications/a3600-01-irrigation-management-in-wisconsin.pdf" target="_blank" rel="noopener">A3600-01</a
      >), with a companion on monitoring soil moisture (<a
        href="/publications/a3600-02-methods-to-monitor-soil-moisture.pdf"
        target="_blank"
        rel="noopener">A3600-02</a
      >). Since 2021 WISP has been maintained in the Department of Entomology, and WISP 3 was rewritten there for the
      2027 season.
    </p>

    <h2 id="contact">Credits and contact</h2>
    <p>
      WISP 3 is developed and maintained by Ben Bradford in the
      <a href="https://vegento.russell.wisc.edu/" target="_blank" rel="noopener">Vegetable Entomology Lab</a>,
      UW–Madison Department of Entomology. WISP 2012 was built by Rick Wayne, Paul Kaarakka, Mark McEahern, Allen
      Ballman and Ben Bradford, with academic leadership from Bill Bland (Soil Science) and John Panuska and Scott
      Sanford (Biological Systems Engineering).
    </p>
    <p>
      The flux tower measurements are AmeriFlux data from Ankur Desai's group (UW–Madison Atmospheric and Oceanic
      Sciences), shared under CC BY 4.0: Talib et al. (2024),
      <cite
        >Improving parameterization of an evapotranspiration estimation model with eddy covariance measurements for a
        regional irrigation scheduling program</cite
      >,
      <a href="https://doi.org/10.1016/j.agrformet.2024.109967" target="_blank" rel="noopener"
        >Agricultural and Forest Meteorology 350</a
      >.
    </p>
    <p>
      Questions, comments and bug reports are welcome at
      <a href="mailto:agweather@cals.wisc.edu">agweather@cals.wisc.edu</a>. WISP's source code is on
      <a href="https://github.com/uwent/wisp3" target="_blank" rel="noopener">GitHub</a>.
    </p>
  </article>
</div>
