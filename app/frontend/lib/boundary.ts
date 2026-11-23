import { boundsOf, bufferedHull, EARTH_RADIUS_M, type LngLat, pointInPolygon, type PivotShape, surveyRing } from './geo'
import { segmentDistance, segmentsCross } from './planar'

const rad = (deg: number) => (deg * Math.PI) / 180

// A field's outline (FieldBoundary on the server): a GeoJSON Polygon
// with one ring (no holes, no parts) in longitude and latitude, for the map and the suggested area only

export type Boundary = { type: 'Polygon'; coordinates: [LngLat[]] }

// FieldBoundary's limits: corners in the outline (plenty for a field drawn by hand; files are
// simplified to it), and its area in acres
export const MAX_BOUNDARY_VERTICES = 100
export const MAX_FIELD_ACRES = 1500
export const MIN_FIELD_ACRES = 0.01
// Where WISP works (Pivot::LATITUDES and LONGITUDES): the US and Canada
export const MIN_LATITUDE = 18
export const MAX_LATITUDE = 84
export const MIN_LONGITUDE = -180
export const MAX_LONGITUDE = -52
const SQUARE_METERS_PER_ACRE = 4046.8564224
const DIGITS = 7

/** An outline's ring (closed: its last position repeats its first) */
export const boundaryRing = (boundary: Boundary): LngLat[] => boundary.coordinates[0]

/** An outline from a ring, closed if it isn't */
export const boundaryFrom = (ring: LngLat[]): Boundary => ({ type: 'Polygon', coordinates: [closeRing(ring)] })

/** Corners, each counted once (a ring's last position repeats its first) */
export const vertexCount = (boundary: Boundary) => Math.max(boundaryRing(boundary).length - 1, 0)

/** A ring's area on a spherical earth in m² (Chamberlain and Duquette, as FieldBoundary and Turf) */
export function ringAreaM2(ring: LngLat[]): number {
  const n = ring.length - 1
  if (n < 3) return 0
  let total = 0
  for (let i = 0; i < n; i++) {
    const lower = ring[i]
    const middle = ring[(i + 1) % n]
    const upper = ring[(i + 2) % n]
    total += (rad(upper[0]) - rad(lower[0])) * Math.sin(rad(middle[1]))
  }
  return Math.abs((total * EARTH_RADIUS_M ** 2) / 2)
}

/** An outline's area in acres */
export const boundaryAcres = (boundary: Boundary) => ringAreaM2(boundaryRing(boundary)) / SQUARE_METERS_PER_ACRE

/** What's wrong with an outline, worded as the server words it (FieldBoundary.errors), or [] */
export function boundaryErrors(boundary: Boundary): string[] {
  const ring = boundaryRing(boundary)
  const errors: string[] = []
  if (ring.length < 4) errors.push('has fewer than 3 corners')
  if (ring.length >= 4 && !samePosition(ring[0], ring[ring.length - 1])) errors.push("isn't closed")
  if (vertexCount(boundary) > MAX_BOUNDARY_VERTICES)
    errors.push(`has too many corners (at most ${MAX_BOUNDARY_VERTICES.toLocaleString('en-US')}; simplify it)`)
  if (
    !ring.every(
      ([lng, lat]) => lat >= MIN_LATITUDE && lat <= MAX_LATITUDE && lng >= MIN_LONGITUDE && lng <= MAX_LONGITUDE,
    )
  )
    errors.push('must be in the US or Canada')
  if (errors.length) return errors
  if (pathCrossesItself(ring)) errors.push('crosses itself')
  const acres = boundaryAcres(boundary)
  if (acres < MIN_FIELD_ACRES) errors.push(`is too small (at least ${MIN_FIELD_ACRES} acres)`)
  if (acres > MAX_FIELD_ACRES)
    errors.push(`is larger than a field (at most ${MAX_FIELD_ACRES.toLocaleString('en-US')} acres)`)
  return errors
}

const samePosition = (a: LngLat, b: LngLat) => a[0] === b[0] && a[1] === b[1]

/**
 * Whether a path of positions (a closed ring, or the corners placed so far while drawing) has two
 * edges that cross (FieldBoundary.crosses_itself? on the server). Edges that only touch, at a
 * shared corner or end to end in a line, don't count.
 */
export function pathCrossesItself(path: LngLat[]): boolean {
  const closed = path.length > 3 && samePosition(path[0], path[path.length - 1])
  const edges = path.length - 1
  for (let i = 0; i < edges; i++)
    for (let j = i + 2; j < edges; j++) {
      // A ring's first and last edges share its first corner
      if (closed && i === 0 && j === edges - 1) continue
      if (segmentsCross(path[i], path[i + 1], path[j], path[j + 1])) return true
    }
  return false
}

/** The outline as stored: positions rounded to about a centimeter, any altitude dropped */
export function roundBoundary(boundary: Boundary): Boundary {
  const round = (n: number) => Number(n.toFixed(DIGITS))
  return { type: 'Polygon', coordinates: [boundaryRing(boundary).map(([lng, lat]) => [round(lng), round(lat)])] }
}

/** A ring closed (its last position repeating its first) */
export function closeRing(ring: LngLat[]): LngLat[] {
  if (!ring.length || samePosition(ring[0], ring[ring.length - 1])) return ring
  return [...ring, ring[0]]
}

