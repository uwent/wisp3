<script lang="ts">
  import { Link } from '@inertiajs/svelte'

  import Spinner from '@/lib/components/Spinner.svelte'
  import type { WeatherUpdate } from '@/lib/poll'
  import Sparkline from '@/lib/components/Sparkline.svelte'
  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import { formatDate, relativeDay } from '@/lib/dates'
  import { outlook } from '@/lib/outlook'
  import type { FieldCard } from '@/lib/overview'
  import { cardWhen, cropName, seasonLine, seasonStats } from '@/lib/plantings'
  import type { Units } from '@/lib/units'
  import { fields, planting as plantingRoute } from '@/routes'
  import type { PlantingSummary } from '@/types/serializers'

  // A field's status card: on the dashboard (the whole card links to its planting), and compact on
  // the map, where onselect makes the card select it, with its own View link (G.14). weather: whether the pivot's weather is
  // being fetched (the page reloads until it lands) or the page gave up waiting.
  //
  // A field growing several plantings at once (plots, PLAN.md Phase 8 G.11) lists each, linking to
  // its page, with the field's name linking to the field: in full up to MANY of them, then as a
  // compact list of one line each (research fields with many plots).
  let {
    card,
    weather = null,
    today,
    units,
    compact = false,
    selected = false,
    onselect,
  }: {
    card: FieldCard
    weather?: WeatherUpdate
    today: string
    units: Units
    compact?: boolean
    selected?: boolean
    onselect?: () => void
  } = $props()

  const MANY = 3

  const several = $derived(card.plantings.length > 1)
  const list = $derived(card.plantings.length > MANY)
  const single = $derived(card.plantings[0] ?? null)
  const href = $derived(single && !several ? plantingRoute(single.planting_id) : fields.show(card.id))

  // "9.2% soil moisture · AD 0.31 in of 0.48 in", under the outlook (G.6)
  const moistureLine = (summary: PlantingSummary) =>
    `${summary.pct_moisture === null ? '' : `${summary.pct_moisture.toFixed(1)}% soil moisture · `}AD ${units.format('depth', summary.ad)} of ${units.format('depth', summary.ad_max)}`

  const frame = $derived(
    `block h-full rounded-lg border bg-surface-raised ${compact ? 'space-y-2 p-3' : 'space-y-3 p-4'}
    ${selected ? 'border-brand-600 ring-2 ring-brand-500' : 'border-line hover:border-brand-500'}`,
  )
</script>

