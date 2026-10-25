<script lang="ts">
  import { Link } from '@inertiajs/svelte'

  import Sparkline from '@/lib/components/Sparkline.svelte'
  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import { formatDate, relativeDay } from '@/lib/dates'
  import { outlook } from '@/lib/outlook'
  import type { FieldCard } from '@/lib/overview'
  import type { Units } from '@/lib/units'
  import { fields } from '@/routes'
  import type { PlantingSummary } from '@/types/serializers'

  // A field's status card: on the dashboard (the whole card links to the field), and compact on the
  // map, where pivotName labels it and onselect makes the card select it, with its own link to the
  // field page.
  let {
    card,
    today,
    units,
    compact = false,
    pivotName,
    selected = false,
    onselect,
  }: {
    card: FieldCard
    today: string
    units: Units
    compact?: boolean
    pivotName?: string
    selected?: boolean
    onselect?: () => void
  } = $props()

  const summary = $derived(card.summary)
  const look = $derived(summary && outlook(summary, units))
  const todo = $derived(summary?.tasks.filter((task) => task.due) ?? [])

  // "3 days ago" during the season; a plain date once it's over
  const when = (summary: PlantingSummary, date: string) =>
    summary.phase === 'active' ? relativeDay(date, today) : formatDate(date)

  const frame = $derived(
    `block h-full rounded-lg border bg-surface-raised ${compact ? 'space-y-2 p-3' : 'space-y-3 p-4'}
    ${selected ? 'border-brand-600 ring-2 ring-brand-500' : 'border-line hover:border-brand-500'}`,
  )
</script>

{#snippet content()}
  <div class="flex items-start justify-between gap-2">
    <div class="min-w-0">
      {#if pivotName}<p class="truncate text-xs text-ink-muted">Pivot: {pivotName}</p>{/if}
      <h4 class="truncate font-medium">
        <span class="font-normal text-ink-muted">Field:</span>
        {card.name}
      </h4>
      {#if summary}
        <p class="truncate text-xs text-ink-muted">
          {summary.plant_name}{#if summary.variety}{` (${summary.variety})`}{/if}
        </p>
      {/if}
    </div>
    {#if summary?.phase === 'active'}
      <StatusBadge status={summary.status} size="sm" />
    {:else if summary?.phase === 'ended'}
      <span class="shrink-0 rounded-full border border-line px-2 py-0.5 text-xs text-ink-muted">Season ended</span>
    {/if}
  </div>

  {#if !summary}
    <p class="text-sm text-ink-muted">No crop this season. Add one in Setup.</p>
  {:else if summary.weather_pending}
    <p class="text-sm text-ink-muted">
      Weather for this pivot is on its way. The water balance will appear when it arrives.
    </p>
  {:else if summary.phase === 'upcoming'}
    <p class="text-sm text-ink-muted">The season starts {formatDate(summary.season_start)}.</p>
  {:else}
    <div class="flex items-end justify-between gap-3">
      <div>
        {#if compact}
          <div class="text-sm">
            <span class="text-xs text-ink-muted">AD {summary.phase === 'ended' ? 'at season end' : 'today'}</span>
            <span class="font-semibold tabular-nums">{units.format('depth', summary.ad)}</span>
            <span class="text-xs text-ink-muted">of {units.format('depth', summary.ad_max)}</span>
          </div>
        {:else}
          <div class="text-xs text-ink-muted">
            AD {summary.phase === 'ended' ? `at season end (${formatDate(summary.end_date)})` : 'today'}
          </div>
          <div class="text-xl font-semibold tabular-nums">{units.format('depth', summary.ad)}</div>
          <div class="text-xs text-ink-muted">
            of {units.format('depth', summary.ad_max)} · {summary.pct_moisture?.toFixed(1)}% moisture
          </div>
        {/if}
      </div>
      <Sparkline
        class={compact ? 'max-w-24' : 'max-w-32'}
        values={summary.recent.map((day) => day.ad)}
        projected={summary.phase === 'active' ? summary.projection.map((day) => day.ad) : []}
        max={summary.ad_max}
        min={summary.ad_pwp}
        label="Allowable depletion over the last {summary.recent.length} days{summary.phase === 'active' &&
        summary.projection.length
          ? `, and the ${summary.projection.length} days ahead`
          : ''}"
      />
    </div>
    {#if look}
      <p class="text-sm {look.urgent ? 'font-medium text-status-irrigate-ink' : ''}">{look.headline}</p>
    {/if}
    {#if !compact}
      <dl class="grid grid-cols-2 gap-2 text-xs">
        <div>
          <dt class="text-ink-muted">Last rain</dt>
          <dd>
            {#if summary.last_rain}{units.format('depth', summary.last_rain.inches)}, {when(
                summary,
                summary.last_rain.date,
              )}{:else}None{/if}
          </dd>
        </div>
        <div>
          <dt class="text-ink-muted">Last irrigation</dt>
          <dd>
            {#if summary.last_irrigation}{units.format('depth', summary.last_irrigation.inches)}, {when(
                summary,
                summary.last_irrigation.date,
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

{#if onselect}
  <!-- The whole card selects; the field's own link sits above the select button -->
  <div class="relative {frame}" data-field-card={card.id}>
    <button
      type="button"
      class="absolute inset-0 rounded-lg focus-visible:outline-2 focus-visible:outline-brand-500"
      aria-label="Show {card.name}{pivotName ? ` (${pivotName})` : ''} on the map"
      aria-pressed={selected}
      onclick={onselect}
    ></button>
    <div class="pointer-events-none relative space-y-2">
      {@render content()}
    </div>
    <Link
      href={fields.show(card.id)}
      class="relative mt-2 inline-block text-xs font-medium text-brand-600 hover:underline"
      aria-label="Open field: {card.name}">Open field →</Link
    >
  </div>
{:else}
  <Link href={fields.show(card.id)} class={frame}>
    {@render content()}
  </Link>
{/if}
