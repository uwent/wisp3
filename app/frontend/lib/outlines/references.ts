import type { Map as MapLibreMap } from 'maplibre-gl'

import { type Boundary, boundaryBounds, boundaryCenter, type LngLat, type PivotShape, pivotOutline } from '@/lib/geo'
import { LABEL_FONT } from '@/lib/map/basemaps'

// What the outline pages draw for reference (PLAN.md Phase 8 G.10): irrigation systems (an outline,
// or a point kind's dot) and fields' outlines, each named, the first one ("own") more strongly

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
  return boundaryBounds({ type: 'Polygon', coordinates: [ring] })
}

/** The references as GeoJSON: outlines, dots and label points */
export function referenceData(references: Reference[]) {
  const features = references.flatMap((reference, index) => {
    const own = index === 0
    if (reference.boundary) {
      return [
        { type: 'Feature' as const, properties: { name: '', own, kind: 'field' }, geometry: reference.boundary },
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
            properties: { name: '', own, kind: 'system' },
            geometry: { type: 'Polygon' as const, coordinates: [ring] },
          }
        : {
            type: 'Feature' as const,
            properties: { name: '', own, kind: 'dot' },
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

// The map's system color and its casing (--color-map-system, --color-map-system-casing)
export const SYSTEM = '#2ec4f0'
export const SYSTEM_CASING = '#0c2d48'
const isSystem = ['==', ['get', 'kind'], 'system']

/** The first of the reference layers, to draw others (soil types) under */
export const FIRST_REFERENCE_LAYER = 'reference-casing'

/**
 * The 'reference' source and its layers: systems in the system color on a dark casing (as on the
 * overview map), the field's own one wider; other fields' outlines faint white; and names
 */
export function addReferenceLayers(map: MapLibreMap, references: Reference[]) {
  map.addSource('reference', { type: 'geojson', data: referenceData(references) as never })
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
      'line-color': ['case', isSystem, SYSTEM, '#ffffff'] as never,
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
    paint: { 'text-color': '#ffffff', 'text-halo-color': '#000000', 'text-halo-width': 1 },
  })
}
