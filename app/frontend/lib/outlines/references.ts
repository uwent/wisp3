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

/** The 'reference' source and its layers: dashed white outlines, dots and names */
export function addReferenceLayers(map: MapLibreMap, references: Reference[]) {
  map.addSource('reference', { type: 'geojson', data: referenceData(references) as never })
  map.addLayer({
    id: 'reference-line',
    type: 'line',
    source: 'reference',
    filter: ['==', ['geometry-type'], 'Polygon'],
    paint: {
      'line-color': '#ffffff',
      'line-width': ['case', ['get', 'own'], 2.5, 1.5],
      'line-opacity': ['case', ['get', 'own'], 0.95, 0.6],
      'line-dasharray': [2, 2],
    },
  })
  map.addLayer({
    id: 'reference-dot',
    type: 'circle',
    source: 'reference',
    filter: ['==', ['get', 'kind'], 'dot'],
    paint: { 'circle-radius': ['case', ['get', 'own'], 7, 5], 'circle-color': '#ffffff', 'circle-opacity': 0.85 },
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
