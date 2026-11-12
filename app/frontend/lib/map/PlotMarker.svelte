<script lang="ts">
  import StatusBadge from '@/lib/components/StatusBadge.svelte'

  import { packRows, type PlotPack } from './pivots'

  // A field's pinned plots on the map while their pins would sit on top of each other (G.14): a
  // badge per plot in its status (a gray dot when it has none), packed in rows like a system's
  // marker, under the field's name. Shown only while the map sets data-plots; closer in, the pins
  // at their own places take over.
  let {
    pack,
    selected,
    dimmed,
    onselect,
  }: { pack: PlotPack; selected: boolean; dimmed: boolean; onselect: () => void } = $props()

  const rows = $derived(packRows(pack.plots))
  const label = $derived(`Plots on ${pack.field_name}: ${pack.plots.map((plot) => plot.label).join('; ')}`)
</script>

<button
  type="button"
  class="hidden cursor-pointer flex-col items-center gap-0.5 {rows.length > 1
    ? 'rounded-xl'
    : 'rounded-full'} bg-black/50 p-0.5 transition-opacity
    group-data-plots/map:flex {dimmed ? 'opacity-35' : ''} {selected ? 'ring-2 ring-white' : ''}"
  aria-label={label}
  aria-pressed={selected}
  onclick={(event) => {
    event.stopPropagation()
    onselect()
  }}
>
  {#each rows as row, index (index)}
    <span class="flex gap-0.5">
      {#each row as plot (plot.planting_id)}
        {#if plot.status}
          <StatusBadge status={plot.status} size="icon" title={plot.label} />
        {:else}
          <span class="inline-flex size-5 rounded-full border-2 border-white/80 bg-gray-400/70" title={plot.label}
          ></span>
        {/if}
      {/each}
    </span>
  {/each}
</button>
