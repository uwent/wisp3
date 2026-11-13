import { describe, expect, it } from 'vitest'

import type { Boundary, LngLat, PivotShape } from '@/lib/geo'

import {
  distanceToBoundaryM,
  formatReach,
  nearestOnSegment,
  outlineProblems,
  reachLine,
  systemDistanceM,
  systemsNear,
  touchesSystem,
} from './problems'

const square = (lng: number, lat: number, size = 0.004): Boundary => ({
  type: 'Polygon',
  coordinates: [
    [
      [lng, lat],
      [lng + size, lat],
      [lng + size, lat + size],
      [lng, lat + size],
      [lng, lat],
    ] as LngLat[],
  ],
})

const system = (kind: PivotShape['kind'], longitude: number, latitude: number) => ({
  name: 'Lane 3',
  kind,
  longitude,
  latitude,
  radius_ft: kind === 'center' ? 1300 : null,
  arc_start_deg: null,
  arc_end_deg: null,
  length_ft: null,
  travel_ft: null,
  travel_bearing_deg: null,
})

describe('outlines to check', () => {
  it('passes a field under its pivot, even one reaching past its circle', () => {
    const pivot = system('center', -89.5, 44.1)
    const fields = [
      { id: 1, name: 'Half', boundary: square(-89.502, 44.099) },
      { id: 2, name: 'Corner', boundary: square(-89.497, 44.1015, 0.01) }, // overlaps the circle's edge
      { id: 3, name: 'None', boundary: null },
    ]
    expect(outlineProblems(pivot, fields, 'imperial')).toEqual([])
  })

  it("lists a field that isn't under its pivot, with how far", () => {
    const pivot = { ...system('center', -89.5, 44.1), name: 'North 160' }
    expect(outlineProblems(pivot, [{ id: 1, name: 'Home North', boundary: square(-89.45, 44.1) }], 'imperial')).toEqual(
      [{ fieldId: 1, message: "Home North's shape isn't under North 160 (pivot), 2.2 mi away" }],
    )
  })

  it('allows a quarter mile between a point kind and its field', () => {
    const traveler = system('traveler', -89.4, 44.1)
    const near = square(-89.399, 44.1005) // 80 m away
    const far = square(-89.37, 44.1)
    expect(outlineProblems(traveler, [{ id: 1, name: 'Near', boundary: near }], 'imperial')).toEqual([])
    expect(outlineProblems(traveler, [{ id: 2, name: 'Far', boundary: far }], 'metric')).toEqual([
      { fieldId: 2, message: "Far's shape is 2.4 km from Lane 3 (traveler)" },
    ])
  })

  it('measures to the nearest edge, 0 inside', () => {
    expect(distanceToBoundaryM([-89.398, 44.102], square(-89.4, 44.1))).toBe(0)
    expect(distanceToBoundaryM([-89.4, 44.095], square(-89.4, 44.1))).toBeCloseTo(556.6, 0)
    expect(formatReach(50, 'imperial')).toBe('164 ft')
    expect(formatReach(500, 'metric')).toBe('500 m')
  })
})

describe('a shape away from its system (G.14 part 7)', () => {
  it('finds the nearest point of a segment, at its end past it', () => {
    const near = nearestOnSegment([-89.4, 44.101], [-89.401, 44.1], [-89.399, 44.1])
    expect(near.point[0]).toBeCloseTo(-89.4, 6)
    expect(near.point[1]).toBeCloseTo(44.1, 6)
    expect(near.meters).toBeCloseTo(111.3, 0)
    expect(nearestOnSegment([-89.39, 44.1], [-89.401, 44.1], [-89.399, 44.1]).point).toEqual([-89.399, 44.1])
  })

  it('lists the systems within half a mile, nearest first: a pivot it overlaps at 0', () => {
    const shape = square(-89.502, 44.099)
    const pivot = { ...system('center', -89.5, 44.1), id: 1 }
    const near = { ...system('traveler', -89.4975, 44.099), id: 2 } // 40 m east
    const halfMile = { ...system('drip', -89.492, 44.099), id: 3 } // 480 m east
    const far = { ...system('drip', -89.45, 44.1), id: 4 }
    const listed = systemsNear(shape, [far, halfMile, near, pivot])
    expect(listed.map(({ system }) => system.id)).toEqual([1, 2, 3])
    expect(listed[0].meters).toBe(0)
    expect(listed[2].meters).toBeCloseTo(480, -1)
    expect(touchesSystem(shape, near)).toBe(true)
    expect(touchesSystem(shape, halfMile)).toBe(false)
    expect(systemDistanceM(shape, far)).toBeGreaterThan(800)
    expect(systemDistanceM(shape, { ...near, longitude: -89.5, latitude: 44.1 })).toBe(0) // inside it
  })

  it("draws the line from the shape's nearest edge to a point kind's location", () => {
    const line = reachLine(square(-89.4, 44.1), system('traveler', -89.39, 44.102))
    expect(line.to).toEqual([-89.39, 44.102])
    expect(line.from[0]).toBeCloseTo(-89.396, 6) // the east edge, level with it
    expect(line.from[1]).toBeCloseTo(44.102, 6)
    expect(line.meters).toBeCloseTo(480, -1)
  })

  it("draws the line to the nearest point of a pivot's circle", () => {
    const pivot = system('center', -89.5, 44.1) // 1,300 ft, about 396 m
    const line = reachLine(square(-89.49, 44.0985, 0.003), pivot)
    expect(line.from[0]).toBeCloseTo(-89.49, 6) // the shape's west edge
    expect(line.to[0]).toBeGreaterThan(-89.5)
    expect(line.meters).toBeCloseTo(800 - 396, -1)
  })
})
