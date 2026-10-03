<script lang="ts">
  import { Link, page } from '@inertiajs/svelte'

  import Sparkline from '@/lib/components/Sparkline.svelte'
  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import { formatDate, relativeDay } from '@/lib/dates'
  import { units as unitsFor } from '@/lib/units'
  import { dailyEntries, fields, newQuickSetup, setup } from '@/routes'
  import type { PlantingSummary } from '@/types/serializers'

  type Card = {
    field: { id: number; name: string }
    pivot: { id: number; name: string }
    farm: { id: number; name: string }
    summary: PlantingSummary | null
  }

  let { today, cards, farm_count }: { today: string; cards: Card[]; farm_count: number } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const farms = $derived([...new Map(cards.map((card) => [card.farm.id, card.farm])).values()])
  let farmId = $state<number | 'all'>('all')

  const shown = $derived(cards.filter((card) => farmId === 'all' || card.farm.id === farmId))
  const byFarm = $derived(farms.map((farm) => ({ farm, cards: shown.filter((card) => card.farm.id === farm.id) })).filter((g) => g.cards.length))

  // "3 days ago" during the season; a plain date once it's over
  const when = (summary: PlantingSummary, date: string) =>
    summary.phase === 'active' ? relativeDay(date, today) : formatDate(date)

  const counts = $derived(
    (['irrigate', 'caution', 'ok', 'full'] as const).map((status) => ({
      status,
      count: shown.filter((card) => card.summary?.phase === 'active' && card.summary.status === status).length,
    })),
  )
</script>

<svelte:head><title>Dashboard · WISP</title></svelte:head>

<div class="flex flex-wrap items-end justify-between gap-3">
  <div>
    <h1 class="text-2xl font-semibold">Dashboard</h1>
    <p class="text-sm text-ink-muted">{page.props.auth.group?.name} · {formatDate(today, { weekday: true, year: true })}</p>
  </div>
  {#if cards.length}
    <div class="flex flex-wrap items-center gap-2">
      {#if farms.length > 1}
        <label class="sr-only" for="farm-filter">Farm</label>
        <select id="farm-filter" class="rounded-md text-sm" bind:value={farmId}>
          <option value="all">All farms</option>
          {#each farms as farm (farm.id)}<option value={farm.id}>{farm.name}</option>{/each}
        </select>
      {/if}
      <Link
        href={dailyEntries.show()}
        class="rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 dark:text-surface"
      >
        Enter rain and irrigation
      </Link>
    </div>
  {/if}
</div>

{#if farm_count === 0}
  <section class="rounded-lg border border-dashed border-line bg-surface-raised px-6 py-12 text-center">
    <h2 class="text-lg font-medium">Set up your first pivot</h2>
    <p class="mx-auto mt-2 max-w-md text-sm text-ink-muted">
      Place it on the map and add its fields and crops. It takes a few minutes, and WISP starts tracking each field's
      soil water straight away.
    </p>
    <Link
      href={newQuickSetup()}
      class="mt-6 inline-block rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 dark:text-surface"
    >
      Get started
    </Link>
  </section>
{:else if cards.length === 0}
  <section class="rounded-lg border border-dashed border-line bg-surface-raised px-6 py-12 text-center">
    <h2 class="text-lg font-medium">No fields yet</h2>
    <p class="mt-2 text-sm text-ink-muted">Add fields to your pivots to see their water status here.</p>
    <Link href={setup.show()} class="mt-4 inline-block text-sm text-brand-600 hover:underline">Go to setup</Link>
  </section>
{:else}
  <div class="flex flex-wrap gap-2 text-sm" aria-label="Fields by status">
    {#each counts as { status, count } (status)}
      {#if count}<span class="flex items-center gap-1.5"><StatusBadge {status} size="sm" /> {count}</span>{/if}
    {/each}
  </div>

  {#each byFarm as group (group.farm.id)}
    <section class="space-y-3">
      <h2 class="text-lg font-medium">{group.farm.name}</h2>
      <ul class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {#each group.cards as card (card.field.id)}
          {@const summary = card.summary}
          <li>
            <Link
              href={fields.show(card.field.id)}
              class="block h-full space-y-3 rounded-lg border border-line bg-surface-raised p-4 hover:border-brand-500"
            >
              <div class="flex items-start justify-between gap-2">
                <div class="min-w-0">
                  <h3 class="truncate font-medium">{card.field.name}</h3>
                  <p class="truncate text-xs text-ink-muted">
                    {card.pivot.name}{#if summary}{` · ${summary.plant_name}`}{#if summary.variety}{` (${summary.variety})`}{/if}{/if}
                  </p>
                </div>
                {#if summary?.phase === 'active'}<StatusBadge status={summary.status} size="sm" />{/if}
              </div>

              {#if !summary}
                <p class="text-sm text-ink-muted">No crop this season. Add a planting in setup.</p>
              {:else if summary.weather_pending}
                <p class="text-sm text-ink-muted">Weather for this pivot is on the way; the water balance fills in once it arrives.</p>
              {:else if summary.phase === 'upcoming'}
                <p class="text-sm text-ink-muted">Season starts {formatDate(summary.season_start)}</p>
              {:else}
                <div class="flex items-end justify-between gap-3">
                  <div>
                    <div class="text-xs text-ink-muted">
                      AD {summary.phase === 'ended' ? `at season end (${formatDate(summary.end_date)})` : 'today'}
                    </div>
                    <div class="text-xl font-semibold tabular-nums">{units.format('depth', summary.ad)}</div>
                    <div class="text-xs text-ink-muted">
                      of {units.format('depth', summary.ad_max)} · {summary.pct_moisture?.toFixed(1)}% moisture
                    </div>
                  </div>
                  <Sparkline
                    class="max-w-32"
                    values={summary.recent.map((day) => day.ad)}
                    max={summary.ad_max}
                    min={summary.ad_pwp}
                    label="Allowable depletion over the last {summary.recent.length} days"
                  />
                </div>
                <dl class="grid grid-cols-2 gap-2 text-xs">
                  <div>
                    <dt class="text-ink-muted">Last rain</dt>
                    <dd>
                      {#if summary.last_rain}{units.format('depth', summary.last_rain.inches)}, {when(summary, summary.last_rain.date)}{:else}None{/if}
                    </dd>
                  </div>
                  <div>
                    <dt class="text-ink-muted">Last irrigation</dt>
                    <dd>
                      {#if summary.last_irrigation}{units.format('depth', summary.last_irrigation.inches)}, {when(summary, summary.last_irrigation.date)}{:else}None{/if}
                    </dd>
                  </div>
                </dl>
              {/if}
            </Link>
          </li>
        {/each}
      </ul>
    </section>
  {/each}
{/if}
