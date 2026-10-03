import { describe, expect, it } from 'vitest'

import { bearing, destination, distanceM, edgePointer, pivotAcres, pivotRing, sweep, type LngLat } from './geo'

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
})
