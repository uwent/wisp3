// Pivot geometry for the map. A center pivot is a center, a radius in feet, and optionally an arc
// (start and end bearings in degrees clockwise from north; the pivot sweeps clockwise from start
// to end). A linear move is a machine length_ft long traveling travel_ft along travel_bearing_deg
// (whole degrees from north, 0–179, as it runs both ways): a rectangle centered on its location.
// Spherical-earth math, which is plenty at pivot scale.

export type LngLat = [number, number]

export type PivotKind = 'center' | 'linear'

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

/** A linear move's machine length and travel in feet, and its direction of travel */
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
 * A linear move's corners: front left, front right, back right, back left, facing its direction
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

/** A linear move's irrigated area as a closed ring */
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

/** A linear move's sizes and direction, with the defaults for any missing */
export function linearOf(shape: Pick<PivotShape, 'length_ft' | 'travel_ft' | 'travel_bearing_deg'>): Linear {
  return {
    lengthFt: shape.length_ft ?? DEFAULT_LINEAR.lengthFt,
    travelFt: shape.travel_ft ?? DEFAULT_LINEAR.travelFt,
    bearingDeg: shape.travel_bearing_deg ?? DEFAULT_LINEAR.bearingDeg,
  }
}

/** A pivot's irrigated area as a closed ring: a circle, a sector, or a linear move's rectangle */
export function pivotOutline(shape: PivotShape, steps = 96): LngLat[] {
  const center: LngLat = [shape.longitude, shape.latitude]
  if (shape.kind === 'linear') {
    return linearRing(center, linearOf(shape))
  }
  return pivotRing(center, shape.radius_ft ?? DEFAULT_RADIUS_FT, shape.arc_start_deg, shape.arc_end_deg, steps)
}

/** A pivot's irrigated acres */
export function shapeAcres(shape: Omit<PivotShape, 'latitude' | 'longitude'>): number {
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
  const arc = !linear && draft.partial && draft.arcStart !== null && draft.arcEnd !== null
  return {
    kind: draft.kind,
    latitude: draft.latitude,
    longitude: draft.longitude,
    radius_ft: linear ? null : draft.radiusFt,
    arc_start_deg: arc ? draft.arcStart : null,
    arc_end_deg: arc ? draft.arcEnd : null,
    length_ft: linear ? draft.lengthFt : null,
    travel_ft: linear ? draft.travelFt : null,
    travel_bearing_deg: linear ? draft.travelBearing : null,
  }
}
