import {
  boundsOf,
  bufferedHull,
  FEET_PER_METER,
  isPoint,
  type LngLat,
  shapeOutline,
  systemName,
  type SystemShape,
} from '@/lib/geo'
import { type Boundary, boundaryBounds, boundaryCenter, boundaryRing, boundaryTop, groupOutline } from '@/lib/boundary'
import {
  type FarmGroup,
  type FieldCard,
  primary,
  type OverviewSystem,
  systemStatus,
  type Status,
  summaryActive,
} from '@/lib/overview'
import { plantingLabel } from '@/lib/plantings'
import type { PlantingSummary } from '@/types/serializers'

import { glyphProperties, type GlyphProperties } from './systemLayers'

// The map page's irrigation systems (MapController): the dashboard's system with its location and
// its weather zone's id, drawn as GeoJSON. Pivots and linears are their outline and a point
// for their glyph (drawn when they're too small to see); the other kinds (a traveler, drip, a
// location) are a point for their glyph. Each irrigation group is a light outline around its
// systems and their fields. Fields with an outline are drawn in their status, named along
// their top, with a badge per planting at their center.

/** A field's outline */
export type MapOutline = { field_id: number; boundary: Boundary }

export type MapSystem = OverviewSystem &
  SystemShape & {
    /** Its weather zone's id (MapZone), or null before its weather cell is known */
    weather_cell_id: number | null
    outlines: MapOutline[]
  }

