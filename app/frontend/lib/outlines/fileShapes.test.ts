import { describe, expect, it } from 'vitest'

import type { LngLat } from '@/lib/geo'
import type { Boundary } from '@/lib/boundary'

import { unimportedShapes } from './fileShapes'
import type { KeptFile, KeptShape } from './kept'

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

const shape = (name: string, boundary: Boundary | null, problems: string[] = []): KeptShape => ({
  properties: { NAME: name },
  boundary,
  acres: 80,
  notes: [],
  problems,
})

const kept = (shapes: KeptShape[]): KeptFile => ({
  fileName: 'Fields.zip',
  savedAt: 0,
  nameKey: 'NAME',
  skipped: 0,
  shapes,
})

describe("a kept file's shapes on the irrigation system map", () => {
  it("are the usable ones not yet a saved field's, named", () => {
    const file = kept([
      shape('East 40', square(-89.5, 44.1)),
      shape('West 40', square(-89.51, 44.1)),
      shape('Moved', square(-89.52, 44.1)),
      shape('County', null, ['is larger than a field (at most 1,500 acres)']),
    ])
    // East 40 is saved about 1 m off; Moved's field was redrawn 20 m away
    const saved = [square(-89.50001, 44.1), square(-89.5202, 44.1)]
    expect(unimportedShapes(file, saved)).toEqual({
      fileName: 'Fields.zip',
      shapes: [
        { name: 'West 40', boundary: square(-89.51, 44.1) },
        { name: 'Moved', boundary: square(-89.52, 44.1) },
      ],
    })
  })

  it('are none once every shape is saved', () => {
    expect(unimportedShapes(kept([shape('East 40', square(-89.5, 44.1))]), [square(-89.5, 44.1)])).toBeNull()
  })

  it('are every usable shape when no field is outlined', () => {
    expect(unimportedShapes(kept([shape('East 40', square(-89.5, 44.1))]), [])?.shapes).toHaveLength(1)
  })
})
