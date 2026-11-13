// Pivot geometry for the map. A center pivot is a center, a radius in feet, and optionally an arc
// (start and end bearings in degrees clockwise from north; the pivot sweeps clockwise from start
// to end). A linear is a machine length_ft long traveling travel_ft along travel_bearing_deg
// (whole degrees from north, 0–179, as it runs both ways): a rectangle centered on its location.
// The other kinds (a traveler, solid set, drip, or a location only; Pivot::POINT_KINDS) are a
// point with no outline. Spherical-earth math, which is plenty at pivot scale.

export type LngLat = [number, number]

/** An irrigation system's kind (Pivot::KINDS); "pivot" in code is any of them */
export type PivotKind = 'center' | 'linear' | 'traveler' | 'solid_set' | 'drip' | 'point'

/** What growers call each kind (Pivot::KIND_NAMES; the server sends it as kind_name) */
export const KIND_NAMES: Record<PivotKind, string> = {
  center: 'Pivot',
  linear: 'Linear',
  traveler: 'Traveler',
  solid_set: 'Solid set',
  drip: 'Drip',
  point: 'Location',
}

/** The kind in a sentence: "place the drip block" */
export const KIND_NOUNS: Record<PivotKind, string> = {
  center: 'pivot',
  linear: 'linear',
  traveler: 'traveler',
  solid_set: 'solid set block',
  drip: 'drip block',
  point: 'location',
}

/**
 * How a system is named to growers (G.14, Pivot#label): "East gun (traveler)", or the name alone
 * when it already says its kind ("Home pivot"). Pages put "Irrigation system:" (or "System:" where
 * space is short) before it, never the kind.
 */
export function systemName(system: { name: string; kind_name: string }): string {
  const kind = system.kind_name.toLowerCase()
  return system.name.toLowerCase().includes(kind) ? system.name : `${system.name} (${kind})`
}

/** Kinds that are a point with no dimensions (Pivot::POINT_KINDS) */
export const isPoint = (kind: PivotKind) => kind !== 'center' && kind !== 'linear'

/** What a pivot covers, as the server sends it (PivotSerializer::SHAPE) */
export type PivotShape = {
  kind: PivotKind
  latitude: number
  longitude: number
  radius_ft: number | null
  arc_start_deg: number | null
  arc_end_deg: number | null
  length_ft: number | null
  travel_ft: number | null
  travel_bearing_deg: number | null
}

/** A linear's machine length and travel in feet, and its direction of travel */
export type Linear = { lengthFt: number; travelFt: number; bearingDeg: number }

const EARTH_RADIUS_M = 6_371_008.8
export const FEET_PER_METER = 3.28084
/** A quarter-section (160 acre) pivot */
export const DEFAULT_RADIUS_FT = 1300
/** A quarter-mile machine traveling half a mile north and south (about 80 acres) */
export const DEFAULT_LINEAR: Linear = { lengthFt: 1300, travelFt: 2640, bearingDeg: 0 }
/** The smallest radius or side the picker's handles allow */
export const MIN_SIZE_FT = 50
// The largest pivots (Pivot::MAX_RADIUS_FT and friends): a center pivot's radius, a linear
// machine's length and how far it travels
export const MAX_RADIUS_FT = 3000
export const MAX_LINEAR_LENGTH_FT = 3300
export const MAX_LINEAR_TRAVEL_FT = 5280
/** A linear's direction snaps to north–south or east–west within this many degrees */
export const SNAP_DEG = 2

const rad = (deg: number) => (deg * Math.PI) / 180
const deg = (rad: number) => (rad * 180) / Math.PI

/** The point distanceM from [lng, lat] along a bearing */
export function destination([lng, lat]: LngLat, distanceM: number, bearingDeg: number): LngLat {
  const d = distanceM / EARTH_RADIUS_M
  const b = rad(bearingDeg)
  const lat1 = rad(lat)
  const lat2 = Math.asin(Math.sin(lat1) * Math.cos(d) + Math.cos(lat1) * Math.sin(d) * Math.cos(b))
  const lng2 =
    rad(lng) + Math.atan2(Math.sin(b) * Math.sin(d) * Math.cos(lat1), Math.cos(d) - Math.sin(lat1) * Math.sin(lat2))
  return [deg(lng2), deg(lat2)]
}

export function distanceM([lng1, lat1]: LngLat, [lng2, lat2]: LngLat): number {
  const dLat = rad(lat2 - lat1)
  const dLng = rad(lng2 - lng1)
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(a))
}

/** Bearing from the first point to the second, 0–360 clockwise from north */
export function bearing([lng1, lat1]: LngLat, [lng2, lat2]: LngLat): number {
  const y = Math.sin(rad(lng2 - lng1)) * Math.cos(rad(lat2))
  const x =
    Math.cos(rad(lat1)) * Math.sin(rad(lat2)) - Math.sin(rad(lat1)) * Math.cos(rad(lat2)) * Math.cos(rad(lng2 - lng1))
  return (deg(Math.atan2(y, x)) + 360) % 360
}

