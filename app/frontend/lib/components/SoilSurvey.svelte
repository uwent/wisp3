<script lang="ts">
  import { DEFAULT_RADIUS_FT, type LngLat, pivotRing } from '@/lib/geo'
  import { fetchSoilSurvey, type MapUnit, soilKeyFor, type SoilSuggestion, suggestSoil } from '@/lib/soils'
  import type { SoilType } from '@/types/serializers'

  // What the soil survey (SSURGO) says is under a pivot, and the soil type it suggests (PLAN.md
  // Phase 7 F). Looked up when the pivot is placed or moved; it never holds up the form, and a
  // failure just says so.
  let {
    center,
    radiusFt,
    arcStart = null,
    arcEnd = null,
    soilTypes,
    onsuggest,
  }: {
    center: LngLat | null
    radiusFt: number | null
    arcStart?: number | null
    arcEnd?: number | null
    soilTypes: SoilType[]
    /** The suggested soil type (or null for none), each time the survey answers */
    onsuggest?: (soilType: SoilType | null) => void
  } = $props()

  const SHOWN = 3
  const DELAY_MS = 700

  let lookup = $state<'idle' | 'loading' | 'done' | 'error'>('idle')
  let suggestion = $state<SoilSuggestion | null>(null)

  const suggested = $derived(suggestion?.key ? (soilTypes.find((s) => s.key === suggestion!.key) ?? null) : null)
  const pct = (share: number) => `${Math.max(1, Math.round(share * 100))}%`
  const describe = (unit: MapUnit) => {
    const key = soilKeyFor(unit.texture)
    const type = key && soilTypes.find((s) => s.key === key)
    return `${unit.name} (${pct(unit.share)})${type ? ` → ${type.name}` : ''}`
  }

  // Look the pivot up again when it moves or changes size, once it settles
  $effect(() => {
    if (!center) {
      lookup = 'idle'
      suggestion = null
      return
    }
    const ring = pivotRing(center, radiusFt ?? DEFAULT_RADIUS_FT, arcStart, arcEnd, 48)
    const request = new AbortController()
    const timer = setTimeout(() => {
      lookup = 'loading'
      fetchSoilSurvey(ring, request.signal)
        .then((units) => {
          suggestion = suggestSoil(units)
          lookup = 'done'
          const key = suggestion.key
          onsuggest?.(key ? (soilTypes.find((s) => s.key === key) ?? null) : null)
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
      <p class="text-ink-muted">The soil survey isn't answering right now; choose the soil yourself.</p>
    {:else if suggestion && suggestion.units.length === 0}
      <p class="text-ink-muted">The soil survey has no map units here.</p>
    {:else if suggestion}
      <p>
        <span class="font-medium">Soil survey:</span>
        {#if suggested}
          mostly <span class="font-medium">{suggested.name}</span> ({pct(suggestion.share)} of the pivot).
        {:else}
          no single soil type covers most of the pivot.
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
        >). A suggestion: check it against what you know of the field.
      </p>
    {/if}
  </div>
{/if}
