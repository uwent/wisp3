import { boundsOf, distanceM, isPoint, type LngLat, type PivotShape, pivotOutline, pointInPolygon } from '@/lib/geo'
import { type Boundary, boundaryBounds, boundaryCenter, inBoundary } from '@/lib/boundary'

import { outlineDifferenceM, overlapShare, SAME_FIELD_SHARE, SAME_OUTLINE_M, withBoxes } from './overlap'

// Matching imported outlines to the operation: each shape to the field of the same name, or the
// field whose outline it mostly covers, or else a new field under the irrigation system it sits under

export type ImportSystem = PivotShape & { id: number; name: string }
export type ImportField = { id: number; name: string; pivot_id: number; boundary?: Boundary | null }

/** How near a point kind (a traveler, drip) a shape must be to suggest it: half a mile */
export const POINT_SYSTEM_REACH_M = 805

/**
 * The system a shape sits under, for a file's shapes (the systems' outlines worked out once): one
 * whose outline holds the shape's center, else the nearest point kind within half a mile, else null
 */
export function systemSuggester(systems: ImportSystem[]): (boundary: Boundary) => number | null {
  const shaped = systems.flatMap((system) => {
    const ring = pivotOutline(system)
    return ring ? [{ system, ring, box: boundsOf(ring)! }] : []
  })
  const points = systems.filter((system) => isPoint(system.kind))
  return (boundary) => {
    const center = boundaryCenter(boundary)
    const inBox = ([min, max]: [LngLat, LngLat]) =>
      center[0] >= min[0] && center[0] <= max[0] && center[1] >= min[1] && center[1] <= max[1]
    const covering = shaped.find(({ ring, box }) => inBox(box) && pointInPolygon(center, [ring]))
    if (covering) return covering.system.id
    const near = points
      .map((system) => {
        const at: LngLat = [system.longitude, system.latitude]
        return { id: system.id, distance: inBoundary(at, boundary) ? 0 : distanceM(center, at) }
      })
      .filter(({ distance }) => distance <= POINT_SYSTEM_REACH_M)
      .sort((a, b) => a.distance - b.distance)
    return near[0]?.id ?? null
  }
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
/** A shape that's already a field's: the field, and how far apart the two outlines are (outlineDifferenceM) */
export type SameAs = { fieldId: number; meters: number }

/** Whether a shape is already the field's: their outlines within SAME_OUTLINE_M */
export function sameAs(boundary: Boundary | null | undefined, field: ImportField): SameAs | null {
  if (!boundary || !field.boundary) return null
  const meters = outlineDifferenceM(boundary, field.boundary)
  return meters <= SAME_OUTLINE_M ? { fieldId: field.id, meters } : null
}

/**
 * Each shape's starting choice: the field of its name; else the field whose outline it shares at
 * least half of (SAME_FIELD_SHARE, of the smaller), the largest overlaps first; else a new field when
 * a system is suggested; else skipped (and a shape that can't be saved is always skipped). A field
 * is matched once. A shape matched to a field whose outline it already is (sameAs) is skipped, with
 * that field: there's nothing to update.
 */
export function initialChoices(
  shapes: Parameters<typeof matchedChoices>[0],
  fields: ImportField[],
): { choice: Choice; same: SameAs | null }[] {
  const byId = new Map(fields.map((field) => [field.id, field]))
  return matchedChoices(shapes, fields).map((choice, index) => {
    if (choice.kind !== 'field') return { choice, same: null }
    const same = sameAs(shapes[index].boundary, byId.get(choice.fieldId)!)
    return same ? { choice: { kind: 'skip' }, same } : { choice, same: null }
  })
}

function matchedChoices(
  shapes: { name: string; systemId: number | null; problems: string[]; boundary?: Boundary | null }[],
  fields: ImportField[],
): Choice[] {
  const taken = new Set<number>()
  const choices: (Choice | null)[] = shapes.map((shape) => {
    if (shape.problems.length) return { kind: 'skip' }
    const fieldId = matchField(shape.name, fields, shape.systemId)
    if (fieldId === null || taken.has(fieldId)) return null
    taken.add(fieldId)
    return { kind: 'field', fieldId }
  })

  const outlined = withBoxes(
    fields.flatMap((field) =>
      field.boundary && !taken.has(field.id) ? [{ id: field.id, boundary: field.boundary }] : [],
    ),
  )
  const pairs: { shape: number; fieldId: number; share: number }[] = []
  shapes.forEach((shape, index) => {
    if (choices[index] || !shape.boundary || !outlined.length) return
    const shapeBox = boundaryBounds(shape.boundary)
    for (const { outline, box } of outlined) {
      const share = overlapShare(shape.boundary, outline.boundary, shapeBox, box)
      if (share >= SAME_FIELD_SHARE) pairs.push({ shape: index, fieldId: outline.id, share })
    }
  })
  for (const pair of pairs.sort((a, b) => b.share - a.share)) {
    if (choices[pair.shape] || taken.has(pair.fieldId)) continue
    taken.add(pair.fieldId)
    choices[pair.shape] = { kind: 'field', fieldId: pair.fieldId }
  }

  return choices.map(
    (choice, index) => choice ?? (shapes[index].systemId !== null ? { kind: 'new' } : { kind: 'skip' }),
  )
}
