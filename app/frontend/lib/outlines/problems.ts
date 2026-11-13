import {
  type Boundary,
  boundaryRing,
  FEET_PER_METER,
  inBoundary,
  isPoint,
  KIND_NAMES,
  type LngLat,
  type PivotShape,
  pivotOutline,
  pointInPolygon,
  systemName,
} from '@/lib/geo'
import type { UnitSystem } from '@/lib/units'

// Outlines to check (PLAN.md Phase 8 G.10): an irrigation system doesn't move with its field (that
// would change its weather), so a field whose outline isn't under its pivot or linear, or is more
// than a quarter mile from a point kind (a traveler, drip), is listed on Setup to fix by hand. The
// shape page (G.14 part 7) warns of the same, offers the other systems within half a mile, and draws
// a line to the system chosen (reachLine).

/** How far a point kind may be from its field's outline: a quarter mile */
export const POINT_REACH_M = 402
/** How far the shape page looks for other systems to move a field to: half a mile */
export const NEARBY_M = 805

export type OutlineProblem = { fieldId: number; message: string }

type System = PivotShape & { name: string }
type Outlined = { id: number; name: string; boundary: Boundary | null }

const rad = (deg: number) => (deg * Math.PI) / 180

export type Nearest = { point: LngLat; meters: number }

/** The point of a segment nearest a point, and how far it is in meters, on a plane around the point (plenty within a few miles) */
export function nearestOnSegment(point: LngLat, a: LngLat, b: LngLat): Nearest {
  const scale = Math.cos(rad(point[1]))
  const xy = ([lng, lat]: LngLat) => [(lng - point[0]) * scale * 111_320, (lat - point[1]) * 111_320]
  const [ax, ay] = xy(a)
  const [bx, by] = xy(b)
  const length2 = (bx - ax) ** 2 + (by - ay) ** 2
  const t = length2 ? Math.max(0, Math.min(1, -(ax * (bx - ax) + ay * (by - ay)) / length2)) : 0
  return {
    point: [a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])],
    meters: Math.hypot(ax + t * (bx - ax), ay + t * (by - ay)),
  }
}

/** The point on a ring's edges nearest a point */
export function nearestOnRing(point: LngLat, ring: LngLat[]): Nearest {
  let best: Nearest = { point: ring[0], meters: Infinity }
  for (let i = 0; i + 1 < ring.length; i++) {
    const near = nearestOnSegment(point, ring[i], ring[i + 1])
    if (near.meters < best.meters) best = near
  }
  return best
}

/** Meters from a point to the nearest edge of an outline (0 inside it) */
export function distanceToBoundaryM(point: LngLat, boundary: Boundary): number {
  if (inBoundary(point, boundary)) return 0
  return nearestOnRing(point, boundaryRing(boundary)).meters
}

/** Whether an outline and a ring overlap: a corner of either inside the other, or an edge crossing */
function overlaps(boundary: Boundary, ring: LngLat[]): boolean {
  const outline = boundaryRing(boundary)
  if (outline.some((point) => pointInPolygon(point, [ring]))) return true
  if (ring.some((point) => inBoundary(point, boundary))) return true
  return crosses(outline, ring)
}

function crosses(a: LngLat[], b: LngLat[]): boolean {
  const side = (p: LngLat, q: LngLat, r: LngLat) =>
    Math.sign((q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0]))
  for (let i = 0; i + 1 < a.length; i++)
    for (let j = 0; j + 1 < b.length; j++) {
      const [p1, p2, q1, q2] = [a[i], a[i + 1], b[j], b[j + 1]]
      if (side(p1, p2, q1) !== side(p1, p2, q2) && side(q1, q2, p1) !== side(q1, q2, p2)) return true
    }
  return false
}

/**
 * The shortest line from a field's shape to its system: from the nearest point of the shape's edge
 * to the system's location (a point kind) or the nearest point of its shape (a pivot or linear),
 * with its length in meters
 */
export function reachLine(boundary: Boundary, system: PivotShape): { from: LngLat; to: LngLat; meters: number } {
  const outline = boundaryRing(boundary)
  const ring = isPoint(system.kind) ? null : pivotOutline(system)
  if (!ring) {
    const to: LngLat = [system.longitude, system.latitude]
    const near = nearestOnRing(to, outline)
    return { from: near.point, to, meters: near.meters }
  }
  let best = { from: outline[0], to: ring[0], meters: Infinity }
  for (const corner of ring) {
    const near = nearestOnRing(corner, outline)
    if (near.meters < best.meters) best = { from: near.point, to: corner, meters: near.meters }
  }
  for (const corner of outline) {
    const near = nearestOnRing(corner, ring)
    if (near.meters < best.meters) best = { from: corner, to: near.point, meters: near.meters }
  }
  return best
}

/**
 * Whether a field's shape sits with a system: overlapping a pivot's or linear's shape, or within a
 * quarter mile of a point kind's location
 */
export function touchesSystem(boundary: Boundary, system: PivotShape): boolean {
  const ring = isPoint(system.kind) ? null : pivotOutline(system)
  if (ring) return overlaps(boundary, ring)
  return distanceToBoundaryM([system.longitude, system.latitude], boundary) <= POINT_REACH_M
}

/**
 * Meters from a field's shape to a system: 0 when a pivot's or linear's shape overlaps it or a
 * point kind is inside it, else the length of reachLine
 */
export function systemDistanceM(boundary: Boundary, system: PivotShape): number {
  const ring = isPoint(system.kind) ? null : pivotOutline(system)
  if (!ring) return distanceToBoundaryM([system.longitude, system.latitude], boundary)
  return overlaps(boundary, ring) ? 0 : reachLine(boundary, system).meters
}

/** The systems within NEARBY_M of a shape, nearest first, with how far each is */
export function systemsNear<T extends PivotShape>(boundary: Boundary, systems: T[]): { system: T; meters: number }[] {
  return systems
    .map((system) => ({ system, meters: systemDistanceM(boundary, system) }))
    .filter(({ meters }) => meters <= NEARBY_M)
    .sort((a, b) => a.meters - b.meters)
}

/** "2.1 mi", "900 ft"; "3.4 km", "270 m" */
export function formatReach(meters: number, system: UnitSystem): string {
  if (system === 'metric') return meters >= 1000 ? `${(meters / 1000).toFixed(1)} km` : `${Math.round(meters)} m`
  const miles = meters / 1609.344
  return miles >= 0.1 ? `${miles.toFixed(1)} mi` : `${Math.round(meters * FEET_PER_METER)} ft`
}

/** The fields whose outline doesn't sit with their irrigation system, worded for Setup */
export function outlineProblems(system: System, fields: Outlined[], unitSystem: UnitSystem): OutlineProblem[] {
  const label = systemName({ name: system.name, kind_name: KIND_NAMES[system.kind] })
  const shaped = !isPoint(system.kind) && pivotOutline(system) !== null
  return fields.flatMap((field) => {
    if (!field.boundary || touchesSystem(field.boundary, system)) return []
    const away = formatReach(reachLine(field.boundary, system).meters, unitSystem)
    const message = shaped
      ? `${field.name}'s shape isn't under ${label}, ${away} away`
      : `${field.name}'s shape is ${away} from ${label}`
    return [{ fieldId: field.id, message }]
  })
}
