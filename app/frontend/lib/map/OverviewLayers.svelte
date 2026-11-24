<script lang="ts">
  import { page } from '@inertiajs/svelte'

  import KindIcon from '@/lib/components/KindIcon.svelte'
  import { formatDate } from '@/lib/dates'
  import { KIND_NAMES, type SystemKind } from '@/lib/geo'
  import type { Units } from '@/lib/units'

  import type { MapOverlays } from './mapOverlays.svelte'
  import OverlayLegend from './OverlayLegend.svelte'
  import { type Overlay, type OverlayId, OVERLAYS } from './overlays'
  import type { MapPrefs } from './prefs'

  // The Map tab's own layers, in its Layers panel (MapLayersButton) above the basemap's: one data
  // overlay at a time (radar, recent rain, forecast rain or the Drought Monitor), the one shown with
  // its legend, time, opacity and source; then the irrigation systems' shapes and the weather zones
  let { prefs = $bindable(), overlays, units }: { prefs: MapPrefs; overlays: MapOverlays; units: Units } = $props()

  // The example farm is seen as of its day, but the overlays are today's
  const example = $derived(page.props.example)
  const exampleDay = $derived(example && formatDate(example.as_of, { year: true }))
  const shown = $derived(OVERLAYS.find((overlay) => overlay.id === prefs.overlay) ?? null)

  const STATUS_TEXT = { loading: 'Loading…', ready: '', unavailable: 'Unavailable' }
</script>

{#snippet details(overlay: Overlay)}
  {@const status = overlays.status[overlay.id]}
  <div class="mt-2 space-y-2 border-l-2 border-line pl-3">
    {#if status === 'unavailable'}
      <p class="text-xs text-status-irrigate-ink">
        This layer isn't loading right now. Switch it off and on to try again, or check back later.
      </p>
    {/if}
    {#if overlays.times[overlay.id]}<p class="text-xs font-medium">{overlays.times[overlay.id]}</p>{/if}
    <OverlayLegend legend={overlay.legend} {units} />
    <p class="text-xs text-ink-muted">{overlay.description}</p>
    <label class="flex items-center gap-2 text-xs">
      <span class="text-ink-muted">Opacity</span>
      <input
        type="range"
        min="0.1"
        max="1"
        step="0.05"
        class="flex-1"
        value={prefs.opacity[overlay.id] ?? overlay.opacity}
        oninput={(event) => (prefs.opacity = { ...prefs.opacity, [overlay.id]: Number(event.currentTarget.value) })}
      />
    </label>
    <p class="text-xs">
      Source: <a href={overlay.credit.url} target="_blank" rel="noopener" class="text-brand-600 hover:underline"
        >{overlay.credit.name}</a
      >
    </p>
  </div>
{/snippet}

{#snippet mark(id: OverlayId)}
  {@const status = overlays.status[id]}
  {#if status && STATUS_TEXT[status]}
    <span class="ml-auto text-xs {status === 'unavailable' ? 'text-status-irrigate-ink' : 'text-ink-muted'}"
      >{STATUS_TEXT[status]}</span
    >
  {/if}
{/snippet}

<fieldset class="space-y-1">
  <legend class="mb-1 text-xs font-medium tracking-wide text-ink-muted uppercase">Data overlays</legend>
  <p class="mb-1.5 text-xs text-ink-muted">
    Point at the map, or tap it, to see the overlay's value there. Overlays come straight from public services, not from
    WISP, and can be slow or unavailable at times.{#if example}{` Note: You're viewing the example farm as of ${exampleDay}, but these overlays will show current conditions.`}{/if}
  </p>
  <label class="flex items-center gap-2">
    <input type="radio" name="map-overlay" checked={prefs.overlay === null} onchange={() => (prefs.overlay = null)} />
    None
  </label>
  {#each OVERLAYS as overlay (overlay.id)}
    <label class="flex items-center gap-2">
      <input
        type="radio"
        name="map-overlay"
        checked={prefs.overlay === overlay.id}
        onchange={() => (prefs.overlay = overlay.id)}
      />
      {overlay.name}
      {@render mark(overlay.id)}
    </label>
  {/each}
  {#if shown}{@render details(shown)}{/if}
</fieldset>

<fieldset class="space-y-3">
  <legend class="mb-1 text-xs font-medium tracking-wide text-ink-muted uppercase">Markers and shapes</legend>
  <div>
    <label class="flex items-center gap-2">
      <input type="checkbox" bind:checked={prefs.systems} />
      Irrigation systems
    </label>
    <p class="mt-1 text-xs text-ink-muted">
      Pivots and linears at their size, the others by their kind's mark. Fields with a shape are drawn in white, with
      their plantings' status badges at the center.
    </p>
    <ul class="mt-1 grid grid-cols-2 gap-x-3 gap-y-0.5 text-xs" aria-label="Irrigation system kinds">
      {#each Object.entries(KIND_NAMES) as [kind, name] (kind)}
        <li class="flex items-center gap-1.5"><KindIcon kind={kind as SystemKind} />{name}</li>
      {/each}
    </ul>
  </div>

  <div>
    <label class="flex items-center gap-2">
      <input type="checkbox" bind:checked={prefs.zones} />
      Weather zones
    </label>
    <p class="mt-1 text-xs text-ink-muted">
      The weather grid cells your irrigation systems are in, about 9 km across, each with its own weather. Point at one
      to see its last week and the week ahead, or select it for its forecast.
    </p>
  </div>
</fieldset>
