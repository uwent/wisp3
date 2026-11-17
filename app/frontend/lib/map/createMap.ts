import type { Map as MapLibreMap, MapOptions } from 'maplibre-gl'

import { GEOCODER_ATTRIBUTION } from '@/lib/geocode'

import { type Basemap, basemapStyle, transformStyle } from './basemaps'
import { loadMapLibre } from './maplibre'

type MapLibre = Awaited<ReturnType<typeof loadMapLibre>>

/** Wisconsin's Central Sands, where most WISP fields are */
export const DEFAULT_VIEW = { center: [-89.5, 44.25] as [number, number], zoom: 8 }

/**
 * Every map's start: MapLibre loaded on demand, a map in container on the basemap (the street style
 * repaired, transformStyle) at DEFAULT_VIEW, zoom buttons at the top right, and the compact
 * attribution with the place search's credit. options add to or replace those (a view, gestures).
 * onready gets the map as soon as it's made, before its style loads, with MapLibre's classes.
 * Returns the cleanup for onMount, which removes the map whether or not it was made yet.
 */
export function createMap(
  container: HTMLElement,
  basemap: Basemap,
  onready: (map: MapLibreMap, maplibre: MapLibre) => void,
  options: Partial<MapOptions> = {},
): () => void {
  let map: MapLibreMap | undefined
  let removed = false
  loadMapLibre().then((maplibre) => {
    if (removed) return
    map = new maplibre.Map({
      container,
      style: basemapStyle(basemap),
      transformStyle,
      ...DEFAULT_VIEW,
      attributionControl: { compact: true, customAttribution: GEOCODER_ATTRIBUTION },
      ...options,
    })
    map.addControl(new maplibre.NavigationControl({ showCompass: false }), 'top-right')
    onready(map, maplibre)
  })
  return () => {
    removed = true
    map?.remove()
  }
}
