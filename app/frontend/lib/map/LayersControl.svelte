<script lang="ts">
  import type { Units } from '@/lib/units'

  import type { MapOverlays } from './mapOverlays.svelte'
  import OverlayLegend from './OverlayLegend.svelte'
  import { DROUGHT_OVERLAY, type Overlay, type OverlayId, RAIN_OVERLAYS } from './overlays'
  import type { MapPrefs } from './prefs'

  // The map's Layers button and panel: one rain layer at a time (radar, recent rain, forecast
  // rain) and the Drought Monitor, each with its legend, time, opacity and source
  let { prefs, overlays, units }: { prefs: MapPrefs; overlays: MapOverlays; units: Units } = $props()

  let open = $state(false)
  let button: HTMLButtonElement | undefined = $state()
  const shownCount = $derived((prefs.rain ? 1 : 0) + prefs.overlays.length)
  const rain = $derived(RAIN_OVERLAYS.find((overlay) => overlay.id === prefs.rain) ?? null)

  function toggle(id: OverlayId, on: boolean) {
    prefs.overlays = on ? [...prefs.overlays, id] : prefs.overlays.filter((shown) => shown !== id)
  }

  const STATUS_TEXT = { loading: 'Loading…', ready: '', unavailable: 'Unavailable' }
</script>

{#snippet details(overlay: Overlay)}
  {@const status = overlays.status[overlay.id]}
  <div class="mt-2 space-y-2 border-l-2 border-line pl-3">
    {#if status === 'unavailable'}
      <p class="text-xs text-status-irrigate-ink">
        Not loading right now. Switch it off and on to try again, or try later.
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

<div class="relative">
  <button
    type="button"
    class="flex items-center gap-1.5 rounded-md border border-line bg-surface-raised px-2.5 py-1.5 text-xs shadow
      hover:bg-surface {open ? 'ring-2 ring-brand-500' : ''}"
    bind:this={button}
    aria-expanded={open}
    aria-controls="map-layers"
    onclick={() => (open = !open)}
  >
    <svg
      viewBox="0 0 24 24"
      class="size-4"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linejoin="round"
      aria-hidden="true"><path d="m12 3 9 5-9 5-9-5 9-5Z" /><path d="m3 13 9 5 9-5" /></svg
    >
    Layers{#if shownCount}<span class="rounded-full bg-brand-600 px-1.5 text-white dark:text-surface">{shownCount}</span
      >{/if}
  </button>

  {#if open}
    <!-- svelte-ignore a11y_no_noninteractive_element_interactions (Escape from any control inside) -->
    <div
      id="map-layers"
      class="absolute top-full left-0 z-20 mt-1 max-h-[min(70vh,32rem)] w-72 space-y-4 overflow-y-auto rounded-md border
        border-line bg-surface-raised p-3 text-sm shadow-lg"
      role="group"
      aria-label="Map layers"
      onkeydown={(event) => {
        // A panel that follows its button in the tab order; Escape closes it and goes back there
        if (event.key !== 'Escape') return
        event.stopPropagation()
        open = false
        button?.focus()
      }}
    >
      <div class="flex items-center justify-between">
        <h2 class="font-medium">Map layers</h2>
        <button
          type="button"
          class="rounded px-1.5 text-lg leading-none text-ink-muted hover:text-ink"
          aria-label="Close map layers"
          onclick={() => {
            open = false
            button?.focus()
          }}>×</button
        >
      </div>

      <fieldset class="space-y-1">
        <legend class="mb-1 text-xs font-medium tracking-wide text-ink-muted uppercase">Rain</legend>
        <label class="flex items-center gap-2">
          <input type="radio" name="map-rain" checked={prefs.rain === null} onchange={() => (prefs.rain = null)} />
          None
        </label>
        {#each RAIN_OVERLAYS as overlay (overlay.id)}
          <label class="flex items-center gap-2">
            <input
              type="radio"
              name="map-rain"
              checked={prefs.rain === overlay.id}
              onchange={() => (prefs.rain = overlay.id)}
            />
            {overlay.name}
            {@render mark(overlay.id)}
          </label>
        {/each}
        {#if rain}{@render details(rain)}{/if}
      </fieldset>

      {#each [DROUGHT_OVERLAY] as overlay (overlay.id)}
        {@const on = prefs.overlays.includes(overlay.id)}
        <div>
          <label class="flex items-center gap-2">
            <input type="checkbox" checked={on} onchange={(event) => toggle(overlay.id, event.currentTarget.checked)} />
            {overlay.name}
            {@render mark(overlay.id)}
          </label>
          {#if on}{@render details(overlay)}{/if}
        </div>
      {/each}

      <p class="text-xs text-ink-muted">
        Point at the map, or tap it, to see the layers' values there. They come straight from public services, not from
        WISP, and can be slow or unavailable at times.
      </p>
    </div>
  {/if}
</div>
