import { distanceM, type LngLat, type PivotShape } from '@/lib/geo'
import { type Boundary, boundaryBounds, boundaryCenter } from '@/lib/boundary'

import { overlapShare } from './overlap'
import { systemDistanceM } from './problems'

// The choices offered on an import card, nearest the shape first, kept pure for testing: the
// fields it could update and the systems a new field could go under.

export type CandidateField = { id: number; pivot_id: number; boundary?: Boundary | null }
export type CandidateSystem = PivotShape & { id: number }

/** A field an imported shape could update: how much of the smaller outline they share, and how far apart their centers are */
export type FieldCandidate = { id: number; share: number; meters: number }

/**
 * The fields for a shape: those it overlaps first, the largest share first; then the rest by the
 * distance from its center to the field's outline's center, or to its system's location when the
 * field has no outline
 */
export function fieldCandidates(
  boundary: Boundary,
  fields: CandidateField[],
  systems: CandidateSystem[],
): FieldCandidate[] {
  const center = boundaryCenter(boundary)
  const box = boundaryBounds(boundary)
  const systemAt = new Map(systems.map((system) => [system.id, [system.longitude, system.latitude] as LngLat]))
  return fields
    .map((field) => {
      const share = field.boundary ? overlapShare(boundary, field.boundary, box) : 0
      const at = field.boundary ? boundaryCenter(field.boundary) : systemAt.get(field.pivot_id)
      return { id: field.id, share, meters: at ? distanceM(center, at) : Infinity }
    })
    .sort((a, b) => b.share - a.share || a.meters - b.meters)
}

/** The systems for a new field, nearest the shape first (0: under a pivot's or linear's shape, or a point kind inside it) */
export function systemCandidates(boundary: Boundary, systems: CandidateSystem[]): { id: number; meters: number }[] {
  return systems
    .map((system) => ({ id: system.id, meters: systemDistanceM(boundary, system) }))
    .sort((a, b) => a.meters - b.meters)
}
