import { groupOutline, type LngLat, pivotOutline, type PivotShape } from '@/lib/geo'
import { type FarmGroup, type PivotGroup, pivotStatus, type Status } from '@/lib/overview'

// The map page's irrigation systems (MapController): the dashboard's pivot with its location and
// its weather zone's rain and ET, drawn as GeoJSON. Pivots and linears are their outline; the other
// kinds (a traveler, drip, a location) are a point. Each irrigation group is a light outline around
// its systems.

export type WeatherTotals = { days: number; precip: number | null; et0: number | null }
export type PivotWeather = { past: WeatherTotals | null; ahead: WeatherTotals | null }

export type MapPivot = PivotGroup & PivotShape & { weather: PivotWeather | null }

export type PivotProperties = {
  id: number
  name: string
  /** The most urgent status among its fields in season, or none */
  status: Status | 'none'
  selected: boolean
  /** Outside the "needs water within" window */
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
      },
      geometry: geometry(pivot),
    })),
  }
}

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
  const points = pivots.flatMap((pivot) => pivotOutline(pivot) ?? [[pivot.longitude, pivot.latitude] as LngLat])
  if (!points.length) return null
  const lngs = points.map(([lng]) => lng)
  const lats = points.map(([, lat]) => lat)
  return [
    [Math.min(...lngs), Math.min(...lats)],
    [Math.max(...lngs), Math.max(...lats)],
  ]
}
