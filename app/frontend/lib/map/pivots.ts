import {
  type Boundary,
  boundaryBounds,
  boundaryCenter,
  boundaryTop,
  groupOutline,
  type LngLat,
  pivotOutline,
  systemName,
  type PivotShape,
} from '@/lib/geo'
import { type FarmGroup, primary, type PivotGroup, pivotStatus, type Status, summaryActive } from '@/lib/overview'
import { cropName } from '@/lib/plantings'
import type { PlantingSummary } from '@/types/serializers'

import { glyphProperties, type GlyphProperties } from './systemLayers'

// The map page's irrigation systems (MapController): the dashboard's pivot with its location and
// its weather zone's rain and ET, drawn as GeoJSON. Pivots and linears are their outline and a point
// for their glyph (drawn when they're too small to see, G.14); the other kinds (a traveler, drip, a
// location) are a point for their glyph. Each irrigation group is a light outline around its
// systems and their fields. Fields with an outline are drawn in their status (G.10), named along
// their top, with a badge per planting at their center (G.14).

export type WeatherTotals = { days: number; precip: number | null; et0: number | null }
export type PivotWeather = { past: WeatherTotals | null; ahead: WeatherTotals | null }

/** A field's outline (G.10) */
export type MapOutline = { field_id: number; boundary: Boundary }

export type MapPivot = PivotGroup & PivotShape & { weather: PivotWeather | null; outlines: MapOutline[] }

export type PivotProperties = GlyphProperties & {
  id: number
  name: string
  /** "East gun (traveler)" (systemName) */
  label: string
  /** The most urgent status among its fields in season, or none (for the marker; the system is drawn in its own color) */
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

type Geometry = { type: 'Polygon'; coordinates: LngLat[][] } | { type: 'Point'; coordinates: LngLat }
export type MapFeature<P> = { type: 'Feature'; id: number; properties: P; geometry: Geometry }
export type FeatureCollection<P> = { type: 'FeatureCollection'; features: MapFeature<P>[] }

/** Where a system is on the map: its outline (a pivot or linear) and its location, for its glyph */
export function geometries(pivot: PivotShape): Geometry[] {
  const ring = pivotOutline(pivot)
  const point: Geometry = { type: 'Point', coordinates: [pivot.longitude, pivot.latitude] }
  return ring ? [{ type: 'Polygon', coordinates: [ring] }, point] : [point]
}

/** highlighted: the pivots in the "needs water within" window, or null when there's no window */
export function pivotFeatures(
  pivots: MapPivot[],
  selectedId: number | null,
  highlighted: Set<number> | null,
): FeatureCollection<PivotProperties> {
  return {
    type: 'FeatureCollection',
    features: pivots.flatMap((pivot) => {
      const properties: PivotProperties = {
        id: pivot.id,
        name: pivot.name,
        label: systemName(pivot),
        status: pivotStatus(pivot.fields) ?? 'none',
        selected: pivot.id === selectedId,
        dimmed: highlighted !== null && !highlighted.has(pivot.id),
        outlined: pivot.outlines.length > 0,
        ...glyphProperties(pivot),
      }
      return geometries(pivot).map((geometry) => ({ type: 'Feature' as const, id: pivot.id, properties, geometry }))
    }),
  }
}

/** The fields with outlines, in their status, each with a point on its top edge for its name */
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
            geometry: { type: 'Point' as const, coordinates: boundaryTop(boundary) },
          },
        ]
      }),
    ),
  }
}

/** A status in words, for badges' tooltips and labels */
export const STATUS_LABELS: Record<Status, string> = {
  irrigate: 'Irrigate',
  caution: 'Caution',
  needs_canopy: 'No canopy data',
  ok: 'OK',
  full: 'Full',
}

/** Why a planting (a field's primary one, or none) has no status, for its gray dot */
export function idleText(summary: PlantingSummary | null): string {
  if (!summary) return 'no crop this season'
  if (summary.phase === 'upcoming') return 'season not started'
  if (summary.phase === 'ended') return 'season ended'
  return 'waiting for weather'
}

/** A badge: a status, or a gray dot when there's none, and what it is in words for its hover label */
export type Badge = { key: number; status: Status | null; label: string }

const capitalized = (text: string) => text.charAt(0).toUpperCase() + text.slice(1)

/** A status, or why there's none, in words: "Irrigate", "Season ended" */
export const statusText = (summary: PlantingSummary | null) =>
  summaryActive(summary) ? STATUS_LABELS[summary!.status!] : capitalized(idleText(summary))

/** An outlined field's plantings as badges at its center (G.14) */
export type FieldBadges = {
  field_id: number
  pivot_id: number
  field_name: string
  center: LngLat
  badges: Badge[]
}

/** The outlined fields, each with a badge per planting (a gray dot when it has none) */
export function fieldBadges(pivots: MapPivot[]): FieldBadges[] {
  return pivots.flatMap((pivot) =>
    pivot.outlines.flatMap(({ field_id, boundary }) => {
      const card = pivot.fields.find((field) => field.id === field_id)
      if (!card) return []
      const badges: Badge[] = card.plantings.length
        ? card.plantings.map((summary) => ({
            key: summary.planting_id,
            status: summaryActive(summary) ? summary.status! : null,
            label: `${cropName(summary)} (${card.name}) · ${statusText(summary)}`,
          }))
        : [{ key: 0, status: null, label: `${card.name} · ${statusText(null)}` }]
      return [{ field_id, pivot_id: pivot.id, field_name: card.name, center: boundaryCenter(boundary), badges }]
    }),
  )
}

/** Whether every one of the system's fields has an outline (its marker then has nothing to show) */
export const allOutlined = (pivot: MapPivot) =>
  pivot.fields.length > 0 && pivot.fields.every((card) => pivot.outlines.some((o) => o.field_id === card.id))

/** The irrigation groups among these pivots, each outlined around its systems shown and their fields */
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
            geometry: {
              type: 'Polygon' as const,
              coordinates: [
                groupOutline(
                  members,
                  members.flatMap((pivot) => pivot.outlines.map((o) => o.boundary)),
                ),
              ],
            },
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

/**
 * How a marker's badges are packed (G.14): rows of at most ⌈√n⌉, the longer rows first, so 2 sit
 * side by side, 3 make a triangle, 4 a square, 5 three over two and 7 three, two and two
 */
export function badgeRows(count: number): number[] {
  if (count <= 0) return []
  const columns = Math.ceil(Math.sqrt(count))
  const rows = Math.ceil(count / columns)
  const base = Math.floor(count / rows)
  return Array.from({ length: rows }, (_, row) => base + (row < count % rows ? 1 : 0))
}

/** Items packed in badgeRows' rows: five as three over two */
export function packRows<T>(items: T[]): T[][] {
  let start = 0
  return badgeRows(items.length).map((size) => items.slice(start, (start += size)))
}
