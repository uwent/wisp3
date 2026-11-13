import { describe, expect, it } from 'vitest'

import type { Boundary, LngLat, PivotShape } from '@/lib/geo'

import { distanceToBoundaryM, formatReach, outlineProblems } from './problems'

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
