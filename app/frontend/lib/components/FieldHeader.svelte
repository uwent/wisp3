<script lang="ts">
  import { Link, router } from '@inertiajs/svelte'
  import { systemName } from '@/lib/geo'
  import type { Snippet } from 'svelte'

  import { isoDate } from '@/lib/dates'
  import { plantingWhen } from '@/lib/plantings'
  import { formatNumber, type Units } from '@/lib/units'
  import { fieldOutline, fields, planting as plantingRoute, pivots } from '@/routes'
  import type { Field } from '@/types/serializers'

  // The top of the field page and its plantings' pages (PLAN.md Phase 8 G.11): where the field is,
  // its area and soil, and tabs for the field and each planting of the season shown. Other seasons
  // are a year select, which opens the field page for that year. current: 'field', or the id of the
  // planting whose page this is. actions: buttons at the right of the title row.
  let {
    field,
    pivot,
    farm,
    units,
    year,
    current,
    actions,
  }: {
    field: Field
    pivot: { id: number; name: string; kind_name: string }
    farm: { id: number; name: string }
    units: Units
    year: number
    current: 'field' | number
    actions?: Snippet
  } = $props()

  const seasonPlantings = $derived(
    field.plantings
      .filter((p) => p.year === year)
      .toSorted((a, b) => Number(a.partial) - Number(b.partial) || a.season_start.localeCompare(b.season_start)),
  )
  const years = $derived([...new Set([...field.plantings.map((p) => p.year), year])].sort((a, b) => b - a))
  // A tab's second line: when the planting is, as plantings are named (G.14)
  const today = isoDate(new Date())
  const detail = (p: Field['plantings'][number]) => plantingWhen(p, today)
  const tab = (active: boolean) =>
    `flex shrink-0 flex-col rounded-t-md border-b-2 px-3 py-1.5 text-sm leading-tight ${
      active
        ? 'border-brand-600 font-medium text-ink'
        : 'border-transparent text-ink-muted hover:border-line hover:text-ink'
    }`
</script>

<div class="space-y-3">
  <div class="flex flex-wrap items-end justify-between gap-3">
    <div class="min-w-0">
      <nav aria-label="Breadcrumb" class="text-sm text-ink-muted">
        {farm.name} ›
        <Link href={pivots.show(pivot.id)} class="underline underline-offset-2">{systemName(pivot)}</Link>
      </nav>
      <h1 class="text-2xl font-semibold">{field.name}</h1>
      <p class="text-sm text-ink-muted">
        {units.format('area', field.area_acres)} · {field.soil_type_name} (field capacity {formatNumber(
          field.effective_field_capacity * 100,
          1,
        )}%, wilting point {formatNumber(field.effective_perm_wilting_pt * 100, 1)}%){' · '}<Link
          href={fieldOutline(field.id)}
          class="underline underline-offset-2">{field.boundary ? 'Outline' : 'Add an outline'}</Link
        >
      </p>
    </div>
    {#if actions}
      <div class="ml-auto flex flex-wrap items-center justify-end gap-2 text-sm">{@render actions()}</div>
    {/if}
  </div>

  <div class="flex items-end gap-2 border-b border-line">
    <nav aria-label="Field and plantings" class="-mb-px flex min-w-0 flex-1 overflow-x-auto">
      <Link
        href={fields.show(field.id, { query: year === new Date().getFullYear() ? {} : { year } })}
        class={tab(current === 'field')}
        aria-current={current === 'field' ? 'page' : undefined}
      >
        Field<span class="text-xs font-normal text-ink-muted">{year}</span>
      </Link>
      {#each seasonPlantings as p (p.id)}
        {@const more = detail(p)}
        <Link
          href={plantingRoute(p.id)}
          class={tab(current === p.id)}
          aria-current={current === p.id ? 'page' : undefined}
        >
          {p.plant_name}{#if more}<span class="text-xs font-normal text-ink-muted">{more}</span>{/if}
        </Link>
      {/each}
    </nav>
    {#if years.length > 1}
      <label for="field-season" class="sr-only">Season</label>
      <select
        id="field-season"
        class="mb-1 rounded-md py-1 text-sm"
        value={year}
        onchange={(e) => router.get(fields.show(field.id, { query: { year: e.currentTarget.value } }).url)}
      >
        {#each years as y (y)}<option value={y}>{y}</option>{/each}
      </select>
    {/if}
  </div>
</div>
