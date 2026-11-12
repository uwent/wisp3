import {
  type Boundary,
  boundaryPolygons,
  FEET_PER_METER,
  inBoundary,
  isPoint,
  KIND_NAMES,
  type LngLat,
  type PivotShape,
  pivotOutline,
  pointInPolygon,
} from '@/lib/geo'
import type { UnitSystem } from '@/lib/units'

// Outlines to check (PLAN.md Phase 8 G.10): an irrigation system doesn't move with its field (that
// would change its weather), so a field whose outline isn't under its pivot or linear, or is more
// than a quarter mile from a point kind (a traveler, drip), is listed on Setup to fix by hand.

/** How far a point kind may be from its field's outline: a quarter mile */
export const POINT_REACH_M = 402

export type OutlineProblem = { fieldId: number; message: string }

type System = PivotShape & { name: string }
type Outlined = { id: number; name: string; boundary: Boundary | null }

const rad = (deg: number) => (deg * Math.PI) / 180

/** Meters from a point to a segment, on a plane around the point (plenty within a few miles) */
function segmentDistanceM(point: LngLat, a: LngLat, b: LngLat): number {
  const scale = Math.cos(rad(point[1]))
  const xy = ([lng, lat]: LngLat) => [(lng - point[0]) * scale * 111_320, (lat - point[1]) * 111_320]
  const [ax, ay] = xy(a)
  const [bx, by] = xy(b)
  const length2 = (bx - ax) ** 2 + (by - ay) ** 2
  const t = length2 ? Math.max(0, Math.min(1, -(ax * (bx - ax) + ay * (by - ay)) / length2)) : 0
  return Math.hypot(ax + t * (bx - ax), ay + t * (by - ay))
}

/** Meters from a point to the nearest edge of an outline (0 inside it) */
export function distanceToBoundaryM(point: LngLat, boundary: Boundary): number {
  if (inBoundary(point, boundary)) return 0
  let best = Infinity
  for (const ring of boundaryPolygons(boundary).flat())
    for (let i = 0; i + 1 < ring.length; i++) best = Math.min(best, segmentDistanceM(point, ring[i], ring[i + 1]))
  return best
}

/** Whether an outline and a ring overlap: a corner of either inside the other, or an edge crossing */
function overlaps(boundary: Boundary, ring: LngLat[]): boolean {
  const rings = boundaryPolygons(boundary).flat()
  if (rings.flat().some((point) => pointInPolygon(point, [ring]))) return true
  if (ring.some((point) => inBoundary(point, boundary))) return true
  return rings.some((outline) => crosses(outline, ring))
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

/** "2.1 mi", "900 ft"; "3.4 km", "270 m" */
export function formatReach(meters: number, system: UnitSystem): string {
  if (system === 'metric') return meters >= 1000 ? `${(meters / 1000).toFixed(1)} km` : `${Math.round(meters)} m`
  const miles = meters / 1609.344
  return miles >= 0.1 ? `${miles.toFixed(1)} mi` : `${Math.round(meters * FEET_PER_METER)} ft`
}

/** The fields whose outline doesn't sit with their irrigation system, worded for Setup */
export function outlineProblems(system: System, fields: Outlined[], unitSystem: UnitSystem): OutlineProblem[] {
  const label = `${KIND_NAMES[system.kind]}: ${system.name}`
  const at: LngLat = [system.longitude, system.latitude]
  return fields.flatMap((field) => {
    if (!field.boundary) return []
    const ring = pivotOutline(system)
    if (ring && !isPoint(system.kind)) {
      if (overlaps(field.boundary, ring)) return []
      const away = Math.min(...ring.map((point) => distanceToBoundaryM(point, field.boundary!)))
      return [
        {
          fieldId: field.id,
          message: `${field.name}'s outline isn't under ${label} (${formatReach(away, unitSystem)} away)`,
        },
      ]
    }
    const away = distanceToBoundaryM(at, field.boundary)
    if (away <= POINT_REACH_M) return []
    return [{ fieldId: field.id, message: `${field.name}'s outline is ${formatReach(away, unitSystem)} from ${label}` }]
  })
}
