// Irrigation system geometry for the map. A center pivot is a center, a radius in feet, and optionally an arc
// (start and end bearings in degrees clockwise from north; the pivot sweeps clockwise from start
// to end). A linear is a machine length_ft long traveling travel_ft along travel_bearing_deg
// (whole degrees from north, 0–179, as it runs both ways): a rectangle centered on its location.
// The other kinds (a traveler, solid set, drip, or a location only; IrrigationSystem::POINT_KINDS) are a
// point with no outline. Spherical-earth math, which is plenty at pivot scale.

export type LngLat = [number, number]

/** An irrigation system's kind (IrrigationSystem::KINDS); "system" in code is any of them */
export type SystemKind = 'center' | 'linear' | 'traveler' | 'solid_set' | 'drip' | 'point'

/** What growers call each kind (IrrigationSystem::KIND_NAMES; the server sends it as kind_name) */
export const KIND_NAMES: Record<SystemKind, string> = {
  center: 'Pivot',
  linear: 'Linear',
  traveler: 'Traveler',
  solid_set: 'Solid set',
  drip: 'Drip',
  point: 'Location',
}

/** The kind in a sentence: "place the drip block" */
export const KIND_NOUNS: Record<SystemKind, string> = {
  center: 'pivot',
  linear: 'linear',
  traveler: 'traveler',
  solid_set: 'solid set block',
  drip: 'drip block',
  point: 'location',
}

/**
 * How a system is named to growers (IrrigationSystem#label): "East gun (traveler)", or the name alone
 * when it already says its kind ("Home pivot"). Pages put "Irrigation system:" (or "System:" where
 * space is short) before it, never the kind.
 */
export function systemName(system: { name: string; kind_name: string }): string {
  const kind = system.kind_name.toLowerCase()
  return system.name.toLowerCase().includes(kind) ? system.name : `${system.name} (${kind})`
}

/** Kinds that are a point with no dimensions (IrrigationSystem::POINT_KINDS) */
export const isPoint = (kind: SystemKind) => kind !== 'center' && kind !== 'linear'

/** What a system covers, as the server sends it (IrrigationSystemSerializer::SHAPE) */
export type SystemShape = {
  kind: SystemKind
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

export const EARTH_RADIUS_M = 6_371_008.8
export const FEET_PER_METER = 3.28084
/** A quarter-section (160 acre) system */
export const DEFAULT_RADIUS_FT = 1300
/** A quarter-mile machine traveling half a mile north and south (about 80 acres) */
export const DEFAULT_LINEAR: Linear = { lengthFt: 1300, travelFt: 2640, bearingDeg: 0 }
/** The smallest radius or side the picker's handles allow */
export const MIN_SIZE_FT = 50
// The largest systems (IrrigationSystem::MAX_RADIUS_FT and friends): a center pivot's radius, a linear
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

/** The system's irrigated area as a closed polygon ring: a circle, or a sector for an arc */
export function systemRing(
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
export function systemAcres(radiusFt: number, arcStart: number | null = null, arcEnd: number | null = null): number {
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
function linearRing(center: LngLat, linear: Linear): LngLat[] {
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
export function linearOf(shape: Pick<SystemShape, 'length_ft' | 'travel_ft' | 'travel_bearing_deg'>): Linear {
  return {
    lengthFt: shape.length_ft ?? DEFAULT_LINEAR.lengthFt,
    travelFt: shape.travel_ft ?? DEFAULT_LINEAR.travelFt,
    bearingDeg: shape.travel_bearing_deg ?? DEFAULT_LINEAR.bearingDeg,
  }
}

/**
 * A system's irrigated area as a closed ring: a circle, a sector, or a linear's rectangle; null
 * for a point kind, which has no outline
 */
export function shapeOutline(shape: SystemShape, steps = 96): LngLat[] | null {
  if (isPoint(shape.kind)) return null
  const center: LngLat = [shape.longitude, shape.latitude]
  if (shape.kind === 'linear') {
    return linearRing(center, linearOf(shape))
  }
  return systemRing(center, shape.radius_ft ?? DEFAULT_RADIUS_FT, shape.arc_start_deg, shape.arc_end_deg, steps)
}

/**
 * The area systems cover, [[west, south], [east, north]]: their shapes (a point kind's location) and
 * their fields' outlines' extents; null for none (the system picker opens on a farm's, Systems/Form)
 */
export function systemsFrame(systems: (SystemShape & { fields_extent?: [LngLat, LngLat] | null })[]) {
  return boundsOf(
    systems.flatMap((system) => [
      ...(shapeOutline(system) ?? [[system.longitude, system.latitude] as LngLat]),
      ...(system.fields_extent ?? []),
    ]),
  )
}

/** How far around a point kind the soil survey is read: a circle about 100 m across */
export const POINT_SURVEY_RADIUS_FT = 165

/** The ring the soil survey is read in: the outline, or a small circle around a point kind */
export function surveyRing(shape: SystemShape, steps = 48): LngLat[] {
  return (
    shapeOutline(shape, steps) ??
    systemRing([shape.longitude, shape.latitude], POINT_SURVEY_RADIUS_FT, null, null, steps)
  )
}

/** A system's irrigated acres; null for a point kind, whose area comes from its fields */
export function shapeAcres(shape: Omit<SystemShape, 'latitude' | 'longitude'>): number | null {
  if (isPoint(shape.kind)) return null
  if (shape.kind === 'linear') {
    const { lengthFt, travelFt } = linearOf(shape)
    return (lengthFt * travelFt) / 43_560
  }
  return systemAcres(shape.radius_ft ?? DEFAULT_RADIUS_FT, shape.arc_start_deg, shape.arc_end_deg)
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
 * A system's shape while the form edits it. Both kinds' sizes and the arc are kept while editing,
 * so switching kinds or turning the arc off and on gives back what was there.
 */
export type ShapeDraft = {
  kind: SystemKind
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

export function shapeDraft(system: Partial<SystemShape> = {}): ShapeDraft {
  return {
    kind: system.kind ?? 'center',
    latitude: system.latitude ?? null,
    longitude: system.longitude ?? null,
    radiusFt: system.radius_ft ?? DEFAULT_RADIUS_FT,
    partial: system.arc_start_deg != null && system.arc_end_deg != null,
    arcStart: system.arc_start_deg ?? 0,
    arcEnd: system.arc_end_deg ?? 270,
    lengthFt: system.length_ft ?? DEFAULT_LINEAR.lengthFt,
    travelFt: system.travel_ft ?? DEFAULT_LINEAR.travelFt,
    travelBearing: system.travel_bearing_deg ?? DEFAULT_LINEAR.bearingDeg,
  }
}

/** The shape a draft describes, or null until it has a location */
export function draftShape(draft: ShapeDraft): SystemShape | null {
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

/** The southwest and northeast corners around points, or null for none */
export function boundsOf(points: LngLat[]): [LngLat, LngLat] | null {
  if (!points.length) return null
  const lngs = points.map(([lng]) => lng)
  const lats = points.map(([, lat]) => lat)
  return [
    [Math.min(...lngs), Math.min(...lats)],
    [Math.max(...lngs), Math.max(...lats)],
  ]
}

/**
 * The convex hull of points as a closed ring, counterclockwise (Andrew's monotone chain, treating
 * longitude and latitude as plane coordinates, which is plenty across a farm). One point gives
 * none, two the line between them and back.
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
