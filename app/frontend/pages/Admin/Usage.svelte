<script lang="ts">
  import { router } from '@inertiajs/svelte'

  import AdminTabs from '@/lib/components/AdminTabs.svelte'
  import Chart from '@/lib/charts/Chart.svelte'
  import {
    type EntryKind,
    funnelShares,
    percent,
    weeklyActiveOption,
    weeklyEntriesOption,
  } from '@/lib/charts/usageCharts'
  import { today } from '@/lib/dates'
  import { adminUsage } from '@/routes'

  type Count = { name: string; count: number }
  let {
    year,
    years,
    tiles,
    funnel,
    weeks,
    weekly_active,
    previous_weekly_active,
    weekly_entries,
    areas,
    phone_share,
    setup,
    return_rate,
  }: {
    year: number
    years: number[]
    tiles: {
      accounts: number
      new_accounts: number
      active_week: number
      active_month: number
      operations_entering: number
    }
    funnel: { key: string; count: number }[]
    weeks: string[]
    weekly_active: number[]
    previous_weekly_active: number[] | null
    weekly_entries: Record<EntryKind, number[]>
    areas: { season_active: number; month_active: number; counts: { area: string; season: number; month: number }[] }
    phone_share: number | null
    setup: {
      operations: number
      shared_operations: number
      farms: number
      systems: Count[]
      fields: number
      outlined_fields: number
      plantings: number
      plots: number
      crops: Count[]
      units: Record<string, number>
      digests: Record<string, number>
    }
    return_rate: { previous_year: number; active: number; returned: number } | null
  } = $props()

  const currentYear = Number(today().slice(0, 4))
  const isCurrent = $derived(year === currentYear)

  const FUNNEL: Record<string, { label: string; hint: string }> = {
    signed_up: { label: 'Signed up', hint: 'Accounts created this season' },
    confirmed: { label: 'Confirmed their email', hint: 'Can sign in' },
    farm: { label: 'Set up a farm', hint: 'In an operation with a farm' },
    planting: { label: 'Added a planting', hint: 'In an operation with a planting this season' },
    entry: { label: 'Entered data', hint: 'In an operation with an entry made this season' },
    regular: { label: 'Used WISP on 10+ days', hint: 'Active on at least 10 days this season' },
  }

  const AREAS: Record<string, string> = {
    dashboard: 'Dashboard',
    daily: 'Daily entry',
    field: 'Field pages',
    planting: 'Planting pages',
    system: 'Irrigation system pages',
    map: 'Map',
    weather: 'Weather',
    setup: 'Setup',
    alerts: 'Alerts',
    reports: 'CSV downloads',
    operation: 'Operation and members',
    settings: 'Settings',
    about: 'About',
  }

  const UNITS: Record<string, string> = { imperial: 'US (inches)', metric: 'Metric (mm)' }
  const DIGESTS: Record<string, string> = {
    never: 'Never',
    daily: 'Daily during season',
    daily_all_year: 'Daily all year',
    needed: 'Only when irrigation is needed',
  }

  const shares = $derived(funnelShares(funnel.map((step) => step.count)))
  const funnelMax = $derived(Math.max(1, funnel[0]?.count ?? 0))
  const anyActivity = $derived(weekly_active.some((n) => n > 0))
  const anyEntries = $derived(Object.values(weekly_entries).some((series) => series.some((n) => n > 0)))
  // In season, the last 30 days; for an earlier season, the season as a whole
  const areaKey = $derived(isCurrent ? 'month' : 'season') as 'month' | 'season'
  const areaTotal = $derived(isCurrent ? areas.month_active : areas.season_active)
  const areaRows = $derived(
    areas.counts
      .map((row) => ({ ...row, count: row[areaKey] }))
      .sort((a, b) => b.count - a.count || a.area.localeCompare(b.area)),
  )

  const entryTotal = $derived(
    Object.values(weekly_entries).reduce((sum, series) => sum + series.reduce((a, b) => a + b, 0), 0),
  )

  function choose(y: number) {
    router.get(adminUsage.show().url, y === currentYear ? {} : { year: y })
  }

  const counts = (record: Record<string, number>, names: Record<string, string>) =>
    Object.entries(record)
      .map(([key, count]) => ({ name: names[key] ?? key, count }))
      .sort((a, b) => b.count - a.count)

  const number = (n: number) => n.toLocaleString('en-US')
