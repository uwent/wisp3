import { describe, expect, it } from 'vitest'

import {
  bearing,
  destination,
  distanceM,
  draftShape,
  edgePointer,
  linearCorners,
  MAX_LINEAR_LENGTH_FT,
  MAX_LINEAR_TRAVEL_FT,
  pivotAcres,
  pivotOutline,
  pivotRing,
  pointInPolygon,
  resizeLinear,
  shapeAcres,
  shapeDraft,
  snapBearing,
  sweep,
  travelArrow,
  type LngLat,
} from './geo'

const center: LngLat = [-89.5213, 44.1335]

describe('geo', () => {
  it('finds the point at a distance and bearing, and back', () => {
    const east = destination(center, 400, 90)
    expect(distanceM(center, east)).toBeCloseTo(400, 3)
    expect(bearing(center, east)).toBeCloseTo(90, 1)
    expect(destination(center, 400, 0)[1]).toBeGreaterThan(center[1])
  })

  it('measures the sweep of an arc clockwise, wrapping through north', () => {
    expect(sweep(null, null)).toBe(360)
    expect(sweep(30, 300)).toBe(270)
    expect(sweep(300, 30)).toBe(90)
    expect(sweep(90, 90)).toBe(360)
  })

  it('draws a closed circle at the radius', () => {
    const ring = pivotRing(center, 1300)
    expect(ring[0]).toEqual(ring[ring.length - 1])
    for (const point of ring) expect(distanceM(center, point)).toBeCloseTo(1300 / 3.28084, 1)
  })

  it('draws an arc as a sector through the center', () => {
    const ring = pivotRing(center, 1300, 0, 90)
    expect(ring[0]).toEqual(center)
    expect(ring[ring.length - 1]).toEqual(center)
    expect(bearing(center, ring[1])).toBeCloseTo(0, 1)
    expect(bearing(center, ring[ring.length - 2])).toBeCloseTo(90, 1)
  })

  it('computes irrigated acres', () => {
    expect(pivotAcres(1300)).toBeCloseTo(121.9, 1)
    expect(pivotAcres(1300, 0, 180)).toBeCloseTo(60.9, 1)
  })
})

