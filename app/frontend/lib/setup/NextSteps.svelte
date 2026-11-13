<script lang="ts">
  import { Link } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import { systemName } from '@/lib/geo'
  import { root, newOutlineImport, pivots as pivotRoutes, setup } from '@/routes'
  import type { Farm, Field, Pivot } from '@/types/serializers'

  // Quick setup's next steps on Setup (PLAN.md G.6), for what it just made: an irrigation system for a
  // farm saved alone; fields for a system without them; then a planting on each field this season.
  // Worked out from Setup's own data, so each step done moves it on.
  let {
    started,
    farms,
    year,
    onaddfield,
    onaddplanting,
  }: {
    started: { farm_id: number; pivot_id: number | null }
    farms: Farm[]
    year: number
    onaddfield: (pivot: Pivot) => void
    onaddplanting: (field: Field) => void
  } = $props()

  const farm = $derived(farms.find((f) => f.id === started.farm_id))
  const pivot = $derived(started.pivot_id === null ? undefined : farm?.pivots.find((p) => p.id === started.pivot_id))
  const unplanted = $derived(
    (pivot?.fields ?? []).filter((field) => !field.plantings.some((planting) => planting.year === year)),
  )
  // A farm saved alone that has since got a system needs nothing more from this box
  const shown = $derived(farm && (pivot || farm.pivots.length === 0))
  const link = 'text-brand-600 underline underline-offset-2'
</script>

{#if farm && shown}
  <section
    class="space-y-3 rounded-lg border border-brand-500 bg-surface-raised p-4 sm:p-6"
    aria-labelledby="next-steps"
  >
    <div class="flex flex-wrap items-start justify-between gap-2">
      <h2 id="next-steps" class="text-lg font-medium">
        {#if pivot && pivot.fields.length && !unplanted.length}Set up{:else}Next steps{/if}
      </h2>
      <Link href={setup.show({ query: { year } })} class="text-sm {link}">Hide</Link>
    </div>

    {#if !pivot}
      <p class="text-sm">
        Add an irrigation system to {farm.name}: WISP gets weather from its location, and its fields hang off it.
      </p>
      <Link
        href={pivotRoutes.new({ query: { farm_id: farm.id } })}
        class="inline-block rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 dark:text-surface"
        >Add an irrigation system</Link
      >
    {:else if pivot.fields.length === 0}
      <p class="text-sm">
        Add the fields {systemName(pivot)} waters. Type each one in, or import their shapes from a shapefile, KML or GeoJSON
        file to make them from those.
      </p>
      <div class="flex flex-wrap gap-2">
        <Button onclick={() => onaddfield(pivot)}>Add a field</Button>
        <Link
          href={newOutlineImport()}
          class="rounded-md border border-line bg-surface-raised px-4 py-2 text-sm font-medium hover:bg-surface"
          >Import field shapes</Link
        >
      </div>
    {:else if unplanted.length}
      <p class="text-sm">
        Add what's planted on each field in {year}: the crop, and when it emerged. A field can have more than one
        planting in a season, one after another or on parts of the field; start with the main one.
      </p>
      <ul class="divide-y divide-line rounded-md border border-line">
        {#each unplanted as field (field.id)}
          <li class="flex flex-wrap items-center justify-between gap-2 px-3 py-2">
            <span><span class="text-ink-muted">Field:</span> <span class="font-medium">{field.name}</span></span>
            <Button variant="secondary" aria-label="Add a planting to {field.name}" onclick={() => onaddplanting(field)}
              >Add a planting</Button
            >
          </li>
        {/each}
      </ul>
    {:else}
      <p class="text-sm">
        {systemName(pivot)} and its fields are set up, and WISP is tracking each planting's soil water.
        <Link href={root()} class={link}>See them on the dashboard</Link>, or draw each field's shape from its page when
        you're ready.
      </p>
    {/if}
  </section>
{/if}