</script>

<svelte:head><title>Usage · WISP</title></svelte:head>

<AdminTabs />

<div class="space-y-6">
  <div class="flex flex-wrap items-end justify-between gap-3">
    <div>
      <h1 class="text-2xl font-semibold">Usage</h1>
      <p class="max-w-prose text-sm text-ink-muted">
        How growers use WISP. Admins and the demo and example farms are left out. Activity is the days each account used
        WISP and which parts, recorded from November 2026.
      </p>
    </div>
    <select
      class="rounded-md text-sm"
      aria-label="Season"
      value={year}
      onchange={(e) => choose(Number(e.currentTarget.value))}
    >
      {#each years as y (y)}<option value={y}>{y}</option>{/each}
    </select>
  </div>

  <!-- Headline numbers -->
  <dl class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
    {#each [{ label: 'Accounts', value: tiles.accounts, note: 'Confirmed' }, { label: `New in ${year}`, value: tiles.new_accounts, note: 'Signed up' }, { label: 'Active this week', value: tiles.active_week, note: 'Last 7 days' }, { label: 'Active this month', value: tiles.active_month, note: 'Last 30 days' }, { label: 'Operations entering data', value: tiles.operations_entering, note: `In ${year}` }] as tile (tile.label)}
      <div class="rounded-lg border border-line bg-surface-raised p-4">
        <dt class="text-sm text-ink-muted">{tile.label}</dt>
        <dd class="mt-1 text-3xl font-semibold tabular-nums">{number(tile.value)}</dd>
        <dd class="text-xs text-ink-muted">{tile.note}</dd>
      </div>
    {/each}
  </dl>

  <div class="grid gap-6 lg:grid-cols-2">
    <!-- Onboarding funnel -->
    <section class="space-y-3 rounded-lg border border-line bg-surface-raised p-4" aria-labelledby="funnel-heading">
      <div>
        <h2 id="funnel-heading" class="font-medium">Getting started</h2>
        <p class="text-sm text-ink-muted">
          Accounts that signed up in {year}, and how far each got. The percentage is of the step before.
        </p>
      </div>
      {#if funnel[0]?.count}
        <ol class="space-y-2.5">
          {#each funnel as step, i (step.key)}
            <li>
              <div class="flex items-baseline justify-between gap-3 text-sm">
                <span title={FUNNEL[step.key]?.hint}>{FUNNEL[step.key]?.label ?? step.key}</span>
                <span class="tabular-nums"
                  ><b class="font-semibold">{number(step.count)}</b>
                  {#if i > 0}<span class="ml-1 inline-block w-10 text-right text-ink-muted">{percent(shares[i])}</span
                    >{/if}</span
                >
              </div>
              <div class="mt-1 h-2 rounded-full bg-line/50" aria-hidden="true">
                <div class="h-2 rounded-full bg-brand-600" style:width="{(step.count / funnelMax) * 100}%"></div>
              </div>
            </li>
          {/each}
        </ol>
      {:else}
        <p class="text-sm text-ink-muted">No accounts signed up in {year}.</p>
      {/if}
    </section>

    <!-- Parts of WISP used -->
    <section class="space-y-3 rounded-lg border border-line bg-surface-raised p-4" aria-labelledby="areas-heading">
      <div>
        <h2 id="areas-heading" class="font-medium">Parts of WISP used</h2>
        <p class="text-sm text-ink-muted">
          {#if isCurrent}
            Of the {number(areaTotal)} accounts active in the last 30 days, how many used each part.
          {:else}
            Of the {number(areaTotal)} accounts active in {year}, how many used each part.
          {/if}
          {#if phone_share !== null}{` ${percent(phone_share)} of active days in ${year} included a phone.`}{/if}
        </p>
      </div>
      {#if areaTotal}
        <ul class="space-y-1.5">
          {#each areaRows as row (row.area)}
            {@const share = row.count / areaTotal}
            <li class="grid grid-cols-[10rem_1fr_4.5rem] items-center gap-3 text-sm">
              <span class="truncate">{AREAS[row.area] ?? row.area}</span>
              <div class="h-2 rounded-full bg-line/50" aria-hidden="true">
                <div class="h-2 rounded-full bg-brand-600" style:width="{share * 100}%"></div>
              </div>
              <span class="text-right tabular-nums"
                >{number(row.count)} <span class="inline-block w-9 text-ink-muted">{percent(share)}</span></span
              >
            </li>
          {/each}
        </ul>
      {:else}
        <p class="text-sm text-ink-muted">No activity recorded {isCurrent ? 'in the last 30 days' : `in ${year}`}.</p>
      {/if}
    </section>
  </div>

  <!-- Weekly charts -->
  <section class="space-y-2 rounded-lg border border-line bg-surface-raised p-4" aria-labelledby="active-heading">
    <h2 id="active-heading" class="font-medium">Accounts active each week</h2>
    <p class="text-sm text-ink-muted">
      Accounts that used WISP in each week from March to November{previous_weekly_active
        ? `, with ${year - 1} for comparison`
        : ''}.
      {#if return_rate}
        {` ${number(return_rate.returned)} of the ${number(return_rate.active)} accounts active in ${return_rate.previous_year} came back in ${year} (${percent(return_rate.active ? return_rate.returned / return_rate.active : null)}).`}
      {/if}
    </p>
    {#if anyActivity || previous_weekly_active}
      <Chart
        height="16rem"
        label="Accounts active each week of {year}"
        build={(palette) => weeklyActiveOption(palette, weeks, weekly_active, previous_weekly_active, year)}
      />
    {:else}
      <p class="py-6 text-center text-sm text-ink-muted">No activity recorded in {year}.</p>
    {/if}
  </section>

  <section class="space-y-2 rounded-lg border border-line bg-surface-raised p-4" aria-labelledby="entries-heading">
    <h2 id="entries-heading" class="font-medium">Entries each week</h2>
    <p class="text-sm text-ink-muted">
      {number(entryTotal)} entries made in {year}, by the week they were made (not the day they're for). Irrigation
      includes system, field and planting entries; a day with rain and irrigation counts once for each.
    </p>
    {#if anyEntries}
      <Chart
        height="16rem"
        label="Entries made each week of {year}, by kind"
        build={(palette) => weeklyEntriesOption(palette, weeks, weekly_entries)}
      />
    {:else}
      <p class="py-6 text-center text-sm text-ink-muted">No entries made in {year}.</p>
    {/if}
  </section>

  <!-- How operations are set up -->
  <section class="space-y-3 rounded-lg border border-line bg-surface-raised p-4" aria-labelledby="setup-heading">
    <div>
      <h2 id="setup-heading" class="font-medium">How operations are set up</h2>
      <p class="text-sm text-ink-muted">As they are now; plantings and crops are {year}'s.</p>
    </div>
    <dl class="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-4">
      {#each [['Operations', setup.operations, `${number(setup.shared_operations)} with more than one member`], ['Farms', setup.farms, null], ['Fields', setup.fields, `${number(setup.outlined_fields)} outlined`], [`Plantings in ${year}`, setup.plantings, `${number(setup.plots)} on part of a field`]] as [label, value, note] (label)}
        <div>
          <dt class="text-ink-muted">{label}</dt>
          <dd class="text-xl font-semibold tabular-nums">{number(value as number)}</dd>
          {#if note}<dd class="text-xs text-ink-muted">{note}</dd>{/if}
        </div>
      {/each}
    </dl>
    <div class="grid items-start gap-6 pt-2 sm:grid-cols-2 lg:grid-cols-4">
      {#each [{ title: 'Irrigation systems', rows: setup.systems }, { title: `Crops in ${year}`, rows: setup.crops }, { title: 'Units', rows: counts(setup.units, UNITS) }, { title: 'Daily email', rows: counts(setup.digests, DIGESTS) }] as table (table.title)}
        <table class="w-full text-sm">
          <caption class="pb-1 text-left font-medium">{table.title}</caption>
          <tbody>
            {#each table.rows as row (row.name)}
              <tr class="border-t border-line">
                <th scope="row" class="py-1 text-left font-normal">{row.name}</th>
                <td class="py-1 text-right tabular-nums">{number(row.count)}</td>
              </tr>
            {:else}
              <tr class="border-t border-line"><td class="py-1 text-ink-muted" colspan="2">None</td></tr>
            {/each}
          </tbody>
        </table>
      {/each}
    </div>
  </section>
</div>
