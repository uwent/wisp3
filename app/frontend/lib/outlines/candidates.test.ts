import { describe, expect, it } from 'vitest'

import type { LngLat } from '@/lib/geo'
import type { Boundary } from '@/lib/boundary'

import { type CandidateSystem, fieldCandidates, systemCandidates } from './candidates'

const square = (lng: number, lat: number, size = 0.002): Boundary => ({
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

const system = (id: number, kind: CandidateSystem['kind'], longitude: number, latitude: number): CandidateSystem => ({
  id,
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

describe("an import card's choices", () => {
  const systems = [system(1, 'center', -89.5, 44.1), system(2, 'traveler', -89.45, 44.1)]
  const shape = square(-89.501, 44.099)

  it('offers the fields it overlaps first, then the rest by distance, from the system without an outline', () => {
    const fields = [
      { id: 10, pivot_id: 1, boundary: square(-89.52, 44.099) }, // about 1.5 km
      { id: 11, pivot_id: 2, boundary: null }, // its traveler, about 4 km
      { id: 12, pivot_id: 1, boundary: square(-89.5005, 44.099) }, // overlapping three quarters
      { id: 13, pivot_id: 1, boundary: null }, // its pivot's center, about 100 m
    ]
    const candidates = fieldCandidates(shape, fields, systems)
    expect(candidates.map(({ id }) => id)).toEqual([12, 13, 10, 11])
    expect(candidates[0].share).toBeCloseTo(0.75, 1)
    expect(candidates[1].share).toBe(0)
  })

  it('offers the systems nearest first, 0 under one', () => {
    expect(systemCandidates(shape, [systems[1], systems[0]])).toEqual([
      { id: 1, meters: 0 },
      { id: 2, meters: expect.any(Number) },
    ])
  })
})