{#snippet badge(summary: PlantingSummary | null)}
  {#if summary?.phase === 'active'}
    <StatusBadge status={summary.status} size="sm" />
  {:else if summary?.phase === 'ended'}
    <span class="shrink-0 rounded-full border border-line px-2 py-0.5 text-xs whitespace-nowrap text-ink-muted"
      >Season ended</span
    >
  {/if}
{/snippet}

{#snippet heading()}
  <div class="min-w-0">
    <h4 class="truncate font-medium">
      <span class="font-normal text-ink-muted">Field:</span>
      {card.name}
    </h4>
    {#if single && !several}
      <p class="truncate text-xs text-ink-muted">{cropName(single)}</p>
      <p class="truncate text-[0.7rem] text-ink-muted">{cardWhen(single, today)}</p>
    {:else if several}
      <p class="truncate text-xs text-ink-muted">{card.plantings.length} plantings</p>
    {/if}
  </div>
{/snippet}

<!-- One planting's status: its AD, sparkline, outlook and readings due -->
{#snippet status(summary: PlantingSummary, small: boolean)}
  {@const look = outlook(summary, units)}
  {@const todo = summary.tasks.filter((task) => task.due)}
  {#if summary.weather_pending && weather === 'failed'}
    <p class="text-sm text-status-caution-ink">Weather update failed. Refresh the page to try again.</p>
  {:else if summary.weather_pending}
    <p class="flex items-start gap-1.5 text-sm text-ink-muted">
      {#if weather === 'updating'}<Spinner class="mt-0.5" />{/if}
      <span>Weather for this location is on its way. The water balance will appear when it arrives.</span>
    </p>
  {:else if summary.phase === 'upcoming'}
    <p class="text-sm text-ink-muted">The season starts {formatDate(summary.season_start)}.</p>
  {:else if summary.phase === 'ended'}
    <!-- An ended season in brief (G.6): what it took, in place of AD and the outlook -->
    {#if small}
      <p class="text-xs text-ink-muted">{seasonLine(summary.totals, units)}</p>
    {:else}
      <dl class="grid grid-cols-2 gap-2 text-xs">
        {#each seasonStats(summary.totals, units) as stat (stat.label)}
          <div>
            <dt class="text-ink-muted">{stat.label}</dt>
            <dd>{stat.value}</dd>
          </div>
        {/each}
      </dl>
    {/if}
  {:else}
    <!-- The outlook leads (G.6), with moisture and AD beneath it -->
    {#if look}
      <p
        class="{small ? 'text-sm font-medium' : 'text-base font-semibold'} {look.urgent
          ? 'text-status-irrigate-ink'
          : ''}"
      >
        {look.headline}
      </p>
    {/if}
    <div class="flex items-end justify-between gap-3">
      <p class="text-xs text-ink-muted tabular-nums">{moistureLine(summary)}</p>
      <Sparkline
        class={small ? 'max-w-24' : 'max-w-32'}
        values={summary.recent.map((day) => day.ad)}
        projected={summary.projection.map((day) => day.ad)}
        max={summary.ad_max}
        min={summary.ad_pwp}
        label="Allowable depletion over the last {summary.recent.length} days{summary.projection.length
          ? `, and the ${summary.projection.length} days ahead`
          : ''}"
      />
    </div>
    {#if !small}
      <dl class="grid grid-cols-2 gap-2 text-xs">
        <div>
          <dt class="text-ink-muted">Last rain</dt>
          <dd>
            {#if summary.last_rain}{units.format('depth', summary.last_rain.inches)}, {relativeDay(
                summary.last_rain.date,
                today,
              )}{:else}None{/if}
          </dd>
        </div>
        <div>
          <dt class="text-ink-muted">Last irrigation</dt>
          <dd>
            {#if summary.last_irrigation}{units.format('depth', summary.last_irrigation.inches)}, {relativeDay(
                summary.last_irrigation.date,
                today,
              )}{:else}None{/if}
          </dd>
        </div>
      </dl>
    {/if}
    {#if todo.length}
      <ul class="space-y-1 border-t border-line pt-2 text-xs" aria-label="Readings and checks due">
        {#each todo as task (task.kind)}
          <li class="flex gap-1.5" title={task.message ?? undefined}>
            <span aria-hidden="true" class="text-status-caution-ink">○</span>
            <span>{task.todo}</span>
          </li>
        {/each}
      </ul>
    {/if}
  {/if}
{/snippet}

{#snippet weatherNote()}
  {#if weather === 'updating' && card.plantings.some((s) => s.phase !== 'ended' && !s.weather_pending)}
    <p class="flex items-center gap-1.5 text-xs text-ink-muted"><Spinner />Updating weather…</p>
  {:else if weather === 'failed' && card.plantings.some((s) => s.phase !== 'ended' && !s.weather_pending)}
    <p class="text-xs text-status-caution-ink">Weather update failed. Refresh the page to try again.</p>
  {/if}
{/snippet}

<!-- A field with one planting (or none): the card as it always was -->
{#snippet one()}
  <div class="flex items-start justify-between gap-2">
    {@render heading()}
    {@render badge(single)}
  </div>
  {#if !single}
    <p class="text-sm text-ink-muted">No crop this season. Add a planting in Setup.</p>
  {:else}
    {@render status(single, compact)}
    {@render weatherNote()}
  {/if}
{/snippet}

<!-- A field with several plantings: each in brief, or one line each when there are many (its crop,
     when it is and its status; the planting's page has the rest) -->
{#snippet each(linked: boolean)}
  {#if list}
    <ul class="divide-y divide-line border-t border-line text-sm" aria-label="Plantings on {card.name}">
      {#each card.plantings as summary (summary.planting_id)}
        {@const look = summary.phase === 'active' ? outlook(summary, units) : null}
        <li>
          {#snippet row()}
            <span class="min-w-0 flex-1">
              <span class="block">{cropName(summary)}</span>
              <span class="block text-xs text-ink-muted">{cardWhen(summary, today)}</span>
              {#if look}<span
                  class="block text-xs {look.urgent ? 'font-medium text-status-irrigate-ink' : 'text-ink-muted'}"
                  >{look.headline}</span
                >{/if}
              <!-- Moisture and AD in season, the stats once ended; nothing while weather is on its way (the card's note says so) -->
              {#if !summary.weather_pending && summary.phase === 'ended'}
                <span class="block text-xs text-ink-muted">{seasonLine(summary.totals, units)}</span>
              {:else if !summary.weather_pending && summary.phase === 'active' && summary.status !== 'needs_canopy'}
                <span class="block text-xs text-ink-muted tabular-nums">{moistureLine(summary)}</span>
              {/if}
            </span>
            {@render badge(summary)}
          {/snippet}
          {#if linked}
            <Link href={plantingRoute(summary.planting_id)} class="flex items-center gap-2 py-1.5 hover:bg-surface"
              >{@render row()}</Link
            >
          {:else}
            <div class="flex items-center gap-2 py-1.5">{@render row()}</div>
          {/if}
        </li>
      {/each}
    </ul>
  {:else}
    <ul class="space-y-3" aria-label="Plantings on {card.name}">
      {#each card.plantings as summary (summary.planting_id)}
        <li class="border-t border-line pt-2">
          {#snippet brief()}
            <div class="flex items-start justify-between gap-2">
              <div class="min-w-0">
                <p class="truncate text-sm font-medium">{cropName(summary)}</p>
                <p class="truncate text-xs text-ink-muted">{cardWhen(summary, today)}</p>
              </div>
              {@render badge(summary)}
            </div>
            {@render status(summary, true)}
          {/snippet}
          {#if linked}
            <Link
              href={plantingRoute(summary.planting_id)}
              class="-mx-1 block space-y-2 rounded-md px-1 hover:bg-surface">{@render brief()}</Link
            >
          {:else}
            <div class="space-y-2">{@render brief()}</div>
          {/if}
        </li>
      {/each}
    </ul>
  {/if}
  {@render weatherNote()}
{/snippet}

{#if onselect}
  <!-- The whole card selects; the field's own link sits above the select button -->
  <div class="relative {frame}" data-field-card={card.id}>
    <button
      type="button"
      class="absolute inset-0 rounded-lg focus-visible:outline-2 focus-visible:outline-brand-500"
      aria-label="Show {card.name} on the map"
      aria-pressed={selected}
      onclick={onselect}
    ></button>
    <div class="pointer-events-none relative space-y-2">
      {#if several}
        {@render heading()}
        {@render each(false)}
      {:else}
        {@render one()}
      {/if}
    </div>
    <Link
      {href}
      class="relative mt-2 inline-block text-xs font-medium text-brand-600 hover:underline"
      aria-label="View {card.name}">View</Link
    >
  </div>
{:else if several}
  <!-- Links inside: the field's name opens the field, each planting its own page -->
  <div class={frame}>
    <div class="flex items-start justify-between gap-2">
      <Link href={fields.show(card.id)} class="min-w-0 hover:underline">{@render heading()}</Link>
    </div>
    {@render each(true)}
  </div>
{:else}
  <Link {href} class={frame}>
    {@render one()}
  </Link>
{/if}
