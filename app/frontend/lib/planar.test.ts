import { describe, expect, it } from 'vitest'

import { nearestT, segmentDistance, segmentsCross, side } from './planar'

describe('plane geometry', () => {
  it('finds which side of a line a point is on', () => {
    expect(side([0, 0], [1, 0], [0, 1])).toBe(1)
    expect(side([0, 0], [1, 0], [0, -1])).toBe(-1)
    expect(side([0, 0], [1, 0], [2, 0])).toBe(0)
  })

  it('measures from a point to a segment, its ends included', () => {
    expect(nearestT([0.5, 1], [0, 0], [1, 0])).toBe(0.5)
    expect(segmentDistance([0.5, 1], [0, 0], [1, 0])).toBe(1)
    expect(segmentDistance([3, 4], [0, 0], [0, 0])).toBe(5) // a segment of no length is its point
    expect(segmentDistance([-3, 4], [0, 0], [1, 0])).toBe(5)
  })

  it('counts segments meeting at a point as crossing only when asked', () => {
    expect(segmentsCross([0, 0], [2, 2], [0, 2], [2, 0])).toBe(true)
    expect(segmentsCross([0, 0], [1, 1], [1, 1], [2, 0])).toBe(false)
    expect(segmentsCross([0, 0], [1, 1], [1, 1], [2, 0], { touching: true })).toBe(true)
    expect(segmentsCross([0, 0], [1, 0], [0, 1], [1, 1], { touching: true })).toBe(false)
  })
})
