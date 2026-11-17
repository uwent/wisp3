import type { Map as MapLibreMap } from 'maplibre-gl'

// Roads and place names over the satellite imagery: on unless switched off, remembered in this
// browser for every map (storage can be blocked, so it's guarded)

const KEY = 'wisp-map-roads'
/** The road layers' ids (IMAGERY_ROADS in basemaps.ts) */
export const ROAD_LAYER_PREFIX = 'imagery-'

function load(): boolean {
  try {
    return localStorage.getItem(KEY) !== 'off'
  } catch {
    return true
  }
}

export const roads = $state({ on: load() })

export function setRoads(on: boolean) {
  roads.on = on
  try {
    localStorage.setItem(KEY, on ? 'on' : 'off')
  } catch {
    // Not remembered; this page still follows it
  }
}

/** Shows or hides the road layers on a map (on the imagery; the street map has its own) */
export function showRoads(map: MapLibreMap, on = roads.on) {
  for (const { id } of map.getStyle().layers) {
    if (id.startsWith(ROAD_LAYER_PREFIX)) map.setLayoutProperty(id, 'visibility', on ? 'visible' : 'none')
  }
}

/** Keeps a map's road layers following the setting; call during component setup */
export function followRoads(map: () => MapLibreMap | null | undefined) {
  $effect(() => {
    const on = roads.on
    const m = map()
    if (m?.isStyleLoaded()) showRoads(m, on)
  })
}
