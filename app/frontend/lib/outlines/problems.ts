import {
  boundsOf,
  DEFAULT_RADIUS_FT,
  FEET_PER_METER,
  isPoint,
  KIND_NAMES,
  type LngLat,
  type PivotShape,
  pivotOutline,
  pointInPolygon,
  systemName,
} from '@/lib/geo'
import { type Boundary, boundaryBounds, boundaryRing, inBoundary } from '@/lib/boundary'
import { nearestT, segmentsCross } from '@/lib/planar'
import type { UnitSystem } from '@/lib/units'

// Outlines to check: an irrigation system doesn't move with its field (that
// would change its weather), so a field whose outline isn't under its pivot or linear, or is more
// than a quarter mile from a point kind (a traveler, drip), is listed on Setup to fix by hand. The
// shape page warns of the same, offers the other systems within half a mile, and draws
// a line to the system chosen (reachLine).

/** How far a point kind may be from its field's outline: a quarter mile */
export const POINT_REACH_M = 402
/** How far the shape page looks for other systems to move a field to: half a mile */
export const NEARBY_M = 805

export type OutlineProblem = { fieldId: number; message: string }

type System = PivotShape & { name: string }
type Outlined = { id: number; name: string; boundary: Boundary | null }

const rad = (deg: number) => (deg * Math.PI) / 180
const M_PER_DEG = 111_320

export type Nearest = { point: LngLat; meters: number }

/** The point of a segment nearest a point, and how far it is in meters, on a plane around the point (plenty within a few miles) */
export function nearestOnSegment(point: LngLat, a: LngLat, b: LngLat): Nearest {
  const scale = Math.cos(rad(point[1]))
  const xy = ([lng, lat]: LngLat) => [(lng - point[0]) * scale * 111_320, (lat - point[1]) * 111_320]
  const [ax, ay] = xy(a)
  const [bx, by] = xy(b)
  const t = nearestT([0, 0], [ax, ay], [bx, by])
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

// Touching counts here: a shape touching its system's edge is with it
function crosses(a: LngLat[], b: LngLat[]): boolean {
  for (let i = 0; i + 1 < a.length; i++)
    for (let j = 0; j + 1 < b.length; j++)
      if (segmentsCross(a[i], a[i + 1], b[j], b[j + 1], { touching: true })) return true
  return false
}

/** Positions as flat x, y pairs in meters on a plane around an origin (plenty within a few miles; farther, a close estimate) */
function projected(ring: LngLat[], origin: LngLat): Float64Array {
  const kx = Math.cos(rad(origin[1])) * M_PER_DEG
  const xy = new Float64Array(ring.length * 2)
  ring.forEach(([lng, lat], i) => {
    xy[2 * i] = (lng - origin[0]) * kx
    xy[2 * i + 1] = (lat - origin[1]) * M_PER_DEG
  })
  return xy
}

/** The nearest point of a projected ring's edges to x, y: its edge, how far along it, and the squared distance */
function nearestEdge(x: number, y: number, xy: Float64Array): { edge: number; t: number; d2: number } {
  let best = { edge: 0, t: 0, d2: Infinity }
  for (let i = 0; i + 3 < xy.length; i += 2) {
    const [ax, ay, dx, dy] = [xy[i], xy[i + 1], xy[i + 2] - xy[i], xy[i + 3] - xy[i + 1]]
    const length2 = dx * dx + dy * dy
    const t = length2 ? Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / length2)) : 0
    const [ex, ey] = [ax + t * dx - x, ay + t * dy - y]
    const d2 = ex * ex + ey * ey
    if (d2 < best.d2) best = { edge: i / 2, t, d2 }
  }
  return best
}

const along = (ring: LngLat[], { edge, t }: { edge: number; t: number }): LngLat => {
  const [a, b] = [ring[edge], ring[edge + 1]]
  return [a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])]
}

/**
 * The shortest line from a field's shape to its system: from the nearest point of the shape's edge
 * to the system's location (a point kind) or the nearest point of its shape (a pivot or linear),
 * with its length in meters. Both are projected once onto a plane around the shape, so the many
 * corner-to-edge distances are plain arithmetic (an import's thousands of shapes).
 */
