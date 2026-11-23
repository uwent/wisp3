import { describe, expect, it } from 'vitest'

import type { LngLat } from '@/lib/geo'
import type { Boundary } from '@/lib/boundary'

import { overlappingPairs, overlapShare, sharePercent } from './overlap'

const rect = (lng: number, lat: number, width = 0.004, height = 0.003): Boundary => ({
  type: 'Polygon',
  coordinates: [
    [
      [lng, lat],
      [lng + width, lat],
      [lng + width, lat + height],
      [lng, lat + height],
      [lng, lat],
    ] as LngLat[],
  ],
})

describe('how much two outlines overlap', () => {
  it('is all of the smaller one when one holds the other, and none when apart or edge to edge', () => {
    expect(overlapShare(rect(-89.5, 44.1), rect(-89.5, 44.1))).toBeCloseTo(1, 1)
    expect(overlapShare(rect(-89.5, 44.1), rect(-89.499, 44.1005, 0.001, 0.001))).toBeCloseTo(1, 1)
    expect(overlapShare(rect(-89.5, 44.1), rect(-89.49, 44.1))).toBe(0)
    expect(overlapShare(rect(-89.5, 44.1), rect(-89.496, 44.1))).toBe(0)
  })

  it('is the shared share of the smaller, within a few percent', () => {
    // Half of each, side by side
    expect(overlapShare(rect(-89.5, 44.1), rect(-89.498, 44.1))).toBeCloseTo(0.5, 1)
    // A triangle over half of the rectangle
    const triangle: Boundary = {
      type: 'Polygon',
      coordinates: [
        [
          [-89.5, 44.1],
          [-89.496, 44.1],
          [-89.5, 44.103],
          [-89.5, 44.1],
        ],
      ],
    }
    expect(overlapShare(rect(-89.5, 44.1), triangle)).toBeCloseTo(1, 1)
  })

  it('lists each pair overlapping enough for a warning once, largest first', () => {
    const fields = [
      { id: 1, boundary: rect(-89.5, 44.1) },
      { id: 2, boundary: rect(-89.4965, 44.1) }, // an eighth of 1
      { id: 3, boundary: rect(-89.4961, 44.1) }, // 90% of 2, a sliver of 1
      { id: 4, boundary: rect(-89.4, 44.1) },
    ]
    const pairs = overlappingPairs(fields)
    expect(pairs.map(({ a, b }) => [a.id, b.id])).toEqual([
      [2, 3],
      [1, 2],
    ])
    expect(sharePercent(pairs[0].share)).toMatch(/^9\d%$/)
    expect(sharePercent(0.001)).toBe('1%')
  })
})
