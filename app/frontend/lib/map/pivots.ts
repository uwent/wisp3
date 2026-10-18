import { DEFAULT_RADIUS_FT, pivotRing, type LngLat } from '@/lib/geo'
import { type PivotGroup, pivotStatus, type Status } from '@/lib/overview'

// The map page's pivots (MapController): the dashboard's pivot with its location and its weather
// zone's rain and ET, drawn as GeoJSON

export type WeatherTotals = { days: number; precip: number | null; et0: number | null }
export type PivotWeather = { past: WeatherTotals | null; ahead: WeatherTotals | null }

export type MapPivot = PivotGroup & {
  latitude: number
  longitude: number
  radius_ft: number | null
  arc_start_deg: number | null
  arc_end_deg: number | null
  weather: PivotWeather | null
}

export type PivotProperties = {
  id: number
  name: string
  /** The most urgent status among its fields in season, or none */
  status: Status | 'none'
  selected: boolean
  /** Outside the "needs water within" window */
  dimmed: boolean
}

export type PolygonFeature<P> = {
  type: 'Feature'
  id: number
  properties: P
  geometry: { type: 'Polygon'; coordinates: LngLat[][] }
}
export type FeatureCollection<P> = { type: 'FeatureCollection'; features: PolygonFeature<P>[] }

export const ring = (pivot: MapPivot) =>
  pivotRing(
    [pivot.longitude, pivot.latitude],
    pivot.radius_ft ?? DEFAULT_RADIUS_FT,
    pivot.arc_start_deg,
    pivot.arc_end_deg,
  )

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
      },
      geometry: { type: 'Polygon', coordinates: [ring(pivot)] },
    })),
  }
}

/** [[west, south], [east, north]] around the pivots' whole circles, or null without pivots */
export function pivotBounds(pivots: MapPivot[]): [LngLat, LngLat] | null {
  const points = pivots.flatMap(ring)
  if (!points.length) return null
  const lngs = points.map(([lng]) => lng)
  const lats = points.map(([, lat]) => lat)
  return [
    [Math.min(...lngs), Math.min(...lats)],
    [Math.max(...lngs), Math.max(...lats)],
  ]
}
