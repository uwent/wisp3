import type { Map as MapLibreMap } from 'maplibre-gl'

import { boundsOf, type LngLat, type PivotShape, pivotOutline } from '@/lib/geo'
import { type Boundary, boundaryBounds, boundaryCenter } from '@/lib/boundary'
import { readPalette } from '@/lib/charts/palette'
import { LABEL_FONT, labelPaint } from '@/lib/map/basemaps'

// What the outline pages draw for reference: irrigation systems (an outline,
// or a point kind's dot) and fields' outlines, each named, the first one ("own") more strongly
// unless ownFirst is false

export type Reference = { name: string; boundary?: Boundary | null; shape?: PivotShape }

/** [[west, south], [east, north]] around a reference (a small box around a point kind) */
export function referenceBounds(reference: Reference): [LngLat, LngLat] | null {
  if (reference.boundary) return boundaryBounds(reference.boundary)
  if (!reference.shape) return null
  const ring = pivotOutline(reference.shape)
  if (!ring) {
    const { longitude: lng, latitude: lat } = reference.shape
    return [
      [lng - 0.004, lat - 0.003],
      [lng + 0.004, lat + 0.003],
    ]
  }
  return boundsOf(ring)
}

/** The references as GeoJSON: outlines, dots and label points */
export function referenceData(references: Reference[], { ownFirst = true } = {}) {
  const features = references.flatMap((reference, index) => {
    const own = ownFirst && index === 0
    // hoverName: the name on every part, for a hover label
    const hoverName = reference.name
    if (reference.boundary) {
      return [
        {
          type: 'Feature' as const,
          properties: { name: '', hoverName, own, kind: 'field' },
          geometry: reference.boundary,
        },
        {
          type: 'Feature' as const,
          properties: { name: reference.name, own, kind: 'label' },
          geometry: { type: 'Point' as const, coordinates: boundaryCenter(reference.boundary) },
        },
      ]
    }
    const shape = reference.shape!
    const ring = pivotOutline(shape)
    const at: LngLat = [shape.longitude, shape.latitude]
    return [
      ring
        ? {
            type: 'Feature' as const,
            properties: { name: '', hoverName, own, kind: 'system' },
            geometry: { type: 'Polygon' as const, coordinates: [ring] },
          }
        : {
            type: 'Feature' as const,
            properties: { name: '', hoverName, own, kind: 'dot' },
            geometry: { type: 'Point' as const, coordinates: at },
          },
      {
        type: 'Feature' as const,
        properties: { name: reference.name, own, kind: 'label' },
        geometry: { type: 'Point' as const, coordinates: at },
      },
    ]
  })
  return { type: 'FeatureCollection' as const, features }
}

const isSystem = ['==', ['get', 'kind'], 'system']

/** The first of the reference layers, to draw others (soil types) under */
export const FIRST_REFERENCE_LAYER = 'reference-hit'

/** The hover label's line for each system under a point: "System: Home pivot" */
export const SYSTEM_HOVER_LAYERS = ['reference-dot', 'reference-hit']

/**
 * The 'reference' source and its layers: systems in the system color on a dark casing (as on the
 * overview map), the field's own one wider; other fields' outlines faint, in the map's field color; and names
 */
export function addReferenceLayers(map: MapLibreMap, references: Reference[], options: { ownFirst?: boolean } = {}) {
  // The map's system color and its casing (--color-map-system, --color-map-system-casing)
  const { system: SYSTEM, systemCasing: SYSTEM_CASING, field: FIELD } = readPalette()
  map.addSource('reference', { type: 'geojson', data: referenceData(references, options) as never })
  // The systems' outlines, unseen, so a hover label can name one from anywhere inside it
  map.addLayer({
    id: 'reference-hit',
    type: 'fill',
    source: 'reference',
    filter: isSystem as never,
    paint: { 'fill-opacity': 0 },
  })
  map.addLayer({
    id: 'reference-casing',
    type: 'line',
    source: 'reference',
    filter: isSystem as never,
    paint: {
      'line-color': SYSTEM_CASING,
      'line-width': ['case', ['get', 'own'], 5, 3.5],
      'line-opacity': ['case', ['get', 'own'], 0.9, 0.6],
    },
  })
  map.addLayer({
    id: 'reference-line',
    type: 'line',
    source: 'reference',
    filter: ['==', ['geometry-type'], 'Polygon'],
    paint: {
      'line-color': ['case', isSystem, SYSTEM, FIELD] as never,
      'line-width': ['case', isSystem, ['case', ['get', 'own'], 2.5, 1.5], 1.2] as never,
      'line-opacity': ['case', ['get', 'own'], 1, isSystem, 0.7, 0.55] as never,
    },
  })
  map.addLayer({
    id: 'reference-dot',
    type: 'circle',
    source: 'reference',
    filter: ['==', ['get', 'kind'], 'dot'],
    paint: {
      'circle-radius': ['case', ['get', 'own'], 7, 5],
      'circle-color': SYSTEM,
      'circle-stroke-color': SYSTEM_CASING,
      'circle-stroke-width': 1.5,
      'circle-opacity': ['case', ['get', 'own'], 1, 0.7],
    },
  })
  map.addLayer({
    id: 'reference-label',
    type: 'symbol',
    source: 'reference',
    filter: ['==', ['get', 'kind'], 'label'],
    layout: {
      'text-field': ['get', 'name'],
      'text-size': 12,
      'text-font': LABEL_FONT,
      'text-variable-anchor': ['top', 'center'],
      'text-radial-offset': 0.9,
    },
    paint: labelPaint(),
  })
}
