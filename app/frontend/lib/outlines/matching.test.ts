import { describe, expect, it } from 'vitest'

import type { Boundary, LngLat } from '@/lib/geo'

import { type ImportSystem, initialChoices, matchField, suggestSystem } from './matching'

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

const system = (id: number, kind: ImportSystem['kind'], longitude: number, latitude: number): ImportSystem => ({
  id,
  name: `System ${id}`,
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

describe('the system an imported shape sits under', () => {
  const pivot = system(1, 'center', -89.5, 44.1)
  const traveler = system(2, 'traveler', -89.4, 44.1)

  it('is the pivot whose circle holds its center', () => {
    expect(suggestSystem(square(-89.501, 44.099), [traveler, pivot])).toBe(1)
  })

  it('is a point kind within half a mile, the nearest first', () => {
    expect(suggestSystem(square(-89.405, 44.1), [pivot, traveler])).toBe(2) // about 300 m away
    expect(suggestSystem(square(-89.42, 44.1), [pivot, traveler])).toBeNull() // about 1.5 km
  })
})

describe('matching shapes to fields', () => {
  const fields = [
    { id: 10, name: 'Home North', pivot_id: 1 },
    { id: 11, name: 'River', pivot_id: 1 },
    { id: 12, name: 'River', pivot_id: 2 },
  ]

  it('matches a name ignoring case and spacing, and a repeated name by system', () => {
    expect(matchField('  home  north ', fields, null)).toBe(10)
    expect(matchField('River', fields, 2)).toBe(12)
    expect(matchField('River', fields, null)).toBeNull()
    expect(matchField('', fields, 1)).toBeNull()
  })

  it('starts each shape at its field, a new field under its system, or skipped', () => {
    const choices = initialChoices(
      [
        { name: 'Home North', systemId: 1, problems: [] },
        { name: 'Home North', systemId: 1, problems: [] }, // its field is taken: a new one
        { name: 'Hill', systemId: null, problems: [] },
        { name: 'River', systemId: 1, problems: ['is larger than a field (at most 1,500 acres)'] },
      ],
      fields,
    )
    expect(choices).toEqual([{ kind: 'field', fieldId: 10 }, { kind: 'new' }, { kind: 'skip' }, { kind: 'skip' }])
  })
})
