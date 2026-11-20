<script lang="ts" module>
  // A crop's percent cover curve, from db/reference/canopy_curves.yml (PagesController#canopy_curves)
  export type CanopyCurve = {
    key: string
    name: string
    basis: string
    confidence: string
    confidence_label: string
    notes: string | null
    growth: { cc0: number; ccx: number; cgc: number }
    decline:
      | { type: 'aquacrop'; start_day: number; cdc: number }
      | { type: 'rule'; date: string; days: number; floor: number }
      | null
    days_to: { 50: number | null; 80: number | null }
    /** The curve in growing degree days (°C days), which plantings run on (PLAN.md §9 C23) */
    thermal: {
      base_c: number
      upper_c: number
      cgc: number
      decline_start: number | null
      cdc: number | null
      basis: string
    } | null
    /** Typical days from emergence to harvest (PLAN.md Phase 8 G.2) */
    season: { days: number; basis: string } | null
    covers: number[]
    sources: { citation: string; url: string }[]
  }
</script>

<script lang="ts">
  import Dialog from '@/lib/components/Dialog.svelte'

  import CanopyCurvePlot from './CanopyCurvePlot.svelte'

  // A crop's card in the About page's canopy curves: its curve and when it reaches 50% and 80% cover,
  // and at its foot "Details and sources", opening a dialog with the whole card, its parameters,
  // notes, season and sources (Ben, 2026-11-19: as the weather charts' "Summary and data", so the grid
  // of cards keeps its shape)
  let { curve }: { curve: CanopyCurve } = $props()

  let open = $state(false)

  const pct = (fraction: number) => `${+(fraction * 100).toFixed(2)}%`

  function declineText(decline: CanopyCurve['decline']): string {
    if (!decline) return "Holds its maximum cover until the planting's end date."
    if (decline.type === 'aquacrop') {
      return `Declines from day ${decline.start_day} after emergence in a typical season, following AquaCrop's equation (CDC ${decline.cdc} a day).`
    }
    const [month, day] = decline.date.split('-').map(Number)
    const date = new Date(2000, month - 1, day).toLocaleDateString('en-US', { month: 'long', day: 'numeric' })
    return (
      `Starting ${date} (or once the canopy is full, if that comes later), cover eases down to ${decline.floor}% ` +
      `over ${decline.days} days, fastest at the halfway point, then holds until the end date.`
    )
  }

  const label = $derived(
    `${curve.name} canopy cover by day since emergence` +
      (curve.days_to[50] !== null ? `: 50% on day ${curve.days_to[50]}` : '') +
      (curve.days_to[80] !== null ? `, 80% on day ${curve.days_to[80]}` : ''),
  )
  const degreeDaysPerDay = $derived(curve.thermal ? curve.growth.cgc / curve.thermal.cgc : null)
</script>

{#snippet takeaway()}
  <p>
    {#if curve.days_to[50] !== null}50% cover on day {curve.days_to[50]}{/if}{#if curve.days_to[80] !== null}, 80% on
      day {curve.days_to[80]}{/if}. {declineText(curve.decline)}
  </p>
{/snippet}

<section
  id="canopy-{curve.key}"
  aria-labelledby="canopy-{curve.key}-name"
  class="flex scroll-mt-6 flex-col gap-2 rounded-lg border border-line bg-surface-raised p-3 text-sm"
>
  <div class="flex flex-wrap items-baseline justify-between gap-x-2">
    <h3 id="canopy-{curve.key}-name" class="font-display font-semibold">{curve.name}</h3>
    <span class="text-xs text-ink-muted">{curve.confidence_label}</span>
  </div>
  <CanopyCurvePlot covers={curve.covers} {degreeDaysPerDay} {label} />
  {@render takeaway()}
  <button
    type="button"
    class="mt-auto self-end text-xs text-ink-muted hover:text-ink hover:underline"
    aria-haspopup="dialog"
    aria-label="{curve.name}: details and sources"
    onclick={() => (open = true)}>Details and sources</button
  >
</section>

<Dialog bind:open title="{curve.name} canopy curve" description={curve.confidence_label} wide>
  <div class="space-y-3 text-sm">
    <div class="mx-auto max-w-md"><CanopyCurvePlot covers={curve.covers} {degreeDaysPerDay} {label} /></div>
    {@render takeaway()}
    <p>
      {curve.basis}. Starting cover (CC₀) {pct(curve.growth.cc0)}, maximum cover (CCx) {pct(curve.growth.ccx)}, growth
      rate (CGC) {curve.growth.cgc} a day.
    </p>
    {#if curve.thermal}
      <p>
        In growing degree days: base {curve.thermal.base_c} °C, upper {curve.thermal.upper_c} °C, growth rate {curve
          .thermal.cgc} a degree day{curve.thermal.decline_start
          ? `, decline from ${curve.thermal.decline_start} degree days (CDC ${curve.thermal.cdc} a degree day)`
          : ''}. {curve.thermal.basis}.
      </p>
    {/if}
    {#if curve.notes}<p>{curve.notes}</p>{/if}
    {#if curve.season}
      <p>Typical season: {curve.season.days} days from emergence to harvest ({curve.season.basis}).</p>
    {/if}
    <h4 class="font-medium">Sources</h4>
    <ul class="list-disc space-y-1 pl-4 text-ink-muted">
      {#each curve.sources as source (source.url)}
        <li>
          {source.citation}
          <a href={source.url} target="_blank" rel="noopener" class="break-all text-brand-600 underline">{source.url}</a
          >
        </li>
      {/each}
    </ul>
  </div>
</Dialog>