export type SystemProperties = GlyphProperties & {
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
  system_id: number
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

/** How far a point kind's outline stands off its fields' outlines: 50 ft */
export const POINT_OUTLINE_MARGIN_M = 50 / FEET_PER_METER

/**
 * A system's outline on the map: a system's or linear's shape, or for a point kind whose fields have
 * outlines, the area around them and its own location, so the dot at the place it was put is
 * always inside, even off its fields; null for a point kind without
 */
export function systemOutline(system: MapSystem): LngLat[] | null {
  if (!isPoint(system.kind)) return shapeOutline(system)
  if (!system.outlines.length) return null
  return bufferedHull(
    [[system.longitude, system.latitude], ...system.outlines.flatMap(({ boundary }) => boundaryRing(boundary))],
    POINT_OUTLINE_MARGIN_M,
  )
}

/** A system's fields without an outline, which its marker badges */
export const unoutlinedFields = (system: MapSystem) =>
  system.fields.filter((card) => !system.outlines.some((outline) => outline.field_id === card.id))

/** Where a system is on the map: its outline (systemOutline) and its location, for its glyph */
export function geometries(system: MapSystem): Geometry[] {
  const ring = systemOutline(system)
  const point: Geometry = { type: 'Point', coordinates: [system.longitude, system.latitude] }
  return ring ? [{ type: 'Polygon', coordinates: [ring] }, point] : [point]
}

/** highlighted: the systems the list's filters keep (the others are muted), or null when nothing's filtered */
export function systemFeatures(
  systems: MapSystem[],
  selectedId: number | null,
  highlighted: Set<number> | null,
): FeatureCollection<SystemProperties> {
  return {
    type: 'FeatureCollection',
    features: systems.flatMap((system) => {
      const properties: SystemProperties = {
        id: system.id,
        name: system.name,
        label: systemName(system),
        status: systemStatus(system.fields) ?? 'none',
        selected: system.id === selectedId,
        dimmed: highlighted !== null && !highlighted.has(system.id),
        outlined: system.outlines.length > 0,
        ...glyphProperties(system, badgeRows(unoutlinedFields(system).length), system.outlines.length > 0),
      }
      return geometries(system).map((geometry) => ({ type: 'Feature' as const, id: system.id, properties, geometry }))
    }),
  }
}

/**
 * The fields with outlines, each with a point on its top edge for its name; muted outside the
 * highlighted systems or, given them, the highlighted fields (the list's filters)
 */
export function fieldFeatures(
  systems: MapSystem[],
  selectedFieldId: number | null,
  highlighted: Set<number> | null,
  highlightedFields: Set<number> | null = null,
): FeatureCollection<FieldProperties> {
  return {
    type: 'FeatureCollection',
    features: systems.flatMap((system) =>
      system.outlines.flatMap(({ field_id, boundary }) => {
        const card = system.fields.find((field) => field.id === field_id)
        const summary = card ? primary(card) : null
        const properties = {
          id: field_id,
          system_id: system.id,
          name: card?.name ?? '',
          status: summaryActive(summary) ? summary!.status! : ('none' as const),
          selected: field_id === selectedFieldId,
          dimmed:
            (highlighted !== null && !highlighted.has(system.id)) ||
            (highlightedFields !== null && !highlightedFields.has(field_id)),
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
  stressed: 'Stressed',
  stress_coming: 'Stress coming',
  no_stress: 'No stress',
}

/** A badge: a status, or a gray dot when there's none, and what it is, a line each, for the hover label */
export type Badge = { key: number; status: Status | null; lines: string[] }

/** A planting in the hover label: "Planting: Potato (Russet Burbank, May 15, 65 days)" */
const plantingLine = (summary: PlantingSummary, today: string) => `Planting: ${plantingLabel(summary, today)}`

/** A field's badge on its system's marker: its most urgent planting, named with the field */
export function fieldBadge(card: FieldCard, today: string): Badge {
  const summary = primary(card)
  return {
    key: card.id,
    status: summaryActive(summary) ? summary!.status! : null,
    lines: [`Field: ${card.name}`, summary ? plantingLine(summary, today) : 'No crop this season'],
  }
}

/** An outlined field's plantings as badges at its center */
export type FieldBadges = {
  field_id: number
  system_id: number
  field_name: string
  center: LngLat
  badges: Badge[]
}

/** The outlined fields, each with a badge per planting (a gray dot when it has none) */
export function fieldBadges(systems: MapSystem[], today: string): FieldBadges[] {
  return systems.flatMap((system) =>
    system.outlines.flatMap(({ field_id, boundary }) => {
      const card = system.fields.find((field) => field.id === field_id)
      if (!card) return []
      const badges: Badge[] = card.plantings.length
        ? card.plantings.map((summary) => ({
            key: summary.planting_id,
            status: summaryActive(summary) ? summary.status! : null,
            lines: [plantingLine(summary, today)],
          }))
        : [{ key: 0, status: null, lines: ['No crop this season'] }]
      return [{ field_id, system_id: system.id, field_name: card.name, center: boundaryCenter(boundary), badges }]
    }),
  )
}

/**
 * The irrigation groups among these systems, each outlined around its systems shown and their
 * fields, and the selected one marked to be drawn more strongly
 */
export function groupFeatures(
  farms: FarmGroup<MapSystem>[],
  systems: MapSystem[],
  selectedId: number | null = null,
): FeatureCollection<{ name: string; selected: boolean }> {
  const shown = new Set(systems.map((system) => system.id))
  return {
    type: 'FeatureCollection',
    features: farms.flatMap((farm) =>
      farm.irrigation_groups.flatMap((group) => {
        const members = farm.systems.filter((system) => system.irrigation_group_id === group.id && shown.has(system.id))
        if (!members.length) return []
        return [
          {
            type: 'Feature' as const,
            id: group.id,
            properties: { name: group.name, selected: group.id === selectedId },
            geometry: {
              type: 'Polygon' as const,
              coordinates: [
                groupOutline(
                  members,
                  members.flatMap((system) => system.outlines.map((o) => o.boundary)),
                ),
              ],
            },
          },
        ]
      }),
    ),
  }
}

/** [[west, south], [east, north]] around the systems' whole outlines (or points), or null without systems */
export function systemBounds(systems: MapSystem[]): [LngLat, LngLat] | null {
  return boundsOf(
    systems.flatMap((system) => [
      ...(shapeOutline(system) ?? [[system.longitude, system.latitude] as LngLat]),
      ...system.outlines.flatMap(({ boundary }) => boundaryBounds(boundary)),
    ]),
  )
}

/**
 * How a marker's badges are packed: rows of at most ⌈√n⌉, the longer rows first, so 2 sit
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
