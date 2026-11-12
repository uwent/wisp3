import {
  type Boundary,
  boundaryBounds,
  boundaryCenter,
  groupOutline,
  type LngLat,
  pivotOutline,
  type PivotShape,
} from '@/lib/geo'
import { type FarmGroup, primary, type PivotGroup, pivotStatus, type Status, summaryActive } from '@/lib/overview'
import { cropName } from '@/lib/plantings'

// The map page's irrigation systems (MapController): the dashboard's pivot with its location and
// its weather zone's rain and ET, drawn as GeoJSON. Pivots and linears are their outline; the other
// kinds (a traveler, drip, a location) are a point. Each irrigation group is a light outline around
// its systems. Fields with an outline are drawn in their status (G.10), and plots with a pin as dots.

export type WeatherTotals = { days: number; precip: number | null; et0: number | null }
export type PivotWeather = { past: WeatherTotals | null; ahead: WeatherTotals | null }

/** A field's outline (G.10) */
export type MapOutline = { field_id: number; boundary: Boundary }
/** A plot with a pin, in this season (G.10) */
export type MapPin = { planting_id: number; field_id: number; latitude: number; longitude: number }

export type MapPivot = PivotGroup &
  PivotShape & { weather: PivotWeather | null; outlines: MapOutline[]; pins: MapPin[] }

export type PivotProperties = {
  id: number
  name: string
  /** The most urgent status among its fields in season, or none */
  status: Status | 'none'
  selected: boolean
  /** Outside the "needs water within" window */
  dimmed: boolean
  /** Some of its fields have outlines, which carry the status: the system is drawn as a line only */
  outlined: boolean
}

export type FieldProperties = {
  /** The field's id */
  id: number
  pivot_id: number
  name: string
  /** Its most urgent planting's status in season, or none */
  status: Status | 'none'
  selected: boolean
  dimmed: boolean
  /** An outline, or the point its name is drawn at */
  kind: 'outline' | 'label'
}

export type PinProperties = {
  planting_id: number
  field_id: number
  pivot_id: number
  /** "Soybean" */
  name: string
  status: Status | 'none'
  selected: boolean
  dimmed: boolean
}

type Geometry = { type: 'Polygon'; coordinates: LngLat[][] } | { type: 'Point'; coordinates: LngLat }
export type MapFeature<P> = { type: 'Feature'; id: number; properties: P; geometry: Geometry }
export type FeatureCollection<P> = { type: 'FeatureCollection'; features: MapFeature<P>[] }

/** Where a system is on the map: its outline, or a point kind's location */
export function geometry(pivot: PivotShape): Geometry {
  const ring = pivotOutline(pivot)
  return ring
    ? { type: 'Polygon', coordinates: [ring] }
    : { type: 'Point', coordinates: [pivot.longitude, pivot.latitude] }
}

/** highlighted: the pivots in the "needs water within" window, or null when there's no window */
export function pivotFeatures(
  pivots: MapPivot[],
  selectedId: number | null,
  highlighted: Set<number> | null,
): FeatureCollection<PivotProperties> {
  return {
    type: 'FeatureCollection',
    features: pivots.map((pivot) => ({
      type: 'Feature',
      id: pivot.id,
      properties: {
        id: pivot.id,
        name: pivot.name,
        status: pivotStatus(pivot.fields) ?? 'none',
        selected: pivot.id === selectedId,
        dimmed: highlighted !== null && !highlighted.has(pivot.id),
        outlined: pivot.outlines.length > 0,
      },
      geometry: geometry(pivot),
    })),
  }
}

/** The fields with outlines, in their status, each with a point inside for its name */
export function fieldFeatures(
  pivots: MapPivot[],
  selectedFieldId: number | null,
  highlighted: Set<number> | null,
): FeatureCollection<FieldProperties> {
  return {
    type: 'FeatureCollection',
    features: pivots.flatMap((pivot) =>
      pivot.outlines.flatMap(({ field_id, boundary }) => {
        const card = pivot.fields.find((field) => field.id === field_id)
        const summary = card ? primary(card) : null
        const properties = {
          id: field_id,
          pivot_id: pivot.id,
          name: card?.name ?? '',
          status: summaryActive(summary) ? summary!.status! : ('none' as const),
          selected: field_id === selectedFieldId,
          dimmed: highlighted !== null && !highlighted.has(pivot.id),
        }
        return [
          {
            type: 'Feature' as const,
            id: field_id,
            properties: { ...properties, kind: 'outline' as const },
            geometry: boundary,
          },
          {
            type: 'Feature' as const,
            id: field_id,
            properties: { ...properties, kind: 'label' as const },
            geometry: { type: 'Point' as const, coordinates: boundaryCenter(boundary) },
          },
        ]
      }),
    ),
  }
}

/** The plots with a pin, in their planting's status, named for their crop */
export function pinFeatures(
  pivots: MapPivot[],
  selectedFieldId: number | null,
  highlighted: Set<number> | null,
): FeatureCollection<PinProperties> {
  return {
    type: 'FeatureCollection',
    features: pivots.flatMap((pivot) =>
      pivot.pins.map((pin) => {
        const summary = pivot.fields.flatMap((card) => card.plantings).find((p) => p.planting_id === pin.planting_id)
        return {
          type: 'Feature' as const,
          id: pin.planting_id,
          properties: {
            planting_id: pin.planting_id,
            field_id: pin.field_id,
            pivot_id: pivot.id,
            name: summary ? cropName(summary) : '',
            status: summary && summaryActive(summary) ? summary.status! : ('none' as const),
            selected: pin.field_id === selectedFieldId,
            dimmed: highlighted !== null && !highlighted.has(pivot.id),
          },
          geometry: { type: 'Point' as const, coordinates: [pin.longitude, pin.latitude] as LngLat },
        }
      }),
    ),
  }
}

/** Whether every one of the system's fields has an outline (its marker then has nothing to show) */
export const allOutlined = (pivot: MapPivot) =>
  pivot.fields.length > 0 && pivot.fields.every((card) => pivot.outlines.some((o) => o.field_id === card.id))

/** The irrigation groups among these pivots, each outlined around its systems shown */
export function groupFeatures(farms: FarmGroup<MapPivot>[], pivots: MapPivot[]): FeatureCollection<{ name: string }> {
  const shown = new Set(pivots.map((pivot) => pivot.id))
  return {
    type: 'FeatureCollection',
    features: farms.flatMap((farm) =>
      farm.pivot_groups.flatMap((group) => {
        const members = farm.pivots.filter((pivot) => pivot.pivot_group_id === group.id && shown.has(pivot.id))
        if (!members.length) return []
        return [
          {
            type: 'Feature' as const,
            id: group.id,
            properties: { name: group.name },
            geometry: { type: 'Polygon' as const, coordinates: [groupOutline(members)] },
          },
        ]
      }),
    ),
  }
}

/** [[west, south], [east, north]] around the pivots' whole outlines (or points), or null without pivots */
export function pivotBounds(pivots: MapPivot[]): [LngLat, LngLat] | null {
  const points = pivots.flatMap((pivot) => [
    ...(pivotOutline(pivot) ?? [[pivot.longitude, pivot.latitude] as LngLat]),
    ...pivot.outlines.flatMap(({ boundary }) => boundaryBounds(boundary)),
  ])
  if (!points.length) return null
  const lngs = points.map(([lng]) => lng)
  const lats = points.map(([, lat]) => lat)
  return [
    [Math.min(...lngs), Math.min(...lats)],
    [Math.max(...lngs), Math.max(...lats)],
  ]
}