describe('linear moves', () => {
  const feet = (a: LngLat, b: LngLat) => distanceM(a, b) * 3.28084

  const north = { lengthFt: 1300, travelFt: 2640, bearingDeg: 0 }

  it('places its corners around the center, facing its direction of travel', () => {
    const [frontLeft, frontRight, backRight, backLeft] = linearCorners(center, north)
    expect(feet(frontLeft, frontRight)).toBeCloseTo(1300, 0) // the machine
    expect(feet(frontRight, backRight)).toBeCloseTo(2640, 0) // its travel
    expect(frontLeft[1]).toBeGreaterThan(center[1]) // front left is northwest
    expect(frontLeft[0]).toBeLessThan(center[0])
    expect(
      distanceM(destination(frontLeft, distanceM(frontLeft, backRight) / 2, bearing(frontLeft, backRight)), center),
    ).toBeLessThan(1)
    expect(backLeft[0]).toBeCloseTo(frontLeft[0], 5) // a north–south side, to within centimeters
  })

  it('turns with its direction of travel', () => {
    const [frontLeft, frontRight, backRight] = linearCorners(center, { ...north, bearingDeg: 30 })
    expect(bearing(frontRight, frontLeft)).toBeCloseTo(300, 0) // the machine lies across the travel
    expect(bearing(backRight, frontRight)).toBeCloseTo(30, 0)
    expect(feet(frontLeft, frontRight)).toBeCloseTo(1300, 0)
    expect(feet(frontRight, backRight)).toBeCloseTo(2640, 0)
  })

  it('follows a dragged corner in its own frame, keeping the opposite corner and its direction', () => {
    const turned = { ...north, bearingDeg: 30 }
    const [frontLeft, , backRight] = linearCorners(center, turned)
    const moved = resizeLinear(backRight, frontLeft, 30, 'frontLeft')
    expect(moved.lengthFt).toBeCloseTo(1300, 0)
    expect(moved.travelFt).toBeCloseTo(2640, 0)
    expect(distanceM(moved.center, center)).toBeLessThan(1)
    const back = resizeLinear(frontLeft, backRight, 30, 'backRight')
    expect(distanceM(back.center, center)).toBeLessThan(1)
    // Dragging the front left corner 100 m further along the travel lengthens only the travel
    const further = resizeLinear(backRight, destination(frontLeft, 100, 30), 30, 'frontLeft')
    expect(further.travelFt).toBeCloseTo(2640 + 328.084, 0)
    expect(further.lengthFt).toBeCloseTo(1300, 0)
  })

  it("keeps a machine's size, and can't cross the opposite corner", () => {
    const [, , backRight] = linearCorners(center, north)
    const huge = resizeLinear(backRight, destination(backRight, 5000, 315), 0, 'frontLeft')
    expect(huge.lengthFt).toBe(MAX_LINEAR_LENGTH_FT)
    expect(huge.travelFt).toBe(MAX_LINEAR_TRAVEL_FT)
    const crossed = resizeLinear(backRight, destination(backRight, 200, 135), 0, 'frontLeft')
    expect([crossed.lengthFt, crossed.travelFt]).toEqual([50, 50])
  })

  it('snaps its direction to whole degrees from 0 to 179, and to north–south or east–west when close', () => {
    expect(snapBearing(30.4)).toBe(30)
    expect(snapBearing(210)).toBe(30)
    expect(snapBearing(1.5)).toBe(0)
    expect(snapBearing(358.5)).toBe(0)
    expect(snapBearing(178.5)).toBe(0)
    expect(snapBearing(91.9)).toBe(90)
    expect(snapBearing(272)).toBe(90)
    expect(snapBearing(3)).toBe(3)
    expect(snapBearing(179.4)).toBe(0)
  })

  it('draws a double-ended arrow along its travel, 80% of its length', () => {
    const [shaft, front, back] = travelArrow(center, { ...north, bearingDeg: 30 })
    expect(feet(shaft[0], shaft[1])).toBeCloseTo(2640 * 0.8, 0)
    expect(bearing(shaft[1], shaft[0])).toBeCloseTo(30, 0)
    expect(front[1]).toEqual(shaft[0]) // each head's tip is an end of the shaft
    expect(back[1]).toEqual(shaft[1])
    expect(distanceM(front[0], front[1])).toBeLessThanOrEqual(60) // capped for a large linear
    expect(bearing(front[1], front[0])).toBeCloseTo(180, 0) // swept back from the tip
  })

  it('outlines and measures either kind', () => {
    const linear = draftShape(shapeDraft({ latitude: center[1], longitude: center[0], kind: 'linear' }))!
    expect(pivotOutline(linear)).toHaveLength(5)
    expect(shapeAcres(linear)).toBeCloseTo((1300 * 2640) / 43_560, 6)
    const arc = draftShape({ ...shapeDraft({ latitude: center[1], longitude: center[0] }), partial: true })!
    expect(arc).toMatchObject({
      kind: 'center',
      radius_ft: 1300,
      arc_start_deg: 0,
      arc_end_deg: 270,
      length_ft: null,
      travel_bearing_deg: null,
    })
    expect(shapeAcres(arc)).toBeCloseTo(pivotAcres(1300) * 0.75, 6)
  })

  it('drafts a shape without a location as nothing to draw', () => {
    expect(draftShape(shapeDraft())).toBeNull()
  })
})

describe('edgePointer', () => {
  it('is null for a visible point', () => {
    expect(edgePointer({ x: 50, y: 50 }, 400, 300)).toBeNull()
  })

  it('points along the edge toward an off-screen point', () => {
    expect(edgePointer({ x: 1000, y: 150 }, 400, 300)).toEqual({ x: 376, y: 150, angle: 0 })
    const above = edgePointer({ x: 200, y: -500 }, 400, 300)!
    expect([above.x, above.y, above.angle].map((n) => Math.round(n))).toEqual([200, 24, -90])
    const corner = edgePointer({ x: -1000, y: 1350 }, 400, 300)! // down and left at 45°
    expect(corner.y).toBeCloseTo(276)
    expect(corner.angle).toBeCloseTo(135)
  })

  it('finds a point inside a polygon but not in its hole', () => {
    const square = (min: number, max: number): LngLat[] => [
      [min, min],
      [max, min],
      [max, max],
      [min, max],
      [min, min],
    ]
    expect(pointInPolygon([5, 5], [square(0, 10)])).toBe(true)
    expect(pointInPolygon([11, 5], [square(0, 10)])).toBe(false)
    expect(pointInPolygon([5, 5], [square(0, 10), square(4, 6)])).toBe(false)
    expect(pointInPolygon([2, 2], [square(0, 10), square(4, 6)])).toBe(true)
  })
})