/** Degrees swept clockwise from start to end (a full circle when there's no arc) */
export function sweep(arcStart: number | null, arcEnd: number | null): number {
  if (arcStart === null || arcEnd === null) return 360
  const swept = (((arcEnd - arcStart) % 360) + 360) % 360
  return swept === 0 ? 360 : swept
}

/** The pivot's irrigated area as a closed polygon ring: a circle, or a sector for an arc */
export function pivotRing(
  center: LngLat,
  radiusFt: number,
  arcStart: number | null = null,
  arcEnd: number | null = null,
  steps = 96,
): LngLat[] {
  const radiusM = radiusFt / FEET_PER_METER
  const swept = sweep(arcStart, arcEnd)
  const start = swept === 360 ? 0 : (arcStart ?? 0)
  const count = Math.max(8, Math.ceil((steps * swept) / 360))
  const edge = Array.from({ length: count + 1 }, (_, i) => destination(center, radiusM, start + (swept * i) / count))
  const ring = swept === 360 ? edge.slice(0, -1) : [center, ...edge]
  return [...ring, ring[0]]
}

/** Irrigated acres for a radius and arc (the full circle is π r²) */
export function pivotAcres(radiusFt: number, arcStart: number | null = null, arcEnd: number | null = null): number {
  return ((Math.PI * radiusFt ** 2) / 43_560) * (sweep(arcStart, arcEnd) / 360)
}

/** The point alongM meters in a direction and acrossM meters to its right (either can be negative) */
export function offset(point: LngLat, alongM: number, acrossM: number, bearingDeg: number): LngLat {
  const along = destination(point, Math.abs(alongM), bearingDeg + (alongM < 0 ? 180 : 0))
  return destination(along, Math.abs(acrossM), bearingDeg + 90 + (acrossM < 0 ? 180 : 0))
}

/**
 * A linear's corners: front left, front right, back right, back left, facing its direction
 * of travel (for a linear traveling north: northwest, northeast, southeast, southwest)
 */
export function linearCorners(center: LngLat, { lengthFt, travelFt, bearingDeg }: Linear): LngLat[] {
  const along = travelFt / FEET_PER_METER / 2
  const across = lengthFt / FEET_PER_METER / 2
  return [
    offset(center, along, -across, bearingDeg),
    offset(center, along, across, bearingDeg),
    offset(center, -along, across, bearingDeg),
    offset(center, -along, -across, bearingDeg),
  ]
}

/** A linear's irrigated area as a closed ring */
export function linearRing(center: LngLat, linear: Linear): LngLat[] {
  const corners = linearCorners(center, linear)
  return [...corners, corners[0]]
}

const clamp = (value: number, max: number) => Math.min(Math.max(value, MIN_SIZE_FT), max)

/**
 * The linear with its front left corner dragged to a point and its back right one fixed (or the
 * other way round), keeping its direction and a machine's size: its center and sizes in feet. A
 * corner can't be dragged past the opposite one.
 */
export function resizeLinear(
  fixed: LngLat,
  dragged: LngLat,
  bearingDeg: number,
  corner: 'frontLeft' | 'backRight',
): { center: LngLat; lengthFt: number; travelFt: number } {
  const distance = distanceM(fixed, dragged)
  const angle = rad(bearing(fixed, dragged) - bearingDeg)
  const sign = corner === 'frontLeft' ? 1 : -1
  const travelFt = clamp(sign * distance * Math.cos(angle) * FEET_PER_METER, MAX_LINEAR_TRAVEL_FT)
  const lengthFt = clamp(-sign * distance * Math.sin(angle) * FEET_PER_METER, MAX_LINEAR_LENGTH_FT)
  const center = offset(
    fixed,
    (sign * travelFt) / FEET_PER_METER / 2,
    (-sign * lengthFt) / FEET_PER_METER / 2,
    bearingDeg,
  )
  return { center, lengthFt, travelFt }
}

/**
 * A double-ended arrow along a linear's travel through its center, spanning a share of the travel,
 * as polylines: the shaft and each end's head
 */
export function travelArrow(center: LngLat, { lengthFt, travelFt, bearingDeg }: Linear, share = 0.8): LngLat[][] {
  const halfM = (travelFt * share) / FEET_PER_METER / 2
  // The heads stay a sensible size on long, narrow and small linears alike
  const headM = Math.min(halfM * 0.25, (lengthFt / FEET_PER_METER) * 0.15, 60)
  const ends = [offset(center, halfM, 0, bearingDeg), offset(center, -halfM, 0, bearingDeg)]
  const head = (tip: LngLat, pointing: number) => [
    destination(tip, headM, pointing + 150),
    tip,
    destination(tip, headM, pointing - 150),
  ]
  return [ends, head(ends[0], bearingDeg), head(ends[1], bearingDeg + 180)]
}

