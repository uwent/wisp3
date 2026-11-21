<script lang="ts">
  import { Link } from '@inertiajs/svelte'

  import Spinner from '@/lib/components/Spinner.svelte'
  import StatusBadge from '@/lib/components/StatusBadge.svelte'
  import { formatDate } from '@/lib/dates'
  import { outlook } from '@/lib/outlook'
  import type { FieldCard } from '@/lib/overview'
  import type { WeatherUpdate } from '@/lib/poll'
  import { cardWhen, cropName } from '@/lib/plantings'
  import type { Units } from '@/lib/units'
  import { fields, planting as plantingRoute } from '@/routes'
  import type { PlantingSummary } from '@/types/serializers'

  // A field in the dashboard's list (Phase 9): its name, crop, status and the outlook's headline,
  // with readings due as "2 due"; the row links as its card does (FieldCard). A field of plots is
  // its name, linking to the field, over a row per planting linking to its own page. context: its
  // system (and farm) when the list isn't under them ("Needs water first").
  let {
    card,
    today,
    units,
    weather = null,
    context,
  }: {
    card: FieldCard
    today: string
    units: Units
    weather?: WeatherUpdate
    context?: string
  } = $props()

  const several = $derived(card.plantings.length > 1)
  const single = $derived(card.plantings[0] ?? null)

  const row = 'flex min-h-11 items-center gap-3 px-3 py-2 hover:bg-surface'
</script>

<!-- One planting's crop, when, and where it stands; its badge and readings due on the right -->
{#snippet planting(summary: PlantingSummary | null, name: string | null)}
  {@const look = summary ? outlook(summary, units) : null}
  {@const due = summary?.phase === 'active' ? summary.tasks.filter((task) => task.due) : []}
  <span class="min-w-0 flex-1">
    {#if name}<span class="block truncate font-medium">{name}</span>{/if}
    {#if name && context}<span class="block truncate text-xs text-ink-muted">{context}</span>{/if}
    {#if summary}
      <span class="block truncate text-xs {name ? 'text-ink-muted' : 'text-sm'}"
        >{cropName(summary)}<span class="text-ink-muted">{` · ${cardWhen(summary, today)}`}</span></span
      >
    {/if}
    {#if !summary}
      <span class="block text-xs text-ink-muted">No crop this season</span>
    {:else if summary.weather_pending && weather === 'failed'}
      <span class="block text-xs text-status-caution-ink">Weather update failed. Refresh the page to try again.</span>
    {:else if summary.weather_pending}
      <span class="flex items-center gap-1.5 text-xs text-ink-muted"
        >{#if weather === 'updating'}<Spinner />{/if}Weather on its way</span
      >
    {:else if summary.phase === 'upcoming'}
      <span class="block text-xs text-ink-muted">Season starts {formatDate(summary.season_start)}</span>
    {:else if look}
      <span class="block text-sm {look.urgent ? 'font-medium text-status-irrigate-ink' : ''}">{look.headline}</span>
    {/if}
  </span>
  <span class="flex shrink-0 flex-col items-end gap-1">
    {#if summary?.phase === 'active'}
      <StatusBadge status={summary.status} size="sm" />
    {:else if summary?.phase === 'ended'}
      <span class="rounded-full border border-line px-2 py-0.5 text-xs whitespace-nowrap text-ink-muted"
        >Season ended</span
      >
    {/if}
    {#if due.length}
      <span
        class="relative text-xs whitespace-nowrap text-status-caution-ink"
        title={due.map((task) => task.todo).join('\n')}
        >{due.length}<span class="sr-only">{due.length === 1 ? ' reading or check' : ' readings or checks'}</span
        >{' due'}</span
      >
    {/if}
  </span>
{/snippet}

{#if several}
  <div data-field-row={card.id}>
    <Link href={fields.show(card.id)} class="{row} pb-1">
      <span class="min-w-0 flex-1">
        <span class="block truncate font-medium">{card.name}</span>
        {#if context}<span class="block truncate text-xs text-ink-muted">{context}</span>{/if}
      </span>
      <span class="shrink-0 text-xs text-ink-muted">{card.plantings.length} plantings</span>
    </Link>
    <ul aria-label="Plantings on {card.name}">
      {#each card.plantings as summary (summary.planting_id)}
        <li>
          <Link href={plantingRoute(summary.planting_id)} class="{row} pl-6">{@render planting(summary, null)}</Link>
        </li>
      {/each}
    </ul>
  </div>
{:else}
  <Link href={single ? plantingRoute(single.planting_id) : fields.show(card.id)} class={row} data-field-row={card.id}
    >{@render planting(single, card.name)}</Link
  >
{/if}
