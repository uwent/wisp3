import type { GeoJSONSource, Map as MapLibreMap } from 'maplibre-gl'

import type { LngLat } from '@/lib/geo'
import type { MapZone } from '@/types/serializers'

import { showLayers } from './maplibre'

// The weather zones of the operation's systems on the Map tab (MapController): each its weather
// grid cell's box (Weather::Grid), drawn as the boxes' edges, each edge once, so where two zones
// meet the line is no darker than elsewhere, and the selected zone's box more strongly. Only these
// cells are kept current, so no others are drawn.

/** The zones' line layer; the public overlays go under it */
export const ZONE_LAYER = 'zones-line'
const SELECTED_LAYER = 'zone-selected'
/** The zones' sources (each named as its layer is), carried over when the basemap changes */
export const ZONE_SOURCES = [ZONE_LAYER, SELECTED_LAYER]

/** How the zones' lines look: Okabe–Ito's sky blue, the selected zone's wider and stronger */
export const ZONE_STYLE = {
  color: '#56b4e9',
  width: { line: 1, selected: 2.5 },
  opacity: { line: 0.6, selected: 0.9 },
}

const selectedEdges = (selected: MapZone | null) => zoneEdges(selected ? [selected] : [])

/** Adds the zones' layers, shown or not */
export function addZoneLayers(map: MapLibreMap, zones: MapZone[], selected: MapZone | null, visible: boolean) {
  const layout = { visibility: visible ? ('visible' as const) : ('none' as const) }
  const line = (id: string, kind: 'line' | 'selected') =>
    map.addLayer({
      id,
      type: 'line',
      source: id,
      layout,
      paint: {
        'line-color': ZONE_STYLE.color,
        'line-width': ZONE_STYLE.width[kind],
        'line-opacity': ZONE_STYLE.opacity[kind],
      },
    })
  map.addSource(ZONE_LAYER, { type: 'geojson', data: zoneEdges(zones) })
  line(ZONE_LAYER, 'line')
  map.addSource(SELECTED_LAYER, { type: 'geojson', data: selectedEdges(selected) })
  line(SELECTED_LAYER, 'selected')
}

/** Redraws the zones and the selected one */
export function setZones(map: MapLibreMap | undefined, zones: MapZone[], selected: MapZone | null) {
  map?.getSource<GeoJSONSource>(ZONE_LAYER)?.setData(zoneEdges(zones))
  map?.getSource<GeoJSONSource>(SELECTED_LAYER)?.setData(selectedEdges(selected))
}

export const showZones = (map: MapLibreMap | undefined, visible: boolean) => showLayers(map, ZONE_SOURCES, visible)

type Segment = { at: number; from: number; to: number }

/** Overlapping or touching intervals along one line merged */
function merge(segments: Segment[]): Segment[] {
  const sorted = [...segments].sort((a, b) => a.from - b.from)
  const merged: Segment[] = []
  for (const segment of sorted) {
    const last = merged.at(-1)
    if (last && segment.from <= last.to + 1e-9) last.to = Math.max(last.to, segment.to)
    else merged.push({ ...segment })
  }
  return merged
}

/** Segments grouped by the latitude or longitude they lie on */
function byLine(segments: Segment[]): Segment[][] {
  const lines = new Map<string, Segment[]>()
  for (const segment of segments) {
    const key = segment.at.toFixed(7)
    lines.set(key, [...(lines.get(key) ?? []), segment])
  }
  return [...lines.values()]
}

/** The zones' edges as GeoJSON lines: east–west along the rings' edges, north–south between cells */
export function zoneEdges(zones: Pick<MapZone, 'bounds'>[]) {
  const across = zones.flatMap(({ bounds: b }) => [
    { at: b.north, from: b.west, to: b.east },
    { at: b.south, from: b.west, to: b.east },
  ])
  const down = zones.flatMap(({ bounds: b }) => [
    { at: b.west, from: b.south, to: b.north },
    { at: b.east, from: b.south, to: b.north },
  ])
  const line = (coordinates: LngLat[]) => ({
    type: 'Feature' as const,
    properties: {},
    geometry: { type: 'LineString' as const, coordinates },
  })
  return {
    type: 'FeatureCollection' as const,
    features: [
      ...byLine(across)
        .flatMap(merge)
        .map(({ at, from, to }) =>
          line([
            [from, at],
            [to, at],
          ]),
        ),
      ...byLine(down)
        .flatMap(merge)
        .map(({ at, from, to }) =>
          line([
            [at, from],
            [at, to],
          ]),
        ),
    ],
  }
}

/** The zone a point is in, or null */
export function zoneAt<Z extends Pick<MapZone, 'bounds'>>(zones: Z[], [lng, lat]: LngLat): Z | null {
  return zones.find(({ bounds: b }) => lat <= b.north && lat > b.south && lng >= b.west && lng < b.east) ?? null
}
