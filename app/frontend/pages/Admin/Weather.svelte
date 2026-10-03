<script lang="ts">
  import { Form } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import { adminWeather } from '@/routes'
  import type { WeatherCellStatus } from '@/types/serializers'

  type Period = 'minute' | 'hour' | 'day'
  let {
    api,
    cells,
  }: {
    api: {
      mode: 'free' | 'customer'
      model: string
      soil_model: string
      usage: Record<Period, number>
      limits: Record<Period, number> | null
    }
    cells: WeatherCellStatus[]
  } = $props()

  const periods: Period[] = ['minute', 'hour', 'day']

  function ago(iso: string | null) {
    if (!iso) return '—'
    const minutes = Math.round((Date.now() - new Date(iso).getTime()) / 60000)
    if (minutes < 60) return `${minutes} min ago`
    if (minutes < 48 * 60) return `${Math.round(minutes / 60)} h ago`
    return `${Math.round(minutes / 1440)} days ago`
  }

  function health(cell: WeatherCellStatus): ['ok' | 'caution' | 'irrigate', string] {
    if (cell.last_error) return ['irrigate', 'Error']
    if (!cell.active) return ['ok', 'Inactive']
    if (cell.missing_days) return ['caution', `${cell.missing_days} days missing`]
    if (!cell.forecast_issued_at) return ['caution', 'No forecast']
    return ['ok', 'OK']
  }

  const badge = {
    ok: 'bg-status-ok text-white',
    caution: 'bg-status-caution text-ink',
    irrigate: 'bg-status-irrigate text-white',
  }
</script>

<svelte:head><title>Weather status · WISP</title></svelte:head>

<div class="flex flex-wrap items-end justify-between gap-3">
  <div>
    <h1 class="text-2xl font-semibold">Weather status</h1>
    <p class="text-sm text-ink-muted">
      Open-Meteo, {api.mode === 'customer' ? 'commercial API key' : 'free API (no key)'} · model {api.model}, soil from
      {api.soil_model}
    </p>
  </div>
  <Form action={adminWeather.refresh()}>
    {#snippet children({ processing })}
      <Button type="submit" variant="secondary" disabled={processing}>Refresh now</Button>
    {/snippet}
  </Form>
</div>

<section class="grid grid-cols-3 gap-3" aria-label="API usage">
  {#each periods as period (period)}
    <div class="rounded-lg border border-line bg-surface-raised p-3">
      <div class="text-xs text-ink-muted">Calls this {period}</div>
      <div class="text-lg font-semibold">
        {api.usage[period]}
        {#if api.limits}<span class="text-sm font-normal text-ink-muted">of {api.limits[period]}</span>{/if}
      </div>
    </div>
  {/each}
</section>

<section class="overflow-x-auto rounded-lg border border-line bg-surface-raised">
  {#if cells.length === 0}
    <p class="p-6 text-center text-sm text-ink-muted">No weather cells yet. Cells are created when pivots are.</p>
  {:else}
    <table class="w-full text-left text-sm">
      <thead class="border-b border-line text-xs text-ink-muted">
        <tr>
          <th class="px-3 py-2 font-medium">Cell</th>
          <th class="px-3 py-2 font-medium">Status</th>
          <th class="px-3 py-2 font-medium">Pivots</th>
          <th class="px-3 py-2 font-medium">Season data</th>
          <th class="px-3 py-2 font-medium">Forecast</th>
          <th class="px-3 py-2 font-medium">Last fetch</th>
        </tr>
      </thead>
      <tbody>
        {#each cells as cell (cell.id)}
          {@const [tone, label] = health(cell)}
          <tr class="border-b border-line last:border-0 align-top">
            <td class="px-3 py-2 whitespace-nowrap">
              <div class="font-mono text-xs">{cell.latitude.toFixed(4)}, {cell.longitude.toFixed(4)}</div>
              <div class="text-xs text-ink-muted">
                {cell.timezone ?? 'timezone not yet known'}{cell.elevation_m != null ? ` · ${cell.elevation_m} m` : ''}
              </div>
            </td>
            <td class="px-3 py-2">
              <span class="rounded-full px-2 py-0.5 text-xs whitespace-nowrap {badge[tone]}">{label}</span>
              {#if cell.last_error}
                <div class="mt-1 max-w-xs text-xs text-status-irrigate">{cell.last_error} ({ago(cell.last_error_at)})</div>
              {/if}
            </td>
            <td class="px-3 py-2">{cell.pivot_count}</td>
            <td class="px-3 py-2 whitespace-nowrap">
              <div>{cell.days_stored} days this year, through {cell.latest_date ?? '—'}</div>
              <div class="text-xs text-ink-muted">
                {cell.season_start ? `season from ${cell.season_start}` : 'no current planting'} · {cell.provisional_days}
                provisional
              </div>
            </td>
            <td class="px-3 py-2 whitespace-nowrap">
              <div>{ago(cell.forecast_issued_at)}</div>
              <div class="text-xs text-ink-muted">{cell.forecast_through ? `through ${cell.forecast_through}` : ''}</div>
            </td>
            <td class="px-3 py-2 whitespace-nowrap">{ago(cell.last_fetched_at)}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  {/if}
</section>
