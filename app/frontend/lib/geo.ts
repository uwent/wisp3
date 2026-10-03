// Pivot geometry for the map: a pivot is a center, a radius in feet, and optionally an arc
// (start and end bearings in degrees clockwise from north; the pivot sweeps clockwise from start
// to end). Spherical-earth math, which is plenty at pivot scale.

export type LngLat = [number, number]

const EARTH_RADIUS_M = 6_371_008.8
export const FEET_PER_METER = 3.28084
/** A quarter-section (160 acre) pivot */
export const DEFAULT_RADIUS_FT = 1300

const rad = (deg: number) => (deg * Math.PI) / 180
const deg = (rad: number) => (rad * 180) / Math.PI

/** The point distanceM from [lng, lat] along a bearing */
export function destination([lng, lat]: LngLat, distanceM: number, bearingDeg: number): LngLat {
  const d = distanceM / EARTH_RADIUS_M
  const b = rad(bearingDeg)
  const lat1 = rad(lat)
  const lat2 = Math.asin(Math.sin(lat1) * Math.cos(d) + Math.cos(lat1) * Math.sin(d) * Math.cos(b))
  const lng2 = rad(lng) + Math.atan2(Math.sin(b) * Math.sin(d) * Math.cos(lat1), Math.cos(d) - Math.sin(lat1) * Math.sin(lat2))
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
  const x = Math.cos(rad(lat1)) * Math.sin(rad(lat2)) - Math.sin(rad(lat1)) * Math.cos(rad(lat2)) * Math.cos(rad(lng2 - lng1))
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