/** Simplify a closed ring by Douglas–Peucker with a tolerance in meters, keeping it closed */
export function simplifyRing(ring: LngLat[], toleranceM: number): LngLat[] {
  if (ring.length <= 4) return ring
  const lat0 = rad(ring[0][1])
  // Plane coordinates in meters around the ring, plenty at a field's scale
  const xy = ring.map(([lng, lat]) => [rad(lng) * Math.cos(lat0) * EARTH_RADIUS_M, rad(lat) * EARTH_RADIUS_M])
  const keep = new Array<boolean>(ring.length).fill(false)
  // A closed ring has no natural ends: split it at its first point and the point farthest from it
  const far = xy.reduce((best, p, i) => (dist2(p, xy[0]) > dist2(xy[best], xy[0]) ? i : best), 0)
  keep[0] = keep[far] = keep[ring.length - 1] = true
  const stack: [number, number][] = [
    [0, far],
    [far, ring.length - 1],
  ]
  while (stack.length) {
    const [start, end] = stack.pop()!
    let index = -1
    let max = toleranceM
    for (let i = start + 1; i < end; i++) {
      const d = segmentDistance(xy[i], xy[start], xy[end])
      if (d > max) {
        max = d
        index = i
      }
    }
    if (index >= 0) {
      keep[index] = true
      stack.push([start, index], [index, end])
    }
  }
  return ring.filter((_, i) => keep[i])
}

const dist2 = (a: number[], b: number[]) => (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2

/**
 * An outline with at most maxVertices corners: unchanged if it fits, else simplified with a
 * tolerance doubled from 0.25 m until it does (keeping at least three corners)
 */
export function simplifyBoundary(boundary: Boundary, maxVertices = MAX_BOUNDARY_VERTICES): Boundary {
  if (vertexCount(boundary) <= maxVertices) return boundary
  for (let tolerance = 0.25; tolerance < 1000; tolerance *= 2) {
    const ring = simplifyRing(boundaryRing(boundary), tolerance)
    if (ring.length < 4) break
    if (ring.length - 1 <= maxVertices) return { type: 'Polygon', coordinates: [ring] }
  }
  return boundary
}

/** [[west, south], [east, north]] around an outline */
export const boundaryBounds = (boundary: Boundary): [LngLat, LngLat] => boundsOf(boundaryRing(boundary))!

/**
 * Where a field's name goes: on the outline's top edge, above its center (boundaryCenter),
 * so it stays clear of the badges there
 */
export function boundaryTop(boundary: Boundary): LngLat {
  const ring = boundaryRing(boundary)
  const center = boundaryCenter(boundary)
  const x = center[0]
  // The northernmost place the outline crosses the center's meridian
  const crossings = ring.slice(1).flatMap((b, i) => {
    const a = ring[i]
    if (a[0] > x === b[0] > x) return []
    return [a[1] + ((x - a[0]) * (b[1] - a[1])) / (b[0] - a[0])]
  })
  return [x, crossings.length ? Math.max(...crossings) : center[1]]
}

/** Whether a point is inside an outline */
export const inBoundary = (point: LngLat, boundary: Boundary) => pointInPolygon(point, boundary.coordinates)

/**
 * A point inside the outline for its label or a pin: its area-weighted centroid, or, when that
 * falls outside (an L or a C), the middle of the widest horizontal run through it
 */
export function boundaryCenter(boundary: Boundary): LngLat {
  const outer = boundaryRing(boundary)
  let cx = 0
  let cy = 0
  let a = 0
  for (let i = 0; i < outer.length - 1; i++) {
    const [x0, y0] = outer[i]
    const [x1, y1] = outer[i + 1]
    const cross = x0 * y1 - x1 * y0
    a += cross
    cx += (x0 + x1) * cross
    cy += (y0 + y1) * cross
  }
  const centroid: LngLat = a ? [cx / (3 * a), cy / (3 * a)] : outer[0]
  if (pointInPolygon(centroid, [outer])) return centroid
  // Across the polygon at the centroid's latitude: the longest stretch inside
  const y = centroid[1]
  const crossings = outer
    .slice(1)
    .flatMap((b, i) => {
      const a = outer[i]
      if (a[1] > y === b[1] > y) return []
      return [a[0] + ((y - a[1]) * (b[0] - a[0])) / (b[1] - a[1])]
    })
    .sort((p, q) => p - q)
  let best: LngLat = outer[0]
  let width = -1
  for (let i = 0; i + 1 < crossings.length; i += 2) {
    if (crossings[i + 1] - crossings[i] > width) {
      width = crossings[i + 1] - crossings[i]
      best = [(crossings[i] + crossings[i + 1]) / 2, y]
    }
  }
  return best
}

/** How far an irrigation group's outline stands off its systems */
export const GROUP_MARGIN_M = 120

/**
 * The outline around an irrigation group's systems and their fields' outlines: the convex hull of
 * their outlines (a point kind's small circle) with a margin, so even a group of one shows around
 * its system
 */
export function groupOutline(shapes: PivotShape[], boundaries: Boundary[] = []): LngLat[] {
  return bufferedHull(
    [...shapes.flatMap((shape) => surveyRing(shape, 24)), ...boundaries.flatMap(boundaryRing)],
    GROUP_MARGIN_M,
    6,
  )
}
