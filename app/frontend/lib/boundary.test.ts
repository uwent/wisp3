import { describe, expect, it } from 'vitest'

import {
  type Boundary,
  boundaryAcres,
  boundaryCenter,
  boundaryErrors,
  boundaryOf,
  closeRing,
  inBoundary,
  type LngLat,
  pivotAcres,
  pivotRing,
  roundBoundary,
  simplifyBoundary,
  vertexCount,
} from './geo'
import { areaWkt } from './soils'

// A field's outline (PLAN.md Phase 8 G.10). The polygons and areas match
// spec/services/field_boundary_spec.rb, so the browser and the server agree.
const outer: LngLat[] = [
  [-89.35, 43.3],
  [-89.34, 43.3],
  [-89.34, 43.31],
  [-89.35, 43.31],
  [-89.35, 43.3],
]
const hole: LngLat[] = [
  [-89.348, 43.302],
  [-89.348, 43.304],
  [-89.346, 43.304],
  [-89.346, 43.302],
  [-89.348, 43.302],
]
const square: Boundary = { type: 'Polygon', coordinates: [outer] }

function ring(corners: number, center: LngLat = [-89.4, 43.3], radius = 0.001): LngLat[] {
  const points = Array.from({ length: corners }, (_, i): LngLat => {
    const angle = (2 * Math.PI * i) / corners
    return [center[0] + radius * Math.cos(angle), center[1] + radius * Math.sin(angle)]
  })
  return [...points, points[0]]
}

describe('an outline’s area', () => {
  it('measures a polygon on a spherical earth, as the server does', () => {
    expect(boundaryAcres(square)).toBeCloseTo(222.338, 2)
  })

  it('takes out holes and adds up a multipolygon’s parts', () => {
    expect(boundaryAcres({ type: 'Polygon', coordinates: [outer, hole] })).toBeCloseTo(213.444, 2)
    const shifted = outer.map(([lng, lat]): LngLat => [lng + 0.02, lat]).reverse()
    expect(boundaryAcres({ type: 'MultiPolygon', coordinates: [[outer], [shifted]] })).toBeCloseTo(2 * 222.338, 1)
  })

  it('agrees with a pivot’s acres for its circle', () => {
    const circle: Boundary = { type: 'Polygon', coordinates: [pivotRing([-89.5, 44.1], 1300, null, null, 360)] }
    expect(boundaryAcres(circle)).toBeCloseTo(pivotAcres(1300), 0)
  })
})

describe('checking an outline', () => {
  it('accepts a field and words problems as the server does', () => {
    expect(boundaryErrors(square)).toEqual([])
    expect(boundaryErrors({ type: 'Polygon', coordinates: [outer.slice(0, 4)] })).toEqual([
      "has a ring that isn't closed",
    ])
    expect(boundaryErrors({ type: 'Polygon', coordinates: [ring(1001)] })).toEqual([
      'has too many corners (at most 1,000; simplify it)',
    ])
    expect(boundaryErrors({ type: 'Polygon', coordinates: [outer.map(([lng, lat]): LngLat => [-lng, lat])] })).toEqual([
      'must be in the US or Canada',
    ])
    expect(boundaryErrors({ type: 'Polygon', coordinates: [ring(4, undefined, 0.00001)] })).toEqual([
      'is too small (at least 0.01 acres)',
    ])
    expect(boundaryErrors({ type: 'Polygon', coordinates: [ring(8, undefined, 0.05)] })).toEqual([
      'is larger than a field (at most 1,500 acres)',
    ])
  })

  it('counts corners once each', () => {
    expect(vertexCount(square)).toBe(4)
    expect(vertexCount({ type: 'Polygon', coordinates: [outer, hole] })).toBe(8)
  })
})

describe('preparing an outline', () => {
  it('rounds positions to about a centimeter and drops altitudes', () => {
    const withAltitude = [[-89.123456789, 43.3, 250] as unknown as LngLat, ...outer.slice(1, 4), [-89.123456789, 43.3]]
    const rounded = roundBoundary({ type: 'Polygon', coordinates: [withAltitude as LngLat[]] })
    expect(rounded.coordinates[0][0]).toEqual([-89.1234568, 43.3])
  })

  it('closes a ring and makes one polygon a Polygon, several a MultiPolygon', () => {
    expect(closeRing(outer.slice(0, 4))).toEqual(outer)
    expect(closeRing(outer)).toEqual(outer)
    expect(boundaryOf([[outer]])?.type).toBe('Polygon')
    expect(boundaryOf([[outer], [hole]])?.type).toBe('MultiPolygon')
    expect(boundaryOf([])).toBeNull()
  })

  it('simplifies a detailed outline to the limit, keeping its shape', () => {
    const detailed: Boundary = { type: 'Polygon', coordinates: [ring(5000, undefined, 0.005)] }
    const simple = simplifyBoundary(detailed)
    expect(vertexCount(simple)).toBeLessThanOrEqual(1000)
    expect(boundaryErrors(simple)).toEqual([])
    expect(boundaryAcres(simple)).toBeCloseTo(boundaryAcres(detailed), -1) // within a few acres of ~60
    expect(simplifyBoundary(square)).toBe(square)
  })
})

describe('a point inside an outline', () => {
  it('is the centroid of a convex field', () => {
    const [lng, lat] = boundaryCenter(square)
    expect(lng).toBeCloseTo(-89.345, 6)
    expect(lat).toBeCloseTo(43.305, 3)
  })

  it('stays inside an L-shaped or ring-shaped field', () => {
    const ell: Boundary = {
      type: 'Polygon',
      coordinates: [
        [
          [-89.35, 43.3],
          [-89.34, 43.3],
          [-89.34, 43.301],
          [-89.349, 43.301],
          [-89.349, 43.31],
          [-89.35, 43.31],
          [-89.35, 43.3],
        ],
      ],
    }
    expect(inBoundary(boundaryCenter(ell), ell)).toBe(true)
    const donut: Boundary = { type: 'Polygon', coordinates: [ring(32, undefined, 0.01), ring(32, undefined, 0.008)] }
    expect(inBoundary(boundaryCenter(donut), donut)).toBe(true)
  })

  it('is in the largest part of a multipolygon', () => {
    const small = ring(8, [-89.0, 43.3], 0.001)
    const large = ring(8, [-89.1, 43.3], 0.01)
    const center = boundaryCenter({ type: 'MultiPolygon', coordinates: [[small], [large]] })
    expect(center[0]).toBeCloseTo(-89.1, 3)
  })
})

describe('the soil survey for an outline', () => {
  it('reads one polygon with its holes, or several as a multipolygon', () => {
    expect(areaWkt({ type: 'Polygon', coordinates: [outer, hole] })).toMatch(
      /^POLYGON\(\(-89\.350000 43\.300000, .*\), \(-89\.348000 43\.302000, .*\)\)$/,
    )
    expect(areaWkt({ type: 'MultiPolygon', coordinates: [[outer], [hole]] })).toMatch(
      /^MULTIPOLYGON\(\(\(.*\)\), \(\(.*\)\)\)$/,
    )
    expect(areaWkt(outer)).toMatch(/^POLYGON\(\(.*\)\)$/)
  })
})
