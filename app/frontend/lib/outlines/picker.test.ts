import { describe, expect, it } from 'vitest'

import type { Boundary } from '@/lib/boundary'
import type { LngLat } from '@/lib/geo'

import {
  attributeKeys,
  attributeValue,
  type PickerContext,
  type PickerShape,
  pickerRows,
  rowNotes,
  rowTag,
  sameBoundary,
  shapeDistances,
  unusableSummary,
} from './picker'

// A square about 0.01° on a side with its southwest corner at lng, lat
const squareAt = (lng: number, lat: number): Boundary => ({
  type: 'Polygon',
  coordinates: [
    [
      [lng, lat],
      [lng + 0.01, lat],
      [lng + 0.01, lat + 0.01],
      [lng, lat + 0.01],
      [lng, lat],
    ] as LngLat[],
  ],
})
const shape = (name: string, boundary: Boundary | null, problems: string[] = []): PickerShape => ({
  properties: { NAME: name, OTHER: 1 },
  boundary,
  acres: 190,
  notes: [],
  problems,
})

// The field's pivot at -89.5, 44.1, a quarter mile long
const context: PickerContext = {
  field: { id: 1, name: 'Home South', pivot_id: 5, boundary: null },
  system: {
    id: 5,
    name: 'Pivot 1',
    kind: 'center',
    latitude: 44.1,
    longitude: -89.5,
    radius_ft: 1320,
    arc_start_deg: null,
    arc_end_deg: null,
    length_ft: null,
    travel_ft: null,
    travel_bearing_deg: null,
  },
  otherFields: [{ name: 'East 40', boundary: squareAt(-89.3, 44.3) }],
}

describe('picking a field shape', () => {
  it('compares outlines position by position, within a tolerance', () => {
    const a = squareAt(-89.5, 44.1)
    expect(sameBoundary(a, squareAt(-89.5, 44.1))).toBe(true)
    expect(sameBoundary(a, squareAt(-89.5000004, 44.1))).toBe(true)
    expect(sameBoundary(a, squareAt(-89.501, 44.1))).toBe(false)
    const fewer: Boundary = { type: 'Polygon', coordinates: [a.coordinates[0].slice(1)] }
    expect(sameBoundary(a, fewer)).toBe(false)
  })

  it("orders the field's name first, then the nearest its system; those that can't be saved last", () => {
    const shapes = [
      shape('Far', squareAt(-88, 43)),
      shape('Too big', null, ['is larger than a field (at most 1,500 acres)']),
      shape('Under', squareAt(-89.505, 44.095)),
      shape('home  south', squareAt(-88.5, 43.5)),
      shape('Nearer', squareAt(-88.2, 43.2)),
    ]
    const rows = pickerRows(shapes, 'NAME', context)
    expect(rows.map((row) => [row.name, row.match, row.usable])).toEqual([
      ['home  south', 'name', true],
      ['Under', null, true],
      ['Nearer', null, true],
      ['Far', null, true],
      ['Too big', null, false],
    ])
    expect(rows.map((row) => row.index)).toEqual([3, 2, 4, 0, 1])
  })

  it("measures from each shape's nearest edge to the system, 0 overlapping it", () => {
    // 0.01° of latitude (1,112 m) south of the pivot's edge, a quarter mile (402 m) from its center
    const south = squareAt(-89.505, 44.1 - 402 / 111_320 - 0.01 - 1112 / 111_320)
    const [under, away, none] = shapeDistances(
      [shape('Under', squareAt(-89.505, 44.095)), shape('South', south), shape('Too big', null, ['is too big'])],
      context.system,
    )
    expect(under).toBe(0)
    expect(away).toBeCloseTo(1112, -1)
    expect(none).toBeNull()
    // Worked out once, and taken as given
    const rows = pickerRows([shape('A', squareAt(-88, 43))], 'NAME', context, [42])
    expect(rows[0].meters).toBe(42)
  })

  it('names by the chosen attribute', () => {
    const rows = pickerRows([shape('Home South', squareAt(-88, 43))], 'OTHER', context)
    expect(rows[0].name).toBe('1')
    expect(rows[0].match).toBeNull()
  })

  it("marks shapes already another field's, or this field's", () => {
    const own = squareAt(-88, 43)
    const rows = pickerRows(
      [shape('A', squareAt(-89.3, 44.3)), shape('B', own), shape('C', squareAt(-87, 42))],
      'NAME',
      { ...context, field: { ...context.field, boundary: own } },
    )
    expect(rows.map((row) => row.usedBy)).toEqual(['East 40', 'this field', null])
    expect(rowNotes(rows[0])).toEqual(['Used for East 40'])
    expect(rowNotes(rows[1])).toEqual(["This field's shape now"])
    expect(rows.map(rowTag)).toEqual(['Used for East 40', "This field's shape now", null])
  })

  it("says why a shape is offered first, what reading it changed, and why one can't be used", () => {
    const rows = pickerRows(
      [
        { ...shape('Home South', squareAt(-89.505, 44.095)), notes: ['kept the largest of 3 parts'] },
        shape('Too big', null, ['is larger than a field (at most 1,500 acres)']),
      ],
      'NAME',
      context,
    )
    expect(rowNotes(rows[0])).toEqual(['Best match: same name', 'Kept the largest of 3 parts'])
    expect(rowTag(rows[0])).toBeNull()
    expect(rowNotes(rows[1])).toEqual(['This shape is larger than a field (at most 1,500 acres)'])
    expect(rowTag(rows[1])).toBe('This shape is larger than a field (at most 1,500 acres)')
  })

  it('lists every attribute, and shows each as text or a number', () => {
    expect(attributeKeys([{ properties: { a: 1, b: 2 } }, { properties: { b: 3, c: 4 } }])).toEqual(['a', 'b', 'c'])
    expect(attributeValue('x')).toBe('x')
    expect(attributeValue(3)).toBe(3)
    expect(attributeValue('')).toBeNull()
    expect(attributeValue(null)).toBeNull()
    expect(attributeValue(true)).toBe('Yes')
    expect(attributeValue({ a: 1 })).toBe('{"a":1}')
  })

  it("sums up why shapes can't be used, the commonest first", () => {
    const big = { problems: ['is larger than a field (at most 1,500 acres)'] }
    expect(unusableSummary([big, big, { problems: ['must be in the US or Canada'] }, big])).toBe(
      '3 are larger than a field (at most 1,500 acres); 1 must be in the US or Canada',
    )
    expect(
      unusableSummary([
        { problems: ['has too many corners (at most 100; simplify it)'] },
        { problems: ["isn't closed", 'crosses itself'] },
        { problems: ['crosses itself'] },
      ]),
    ).toBe("2 cross themselves; 1 has too many corners (at most 100; simplify it); 1 isn't closed")
  })
})