/** A direction of travel in whole degrees, 0–179, snapped to north–south or east–west when close */
export function snapBearing(degrees: number): number {
  const half = ((degrees % 180) + 180) % 180
  const cardinal = [0, 90, 180].find((c) => Math.abs(half - c) <= SNAP_DEG)
  return cardinal !== undefined ? cardinal % 180 : Math.round(half) % 180
}

/** A linear's sizes and direction, with the defaults for any missing */
export function linearOf(shape: Pick<PivotShape, 'length_ft' | 'travel_ft' | 'travel_bearing_deg'>): Linear {
  return {
    lengthFt: shape.length_ft ?? DEFAULT_LINEAR.lengthFt,
    travelFt: shape.travel_ft ?? DEFAULT_LINEAR.travelFt,
    bearingDeg: shape.travel_bearing_deg ?? DEFAULT_LINEAR.bearingDeg,
  }
}

/**
 * A pivot's irrigated area as a closed ring: a circle, a sector, or a linear's rectangle; null
 * for a point kind, which has no outline
 */
export function pivotOutline(shape: PivotShape, steps = 96): LngLat[] | null {
  if (isPoint(shape.kind)) return null
  const center: LngLat = [shape.longitude, shape.latitude]
  if (shape.kind === 'linear') {
    return linearRing(center, linearOf(shape))
  }
  return pivotRing(center, shape.radius_ft ?? DEFAULT_RADIUS_FT, shape.arc_start_deg, shape.arc_end_deg, steps)
}

/** How far around a point kind the soil survey is read: a circle about 100 m across */
export const POINT_SURVEY_RADIUS_FT = 165

/** The ring the soil survey is read in: the outline, or a small circle around a point kind */
export function surveyRing(shape: PivotShape, steps = 48): LngLat[] {
  return (
    pivotOutline(shape, steps) ??
    pivotRing([shape.longitude, shape.latitude], POINT_SURVEY_RADIUS_FT, null, null, steps)
  )
}

/** A pivot's irrigated acres; null for a point kind, whose area comes from its fields */
export function shapeAcres(shape: Omit<PivotShape, 'latitude' | 'longitude'>): number | null {
  if (isPoint(shape.kind)) return null
  if (shape.kind === 'linear') {
    const { lengthFt, travelFt } = linearOf(shape)
    return (lengthFt * travelFt) / 43_560
  }
  return pivotAcres(shape.radius_ft ?? DEFAULT_RADIUS_FT, shape.arc_start_deg, shape.arc_end_deg)
}

/**
 * Where to put an arrow pointing at an off-screen point: on the edge of a width × height box
 * (inset by margin), along the line from the box's center toward the point, with the arrow's angle
 * in degrees (0 = pointing right, clockwise, as in screen coordinates). null if the point is visible.
 */
export function edgePointer(
  point: { x: number; y: number },
  width: number,
  height: number,
  margin = 24,
): { x: number; y: number; angle: number } | null {
  if (point.x >= 0 && point.x <= width && point.y >= 0 && point.y <= height) return null
  const cx = width / 2
  const cy = height / 2
  const dx = point.x - cx
  const dy = point.y - cy
  const scale = Math.min(Math.abs((cx - margin) / dx) || Infinity, Math.abs((cy - margin) / dy) || Infinity)
  return { x: cx + dx * scale, y: cy + dy * scale, angle: (Math.atan2(dy, dx) * 180) / Math.PI }
}

/** Whether a point is inside a polygon (its outer ring, and none of its holes), by ray casting */
export function pointInPolygon(point: LngLat, polygon: LngLat[][]): boolean {
  const [outer, ...holes] = polygon
  return !!outer && inRing(point, outer) && !holes.some((hole) => inRing(point, hole))
}

function inRing([x, y]: LngLat, ring: LngLat[]): boolean {
  let inside = false
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i]
    const [xj, yj] = ring[j]
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside
  }
  return inside
}

/**
 * A pivot's shape while the form edits it. Both kinds' sizes and the arc are kept while editing,
 * so switching kinds or turning the arc off and on gives back what was there.
 */
export type ShapeDraft = {
  kind: PivotKind
  latitude: number | null
  longitude: number | null
  radiusFt: number | null
  partial: boolean
  arcStart: number | null
  arcEnd: number | null
  lengthFt: number | null
  travelFt: number | null
  travelBearing: number | null
}

