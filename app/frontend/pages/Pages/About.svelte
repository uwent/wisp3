<script lang="ts">
  import { page } from '@inertiajs/svelte'

  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import Term from '@/lib/components/Term.svelte'
  import Introduction from '@/lib/docs/Introduction.svelte'
  import { GLOSSARY } from '@/lib/glossary'
  import { FULL_COVER_PCT, READING_EVERY } from '@/lib/guidance'
  import { units as unitsFor } from '@/lib/units'

  // The About page (PLAN.md Phase 6.5): WISP's documentation, replacing the legacy PDF user guide.
  // Public; the crop table comes from the plants table, the glossary from lib/glossary.ts and the
  // reading advice from lib/guidance.ts, so they stay in step with the app.

  type Plant = { key: string; name: string; root_zone_in: number; lai_curve: boolean }
  let {
    plants,
    defaults,
  }: { plants: Plant[]; defaults: { mad_pct: number; lead_days: number; forecast_days: number } } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const depth = (inches: number) => units.format('rootDepth', inches)

  const sections = [
    { id: 'introduction', title: 'What WISP is' },
    { id: 'how-it-works', title: 'How it works' },
    { id: 'getting-started', title: 'Getting started' },
    { id: 'day-to-day', title: 'Day to day' },
    { id: 'ground-truthing', title: 'Keeping the model on track' },
    { id: 'crops', title: 'Crops' },
    { id: 'glossary', title: 'Glossary' },
    { id: 'contact', title: 'Credits and contact' },
  ]
</script>

<svelte:head><title>About WISP</title></svelte:head>