export function reachLine(boundary: Boundary, system: PivotShape): { from: LngLat; to: LngLat; meters: number } {
  const outline = boundaryRing(boundary)
  const ring = isPoint(system.kind) ? null : pivotOutline(system)
  const origin = outline[0]
  const shapeXY = projected(outline, origin)
  if (!ring) {
    const to: LngLat = [system.longitude, system.latitude]
    const point = projected([to], origin)
    const near = nearestEdge(point[0], point[1], shapeXY)
    return { from: along(outline, near), to, meters: Math.sqrt(near.d2) }
  }
  const ringXY = projected(ring, origin)
  let best = { from: outline[0], to: ring[0], d2: Infinity }
  for (let k = 0; k < ring.length; k++) {
    const near = nearestEdge(ringXY[2 * k], ringXY[2 * k + 1], shapeXY)
    if (near.d2 < best.d2) best = { from: along(outline, near), to: ring[k], d2: near.d2 }
  }
  for (let k = 0; k < outline.length; k++) {
    const near = nearestEdge(shapeXY[2 * k], shapeXY[2 * k + 1], ringXY)
    if (near.d2 < best.d2) best = { from: outline[k], to: along(ring, near), d2: near.d2 }
  }
  return { from: best.from, to: best.to, meters: Math.sqrt(best.d2) }
}

/** The box a system covers: a center pivot's whole circle (an arc's too), a linear's shape, a point kind's location */
function systemBox(system: PivotShape): [LngLat, LngLat] {
  const at: LngLat = [system.longitude, system.latitude]
  if (isPoint(system.kind)) return [at, at]
  if (system.kind === 'linear') return boundsOf(pivotOutline(system)!)!
  const meters = (system.radius_ft ?? DEFAULT_RADIUS_FT) / FEET_PER_METER
  const [dLng, dLat] = [meters / (Math.cos(rad(at[1])) * M_PER_DEG), meters / M_PER_DEG]
  return [
    [at[0] - dLng, at[1] - dLat],
    [at[0] + dLng, at[1] + dLat],
  ]
}

/**
 * Meters between two boxes (0 where they meet), never more than between anything inside them: a
 * degree of longitude is taken at the latitude farthest from the equator, where it's shortest
 */
function boxGapM([aMin, aMax]: [LngLat, LngLat], [bMin, bMax]: [LngLat, LngLat]): number {
  const farthest = Math.max(...[aMin[1], aMax[1], bMin[1], bMax[1]].map(Math.abs))
  const dx = Math.max(0, bMin[0] - aMax[0], aMin[0] - bMax[0]) * Math.cos(rad(farthest)) * M_PER_DEG
  const dy = Math.max(0, bMin[1] - aMax[1], aMin[1] - bMax[1]) * M_PER_DEG
  return Math.hypot(dx, dy)
}

/**
 * Meters from a shape to the nearest of the systems (systemDistanceM), or null with none. The
 * systems are tried nearest box first, stopping once a box is farther than the best distance found,
 * so a county file's shapes each measure only a few.
 */
export function nearestSystemM(boundary: Boundary, systems: PivotShape[]): number | null {
  if (!systems.length) return null
  const box = boundaryBounds(boundary)
  const ordered = systems
    .map((system) => ({ system, gap: boxGapM(box, systemBox(system)) }))
    .sort((a, b) => a.gap - b.gap)
  let best = Infinity
  for (const { system, gap } of ordered) {
    if (gap >= best) break
    best = Math.min(best, systemDistanceM(boundary, system))
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

/** "2.1 mi", "900 ft" (feet below 1,000); "3.4 km", "270 m" (meters below 1,000) */
export function formatReach(meters: number, system: UnitSystem): string {
  if (system === 'metric') {
    if (Math.round(meters) < 1000) return `${Math.round(meters)} m`
    return `${(meters / 1000).toLocaleString('en-US', { minimumFractionDigits: 1, maximumFractionDigits: 1 })} km`
  }
  const feet = Math.round(meters * FEET_PER_METER)
  if (feet < 1000) return `${feet} ft`
  return `${(meters / 1609.344).toLocaleString('en-US', { minimumFractionDigits: 1, maximumFractionDigits: 1 })} mi`
}

/** How far a system is from a field's shape: "0.5 mi away", "overlaps this field" (a pivot or linear) or "in this field" (a point kind) */
export function systemReach(system: PivotShape, meters: number, unitSystem: UnitSystem): string {
  if (meters > 0) return `${formatReach(meters, unitSystem)} away`
  return isPoint(system.kind) ? 'in this field' : 'overlaps this field'
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
