import { describe, expect, it } from 'vitest'

import { zoneAt, zoneEdges } from './zones'

const zone = (north: number, south: number, west: number, east: number) => ({ bounds: { north, south, west, east } })

describe('zoneEdges', () => {
  it('draws each edge once, where zones meet too', () => {
    // Two side by side on one ring, and one on the ring south of them, offset
    const zones = [zone(44.2, 44.1, -89.6, -89.5), zone(44.2, 44.1, -89.5, -89.4), zone(44.1, 44.0, -89.55, -89.45)]
    const lines = zoneEdges(zones).features.map((feature) => feature.geometry.coordinates)
    expect(lines).toEqual(
      expect.arrayContaining([
        // The north edge, across both
        [
          [-89.6, 44.2],
          [-89.4, 44.2],
        ],
        // Between the rings, the northern zones' south edge and the southern one's north edge merged
        [
          [-89.6, 44.1],
          [-89.4, 44.1],
        ],
        // The shared side, once
        [
          [-89.5, 44.1],
          [-89.5, 44.2],
        ],
      ]),
    )
    expect(lines).toHaveLength(3 + 5)
  })

  it('draws nothing without zones', () => {
    expect(zoneEdges([]).features).toEqual([])
  })
})

describe('zoneAt', () => {
  const zones = [zone(44.2, 44.1, -89.6, -89.5), zone(44.2, 44.1, -89.5, -89.4)]

  it('finds the zone a point is in, one zone on a shared edge', () => {
    expect(zoneAt(zones, [-89.55, 44.15])).toBe(zones[0])
    expect(zoneAt(zones, [-89.5, 44.15])).toBe(zones[1])
    expect(zoneAt(zones, [-89.3, 44.15])).toBeNull()
  })
})
