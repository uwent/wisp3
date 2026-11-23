import { describe, expect, it } from 'vitest'

import type { LngLat } from '@/lib/geo'
import type { Boundary } from '@/lib/boundary'

import { type ImportSystem, initialChoices, matchField, systemSuggester } from './matching'

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
    expect(systemSuggester([traveler, pivot])(square(-89.501, 44.099))).toBe(1)
  })

  it('is a point kind within half a mile, the nearest first', () => {
    const suggest = systemSuggester([pivot, traveler])
    expect(suggest(square(-89.405, 44.1))).toBe(2) // about 300 m away
    expect(suggest(square(-89.42, 44.1))).toBeNull() // about 1.5 km
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
    expect(choices.map(({ choice }) => choice)).toEqual([
      { kind: 'field', fieldId: 10 },
      { kind: 'new' },
      { kind: 'skip' },
      { kind: 'skip' },
    ])
  })

  it('starts a shape covering most of an outlined field at that field, the largest overlap winning', () => {
    const outlined = [
      { id: 20, name: 'East 40', pivot_id: 1, boundary: square(-89.5, 44.1) },
      { id: 21, name: 'West 40', pivot_id: 1, boundary: square(-89.51, 44.1) },
    ]
    const choices = initialChoices(
      [
        { name: 'CLU 7', systemId: 1, problems: [], boundary: square(-89.4996, 44.1) }, // about 80% of East 40
        { name: 'CLU 8', systemId: 1, problems: [], boundary: square(-89.5, 44.1, 0.0021) }, // all of it: wins
        { name: 'CLU 9', systemId: 1, problems: [], boundary: square(-89.5088, 44.1) }, // about 40% of West 40
      ],
      outlined,
    )
    expect(choices.map(({ choice }) => choice)).toEqual([
      { kind: 'new' },
      { kind: 'field', fieldId: 20 },
      { kind: 'new' },
    ])
  })

  it("skips a shape that's already its field's, by name or by overlap, saying whose", () => {
    const outlined = [
      { id: 20, name: 'East 40', pivot_id: 1, boundary: square(-89.5, 44.1) },
      { id: 21, name: 'West 40', pivot_id: 1, boundary: square(-89.51, 44.1) },
    ]
    // The same corners from another starting corner, running the other way
    const [ring] = square(-89.51, 44.1).coordinates
    const reversed: Boundary = { type: 'Polygon', coordinates: [[...ring.slice(0, 4).reverse(), ring[3]]] }
    const choices = initialChoices(
      [
        { name: 'East 40', systemId: 1, problems: [], boundary: square(-89.50001, 44.1) }, // about 1 m off
        { name: 'CLU 9', systemId: 1, problems: [], boundary: reversed },
      ],
      outlined,
    )
    expect(choices.map(({ choice }) => choice)).toEqual([{ kind: 'skip' }, { kind: 'skip' }])
    expect(choices[0].same?.fieldId).toBe(20)
    expect(choices[0].same?.meters).toBeCloseTo(0.8, 1)
    expect(choices[1].same).toEqual({ fieldId: 21, meters: 0 })
  })
})