<div class="grid gap-8 lg:grid-cols-[12rem_1fr]">
  <nav aria-label="On this page" class="hidden lg:block">
    <ul class="sticky top-6 space-y-1 text-sm">
      {#each sections as section (section.id)}
        <li><a href="#{section.id}" class="block rounded px-2 py-1 text-ink-muted hover:bg-surface-raised hover:text-ink">{section.title}</a></li>
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
      WISP treats each field's root zone as a single reservoir. Its size depends on the soil and the crop: the water held
      between <Term id="field_capacity">field capacity</Term> and the <Term id="wilting_point">wilting point</Term>, over
      the depth of the root zone. Of that, the crop can use a share without stress, set by its
      <Term id="mad">MAD</Term> ({defaults.mad_pct}% unless you change it). WISP tracks how much of that share is left,
      the <Term id="ad">allowable depletion (AD)</Term>, from day to day:
    </p>
    <ul>
      <li><strong>Rain and irrigation</strong> add to it.</li>
      <li>
        <strong>The crop's water use</strong> (<Term id="crop_et">crop ET</Term>) takes from it. It is the day's
        <Term id="reference_et">reference ET</Term>, worked out from the weather, scaled by how much of the ground the crop
        covers (<Term id="percent_cover">percent cover</Term> or <Term id="lai">LAI</Term>).
      </li>
      <li>
        Water beyond field capacity drains below the roots and is counted as <Term id="deep_drainage">deep drainage</Term>.
      </li>
      <li>A soil moisture reading you enter resets the balance to what you measured.</li>
    </ul>
    <p>
      A full root zone has AD at its maximum. At 0 AD the crop has used its allowance and it's time to irrigate; below 0 it
      is increasingly stressed. The balance is worked out afresh from the season's start every time you look, so a value
      you correct last week flows through to today straight away.
    </p>

    <h3>Weather</h3>
    <p>
      Each pivot's weather comes from <a href="https://open-meteo.com/" target="_blank" rel="noopener">Open-Meteo</a> for the
      roughly 9 km grid cell it sits in, refreshed at 5 am, 11 am and 5 pm Central: rain, reference ET (FAO-56
      Penman-Monteith), temperatures, humidity, wind, and modeled soil moisture and temperature. Past days are revised as
      better data comes in, then fixed. You can use your own rain gauge readings in place of the modeled rain on any day,
      or, for a whole operation or a single field, use only the rain you enter. The days ahead still use the forecast's
      rain, and such a field's outlook also says when it would need water if no rain fell.
    </p>

    <h3>The outlook</h3>
    <p>
      WISP runs each field's balance forward through the next {defaults.forecast_days} days of forecast, counting any
      irrigation you've planned, to find the day it would reach 0 AD, or the target you've set for the field. That day
      is its <strong>Irrigate by</strong> date, along with how much water would refill the root zone then. It also runs the
      balance through 31 forecast scenarios, so you can see how sure that date is: "24 of 31 forecast scenarios reach it by
      then" means rain could well push it back.
    </p>
    <p>Each field gets a status for today:</p>
    <table>
      <tbody>
        <tr><td><StatusBadge status="full" /></td><td>Near field capacity: AD at 90% of its maximum or more.</td></tr>
        <tr><td><StatusBadge status="ok" /></td><td>Above its target, or above half its maximum AD without one.</td></tr>
        <tr>
          <td><StatusBadge status="caution" /></td>
          <td>
            Below its target (or half its maximum AD) but above 0, or projected to reach the irrigation point within
            {defaults.lead_days} days.
          </td>
        </tr>
        <tr><td><StatusBadge status="irrigate" /></td><td>At or below the irrigation point, 0 AD, today.</td></tr>
      </tbody>
    </table>

    <h2 id="getting-started">Getting started</h2>
    <h3>Your account and operation</h3>
    <p>
      Create an account with your email address. You can sign in with a password, or have WISP email you a sign-in link and
      code. Your account comes with a farm operation of your own. To work on the same farms as other people, add them to
      the operation by their email address (Farm operation and members, in the account menu). Every member can set up and
      enter data; owners can also change the operation's settings and members, and delete farms, pivots and fields.
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
        between two crops is two fields. The soil type sets field capacity and wilting point; if you know better values
        for your field, from the
        <a href="https://websoilsurvey.nrcs.usda.gov/" target="_blank" rel="noopener">Web Soil Survey</a> or your own
        measurements, enter them instead.
      </li>
      <li>
        <strong>Crop (planting):</strong> a crop on a field for one season, with its emergence date, root zone depth, MAD
        and canopy method. Defaults for each crop are in the <a href="#crops">table below</a>. A field can have more than one
        planting a year, for double cropping.
      </li>
    </ul>
    <p>
      The quickest start is <strong>Set up a pivot</strong> on the Setup page: place the pivot, then add its fields and
      crops in one form. Everything can be changed later in Setup. Each spring, <strong>Copy last season's crops</strong>
      brings your crops forward a year with the same settings.
    </p>

    <h2 id="day-to-day">Day to day</h2>
    <ul>
      <li>
        <strong>Dashboard:</strong> every field by farm and pivot, with its status, AD and outlook, and the last rain and
        irrigation.
      </li>
      <li>
        <strong>Daily entry:</strong> rain, irrigation and soil moisture for every field on one day. Irrigation can be
        entered once for a pivot and its fields. Leave rain blank to use the modeled value; enter 0 if your gauge read
        nothing.
      </li>
      <li>
        <strong>Field groups</strong> (in Setup): fields that share readings, such as one rain gauge. Values entered for a
        group apply to each of its fields.
      </li>
      <li>
        <strong>A field's page:</strong> its status and outlook, a chart of the season, the next
        {defaults.forecast_days} days, every day's values, and the weather. Click a cell to enter or correct a value. Plan
        irrigation by entering it on a future day: it counts as applied when the day comes, so change it if plans change.
        Export the season as a CSV file.
      </li>
      <li>
        <strong>Alerts:</strong> a morning email at about 6 am with your fields by farm and pivot, each pivot's weather, and
        which fields to irrigate or watch. Choose to get it daily during the season, only when a field needs irrigation, or
        never, and which fields it covers.
      </li>
    </ul>

    <h2 id="ground-truthing">Keeping the model on track</h2>
    <p>
      The balance is only as good as what goes into it, and small errors add up over a season. These readings matter most:
    </p>
    <ul>
      <li>
        <strong>Irrigation:</strong> enter every application, by pivot or by field. WISP can't know about water it isn't told
        about.
      </li>
      <li>
        <strong>Rain:</strong> rain is patchy, and the weather model's estimate for your pivot can miss a storm or catch one
        that missed you. A gauge at or near the field, read daily, is the single best correction. If you read it every day
        it rains, set the field to use only the rain you enter; the season details on its page compare your gauge with the
        model.
      </li>
      <li>
        <strong>Soil moisture:</strong> a measured root zone moisture resets the balance, correcting any drift. Enter one about
        every {READING_EVERY} days, from sensors at about 25% and 75% of the root zone depth (see the
        <a href="#crops">crop table</a>).
      </li>
      <li>
        <strong>Canopy:</strong> with percent cover, enter it about weekly from emergence until the canopy covers about
        {FULL_COVER_PCT}% of the ground; WISP holds the last value after that. For row crops, divide the average canopy width
        by the row spacing. With LAI, field corn follows a growth curve unless you enter readings; other crops use only the
        LAI you enter, and use no water in the model until the first reading.
      </li>
      <li>
        <strong>Root zone depth:</strong> the defaults are typical; the depth your crop actually roots to is best measured in
        the field at full canopy. For potatoes, measure from the top of the hill.
      </li>
    </ul>
    <p>Each field's page shows when soil moisture and canopy were last entered, and flags them when one is due.</p>

    <h2 id="crops">Crops</h2>
    <p>
      Every crop can use percent cover. LAI with a growth curve is available for field corn; other crops can use LAI only
      with readings you enter. Default root zone depths are from Table 3.4 of the NRCS National Engineering Handbook, part
      652 (mint from FAO-56), and suggested sensor depths are 25% and 75% of them. Every crop starts with MAD
      {defaults.mad_pct}% and a season from April 1 to November 30; change any of them for your planting.
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
              <td class="px-3 py-1.5">Percent cover; LAI {plant.lai_curve ? 'from a growth curve or readings' : 'from readings only'}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>

    <h2 id="glossary">Glossary</h2>
    <dl>
      {#each GLOSSARY as entry (entry.id)}
        <dt id="glossary-{entry.id}" class="scroll-mt-6">{entry.term}</dt>
        <dd>{entry.definition}</dd>
      {/each}
    </dl>

    <h2 id="contact">Credits and contact</h2>
    <p>
      WISP was developed by the Departments of Soil Science and Biological Systems Engineering at the University of
      Wisconsin–Madison, building on the Wisconsin Irrigation Scheduler (WIS) and UW Extension publication A3600. It is
      maintained by the <a href="https://vegento.russell.wisc.edu/" target="_blank" rel="noopener">Vegetable Entomology Lab</a>
      in the UW–Madison Department of Entomology. Questions, comments and bug reports are welcome at
      <a href="mailto:agweather@cals.wisc.edu">agweather@cals.wisc.edu</a>.
    </p>
  </article>
</div>