export function shapeDraft(pivot: Partial<PivotShape> = {}): ShapeDraft {
  return {
    kind: pivot.kind ?? 'center',
    latitude: pivot.latitude ?? null,
    longitude: pivot.longitude ?? null,
    radiusFt: pivot.radius_ft ?? DEFAULT_RADIUS_FT,
    partial: pivot.arc_start_deg != null && pivot.arc_end_deg != null,
    arcStart: pivot.arc_start_deg ?? 0,
    arcEnd: pivot.arc_end_deg ?? 270,
    lengthFt: pivot.length_ft ?? DEFAULT_LINEAR.lengthFt,
    travelFt: pivot.travel_ft ?? DEFAULT_LINEAR.travelFt,
    travelBearing: pivot.travel_bearing_deg ?? DEFAULT_LINEAR.bearingDeg,
  }
}

/** The shape a draft describes, or null until it has a location */
export function draftShape(draft: ShapeDraft): PivotShape | null {
  if (draft.latitude === null || draft.longitude === null) return null
  const linear = draft.kind === 'linear'
  const center = draft.kind === 'center'
  const arc = center && draft.partial && draft.arcStart !== null && draft.arcEnd !== null
  return {
    kind: draft.kind,
    latitude: draft.latitude,
    longitude: draft.longitude,
    radius_ft: center ? draft.radiusFt : null,
    arc_start_deg: arc ? draft.arcStart : null,
    arc_end_deg: arc ? draft.arcEnd : null,
    length_ft: linear ? draft.lengthFt : null,
    travel_ft: linear ? draft.travelFt : null,
    travel_bearing_deg: linear ? draft.travelBearing : null,
  }
}

/**
 * The convex hull of points as a closed ring, counterclockwise (Andrew's monotone chain, treating
 * longitude and latitude as plane coordinates, which is plenty across a farm). Fewer than three
 * distinct points give what there is.
 */
export function convexHull(points: LngLat[]): LngLat[] {
  const sorted = [...points].sort(([ax, ay], [bx, by]) => ax - bx || ay - by)
  const cross = (o: LngLat, a: LngLat, b: LngLat) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
  const half = (list: LngLat[]) => {
    const chain: LngLat[] = []
    for (const point of list) {
      while (chain.length >= 2 && cross(chain[chain.length - 2], chain[chain.length - 1], point) <= 0) chain.pop()
      chain.push(point)
    }
    chain.pop()
    return chain
  }
  const hull = [...half(sorted), ...half([...sorted].reverse())]
  return hull.length ? [...hull, hull[0]] : []
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

/**
 * The convex hull around points with a margin (meters), rounded at its corners: each of the hull's
 * corners pushed out in `directions` directions (the hull first: far fewer corners than an outline)
 */
export function bufferedHull(points: LngLat[], marginM: number, directions = 12): LngLat[] {
  return convexHull(
    convexHull(points).flatMap((vertex) =>
      Array.from({ length: directions }, (_, i) => destination(vertex, marginM, (360 * i) / directions)),
    ),
  )
}

// A field's outline (PLAN.md Phase 8 G.10, G.14; FieldBoundary on the server): a GeoJSON Polygon
// with one ring (no holes, no parts) in longitude and latitude, for the map and the suggested area only

export type Boundary = { type: 'Polygon'; coordinates: [LngLat[]] }

// FieldBoundary's limits: corners in the outline, and its area in acres
export const MAX_BOUNDARY_VERTICES = 1000
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
  const acres = boundaryAcres(boundary)
  if (acres < MIN_FIELD_ACRES) errors.push(`is too small (at least ${MIN_FIELD_ACRES} acres)`)
  if (acres > MAX_FIELD_ACRES)
    errors.push(`is larger than a field (at most ${MAX_FIELD_ACRES.toLocaleString('en-US')} acres)`)
  return errors
}

const samePosition = (a: LngLat, b: LngLat) => a[0] === b[0] && a[1] === b[1]

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
    let max = toleranceM * toleranceM
    for (let i = start + 1; i < end; i++) {
      const d = segmentDist2(xy[i], xy[start], xy[end])
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

function segmentDist2(p: number[], a: number[], b: number[]): number {
  const length2 = dist2(a, b)
  if (length2 === 0) return dist2(p, a)
  const t = Math.max(0, Math.min(1, ((p[0] - a[0]) * (b[0] - a[0]) + (p[1] - a[1]) * (b[1] - a[1])) / length2))
  return dist2(p, [a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])])
}

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
export function boundaryBounds(boundary: Boundary): [LngLat, LngLat] {
  const points = boundaryRing(boundary)
  const lngs = points.map(([lng]) => lng)
  const lats = points.map(([, lat]) => lat)
  return [
    [Math.min(...lngs), Math.min(...lats)],
    [Math.max(...lngs), Math.max(...lats)],
  ]
}

/**
 * Where a field's name goes (G.14): on the outline's top edge, above its center (boundaryCenter),
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
