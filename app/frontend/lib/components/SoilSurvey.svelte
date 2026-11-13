<script lang="ts">
  import { type Boundary, isPoint, KIND_NOUNS, type PivotShape, surveyRing } from '@/lib/geo'
  import { fetchSoilSurvey, type MapUnit, soilKeyFor, soilShares, type SoilSuggestion, suggestSoil } from '@/lib/soils'
  import type { SoilType } from '@/types/serializers'

  // What the soil survey (SSURGO) says is under an irrigation system (its outline, or a small circle
  // around a point kind's location) or a field's outline (G.10), and the soil type it suggests
  // (PLAN.md Phase 7 F). Looked up when the area is placed or changes; it never holds up the form,
  // and a failure just says so.
  let {
    shape = null,
    boundary = null,
    soilTypes,
    onsuggest,
    onuse,
  }: {
    /** The pivot, or null until it's placed */
    shape?: PivotShape | null
    /** A field's outline, read in place of a pivot */
    boundary?: Boundary | null
    soilTypes: SoilType[]
    /** The suggested soil type (or null for none) and each soil type's share of the area, each time
     * the survey answers */
    onsuggest?: (soilType: SoilType | null, shares: Map<string, number>) => void
    /** With it, a button to use the suggested soil */
    onuse?: (soilType: SoilType) => void
  } = $props()

  const SHOWN = 3
  const DELAY_MS = 700

  let lookup = $state<'idle' | 'loading' | 'done' | 'error'>('idle')
  let suggestion = $state<SoilSuggestion | null>(null)

  // "of the pivot", "around this spot"
  const where = $derived(
    boundary
      ? 'of the field'
      : !shape || !isPoint(shape.kind)
        ? `of the ${KIND_NOUNS[shape?.kind ?? 'center']}`
        : 'around this spot',
  )
  const suggested = $derived(suggestion?.key ? (soilTypes.find((s) => s.key === suggestion!.key) ?? null) : null)
  const pct = (share: number) => `${Math.max(1, Math.round(share * 100))}%`
  const describe = (unit: MapUnit) => {
    const key = soilKeyFor(unit.texture)
    const type = key && soilTypes.find((s) => s.key === key)
    return `${unit.name} (${pct(unit.share)})${type ? `, counted as ${type.name}` : ''}`
  }

  // Look the pivot up again when it moves or changes size, once it settles
  $effect(() => {
    if (!boundary && !shape) {
      lookup = 'idle'
      suggestion = null
      return
    }
    const area = boundary ?? surveyRing(shape!)
    const request = new AbortController()
    const timer = setTimeout(() => {
      lookup = 'loading'
      fetchSoilSurvey(area, request.signal)
        .then((units) => {
          suggestion = suggestSoil(units)
          lookup = 'done'
          const key = suggestion.key
          onsuggest?.(key ? (soilTypes.find((s) => s.key === key) ?? null) : null, soilShares(units))
        })
        .catch((error: Error) => {
          if (error.name !== 'AbortError') lookup = 'error'
        })
    }, DELAY_MS)
    return () => {
      clearTimeout(timer)
      request.abort()
    }
  })
</script>

{#if lookup !== 'idle'}
  <div class="rounded-md border border-line bg-surface px-3 py-2 text-sm" aria-live="polite">
    {#if lookup === 'loading'}
      <p class="text-ink-muted">Checking the soil survey…</p>
    {:else if lookup === 'error'}
      <p class="text-ink-muted">The soil survey can't be reached right now. Please choose the soil yourself.</p>
    {:else if suggestion && suggestion.units.length === 0}
      <p class="text-ink-muted">
        The soil survey has no soil information for this spot. Please choose the soil yourself.
      </p>
    {:else if suggestion}
      <p>
        <span class="font-medium">Soil survey:</span>
        {#if suggested}
          mostly <span class="font-medium">{suggested.name}</span> ({pct(suggestion.share)}
          {where}).
          {#if onuse}
            <button
              type="button"
              class="ml-1 text-brand-600 underline underline-offset-2"
              onclick={() => onuse(suggested!)}>Use {suggested.name}</button
            >
          {/if}
        {:else}
          no single soil type covers most {where}.
        {/if}
      </p>
      <ul class="mt-1 list-disc pl-5 text-xs text-ink-muted">
        {#each suggestion.units.slice(0, SHOWN) as unit (unit.mukey)}<li>{describe(unit)}</li>{/each}
        {#if suggestion.units.length > SHOWN}<li>and {suggestion.units.length - SHOWN} more</li>{/if}
      </ul>
      <p class="mt-1 text-xs text-ink-muted">
        From the surface layer of each map unit's main soil (<a
          href="https://websoilsurvey.nrcs.usda.gov/"
          target="_blank"
          rel="noopener"
          class="text-brand-600 hover:underline">USDA Web Soil Survey</a
        >). Treat this as a starting point, and check it against what you know of the field.
      </p>
    {/if}
  </div>
{/if}
