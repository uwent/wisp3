import { describe, expect, it } from 'vitest'

import {
  type Boundary,
  boundaryAcres,
  boundaryCenter,
  boundaryErrors,
  boundaryFrom,
  closeRing,
  inBoundary,
  type LngLat,
  MAX_BOUNDARY_VERTICES,
  pathCrossesItself,
  pivotAcres,
  pivotRing,
  roundBoundary,
  simplifyBoundary,
  vertexCount,
} from './geo'
import { areaWkt } from './soils'

// A field's outline (PLAN.md Phase 8 G.10; one ring since G.14). The polygons and areas match
// spec/services/field_boundary_spec.rb, so the browser and the server agree.
const outer: LngLat[] = [
  [-89.35, 43.3],
  [-89.34, 43.3],
  [-89.34, 43.31],
  [-89.35, 43.31],
  [-89.35, 43.3],
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

  it('agrees with a pivot’s acres for its circle', () => {
    const circle: Boundary = { type: 'Polygon', coordinates: [pivotRing([-89.5, 44.1], 1300, null, null, 360)] }
    expect(boundaryAcres(circle)).toBeCloseTo(pivotAcres(1300), 0)
  })
})

describe('checking an outline', () => {
  it('accepts a field and words problems as the server does', () => {
    expect(boundaryErrors(square)).toEqual([])
    expect(boundaryErrors({ type: 'Polygon', coordinates: [outer.slice(0, 4)] })).toEqual(["isn't closed"])
    expect(boundaryErrors({ type: 'Polygon', coordinates: [ring(100)] })).toEqual([])
    expect(boundaryErrors({ type: 'Polygon', coordinates: [ring(101)] })).toEqual([
      'has too many corners (at most 100; simplify it)',
    ])
    expect(boundaryErrors({ type: 'Polygon', coordinates: [bowtie] })).toEqual(['crosses itself'])
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
  })
})

// An L-shaped field (concave, and fine) and a bowtie (two edges cross), as in field_boundary_spec.rb
const corner = (east: number, north: number): LngLat => [-89.4 + east * 0.002, 43.3 + north * 0.002]
const ell = [corner(0, 0), corner(2, 0), corner(2, 1), corner(1, 1), corner(1, 2), corner(0, 2), corner(0, 0)]
// (lopsided, so its halves don't cancel to no area)
const bowtie = [corner(0, 0), corner(2, 2), corner(2, 0), corner(0, 1), corner(0, 0)]

describe('an outline that crosses itself', () => {
  it('finds edges that cross, not a concave corner', () => {
    expect(pathCrossesItself(ell)).toBe(false)
    expect(pathCrossesItself(square.coordinates[0])).toBe(false)
    expect(pathCrossesItself(bowtie)).toBe(true)
  })

  it("doesn't count edges that only touch", () => {
    // The fourth corner sits on the first edge
    expect(pathCrossesItself([corner(0, 0), corner(2, 0), corner(2, 2), corner(1, 0), corner(0, 0)])).toBe(false)
  })

  it('checks a path being drawn without its closing edge', () => {
    // A spiral drawn inward: the corners so far don't cross, but closing it now would
    const drawn = [
      corner(0, 0),
      corner(3, 0),
      corner(3, 3),
      corner(0, 3),
      corner(0, 1),
      corner(2, 1),
      corner(2, 2),
      corner(1, 2),
    ]
    expect(pathCrossesItself(drawn)).toBe(false)
    expect(pathCrossesItself([...drawn, drawn[0]])).toBe(true)
  })
})

describe('preparing an outline', () => {
  it('rounds positions to about a centimeter and drops altitudes', () => {
    const withAltitude = [[-89.123456789, 43.3, 250] as unknown as LngLat, ...outer.slice(1, 4), [-89.123456789, 43.3]]
    const rounded = roundBoundary({ type: 'Polygon', coordinates: [withAltitude as LngLat[]] })
    expect(rounded.coordinates[0][0]).toEqual([-89.1234568, 43.3])
  })

  it('closes a ring and makes it a Polygon', () => {
    expect(closeRing(outer.slice(0, 4))).toEqual(outer)
    expect(closeRing(outer)).toEqual(outer)
    expect(boundaryFrom(outer.slice(0, 4))).toEqual(square)
  })

  it('simplifies a detailed outline to the limit, keeping its shape', () => {
    const detailed: Boundary = { type: 'Polygon', coordinates: [ring(5000, undefined, 0.005)] }
    const simple = simplifyBoundary(detailed)
    expect(vertexCount(simple)).toBeLessThanOrEqual(MAX_BOUNDARY_VERTICES)
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

  it('stays inside an L-shaped or C-shaped field', () => {
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
    // A C: a circle with a wedge cut out on its east side, where the centroid falls
    const c = ring(32, undefined, 0.01).filter(
      ([lng], i, all) => i === all.length - 1 || i === 0 || lng < -89.4 + 0.004,
    )
    const cee = boundaryFrom([[-89.4 + 0.002, 43.3], ...c.slice(1, -1)])
    expect(inBoundary(boundaryCenter(cee), cee)).toBe(true)
  })
})

describe('the soil survey for an outline', () => {
  it('reads an outline or a ring as a polygon', () => {
    expect(areaWkt(square)).toMatch(/^POLYGON\(\(-89\.350000 43\.300000, .*\)\)$/)
    expect(areaWkt(outer)).toBe(areaWkt(square))
  })
})
