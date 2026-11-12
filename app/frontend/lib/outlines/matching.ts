import {
  type Boundary,
  boundaryCenter,
  distanceM,
  inBoundary,
  isPoint,
  type PivotShape,
  pivotOutline,
  pointInPolygon,
} from '@/lib/geo'

// Matching imported outlines to the operation (PLAN.md Phase 8 G.10): each shape to the field of
// the same name, or else a new field under the irrigation system it sits under

export type ImportSystem = PivotShape & { id: number; name: string }
export type ImportField = { id: number; name: string; pivot_id: number }

/** How near a point kind (a traveler, drip) a shape must be to suggest it: half a mile */
export const POINT_SYSTEM_REACH_M = 805

/**
 * The system a shape sits under: one whose outline holds the shape's center, else the nearest
 * point kind within half a mile, else null
 */
export function suggestSystem(boundary: Boundary, systems: ImportSystem[]): number | null {
  const center = boundaryCenter(boundary)
  const covering = systems.find((system) => {
    const ring = pivotOutline(system)
    return ring !== null && pointInPolygon(center, [ring])
  })
  if (covering) return covering.id
  const points = systems
    .filter((system) => isPoint(system.kind))
    .map((system) => {
      const at: [number, number] = [system.longitude, system.latitude]
      return { id: system.id, distance: inBoundary(at, boundary) ? 0 : distanceM(center, at) }
    })
    .filter(({ distance }) => distance <= POINT_SYSTEM_REACH_M)
    .sort((a, b) => a.distance - b.distance)
  return points[0]?.id ?? null
}

const normalized = (name: string) => name.trim().toLowerCase().replace(/\s+/g, ' ')

/**
 * The field a shape's name matches (ignoring case and spacing); with several of that name, the one
 * under the suggested system, else none (the grower picks)
 */
export function matchField(name: string, fields: ImportField[], systemId: number | null): number | null {
  if (!name.trim()) return null
  const named = fields.filter((field) => normalized(field.name) === normalized(name))
  if (named.length === 1) return named[0].id
  return named.find((field) => field.pivot_id === systemId)?.id ?? null
}

/** Where a shape goes: nowhere, an existing field, or a new field under a system */
export type Choice = { kind: 'skip' } | { kind: 'field'; fieldId: number } | { kind: 'new' }

/**
 * Each shape's starting choice: its matching field; else a new field when a system is suggested;
 * else skipped (and a shape that can't be saved is always skipped). A field is matched once.
 */
export function initialChoices(
  shapes: { name: string; systemId: number | null; problems: string[] }[],
  fields: ImportField[],
): Choice[] {
  const taken = new Set<number>()
  return shapes.map((shape) => {
    if (shape.problems.length) return { kind: 'skip' }
    const fieldId = matchField(shape.name, fields, shape.systemId)
    if (fieldId !== null && !taken.has(fieldId)) {
      taken.add(fieldId)
      return { kind: 'field', fieldId }
    }
    return shape.systemId !== null ? { kind: 'new' } : { kind: 'skip' }
  })
}
