/// <reference types="node" />
import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

import { boundaryRing, type LngLat, vertexCount } from '@/lib/geo'

import { nameKey, OutlineFileError, readOutlineFile, shapeName, shapeNotes, shapesFrom } from './read'

// Field outlines from files (PLAN.md Phase 8 G.10); fixtures in spec/fixtures/files/outlines
const fixture = (name: string) => new File([readFileSync(`spec/fixtures/files/outlines/${name}`)], name)

describe('reading outline files', () => {
  it('reads a zipped shapefile, reprojected from UTM with its .prj', async () => {
    const result = await readOutlineFile(fixture('clu_utm.zip'))
    expect(result.shapes).toHaveLength(2)
    expect(result.nameKey).toBe('FIELD_NAME')
    expect(result.shapes.map((shape) => shapeName(shape, result.nameKey))).toEqual(['Home North', 'Home South'])
    const [west, south] = boundaryRing(result.shapes[0].boundary)[0]
    expect(west).toBeCloseTo(-89.35, 5)
    expect(south).toBeCloseTo(43.3, 5)
    expect(result.shapes[0].acres).toBeCloseTo(111.17, 0) // 0.01° by 0.005° at 43.3°N
    expect(result.shapes[0].problems).toEqual([])
  })

  it('asks for the .prj and for the whole shapefile zipped', async () => {
    await expect(readOutlineFile(fixture('no_prj.zip'))).rejects.toThrow(/no \.prj file/)
    await expect(readOutlineFile(new File(['x'], 'fields.shp'))).rejects.toThrow(/Zip the \.shp, \.dbf and \.prj/)
    await expect(readOutlineFile(new File(['x'], 'fields.pdf'))).rejects.toBeInstanceOf(OutlineFileError)
  })

  it('reads KML and KMZ, leaving out points and dropping altitudes', async () => {
    for (const name of ['google_earth.kml', 'google_earth.kmz']) {
      const result = await readOutlineFile(fixture(name))
      expect(result.shapes).toHaveLength(1)
      expect(result.skipped).toBe(1)
      expect(shapeName(result.shapes[0], result.nameKey)).toBe('River 80')
      expect(boundaryRing(result.shapes[0].boundary)[0]).toEqual([-89.36, 43.3])
    }
  })

  it('reads GeoJSON, keeping a multipolygon’s largest part and guessing the name from its attributes', async () => {
    const result = await readOutlineFile(fixture('fields.geojson'))
    expect(result.shapes).toHaveLength(1)
    expect(result.skipped).toBe(1)
    expect(result.nameKey).toBe('Field Name')
    expect(result.shapes[0].boundary.type).toBe('Polygon')
    expect(boundaryRing(result.shapes[0].boundary)[0]).toEqual([-89.37, 43.3])
    expect(shapeNotes(result.shapes[0])).toBe('Kept the largest of 2 parts')
    await expect(readOutlineFile(new File(['{oops'], 'bad.geojson'))).rejects.toThrow("isn't valid GeoJSON")
  })
})

describe('shapes from features', () => {
  const ring = (corners: number): LngLat[] => {
    const points = Array.from({ length: corners }, (_, i): LngLat => {
      const angle = (2 * Math.PI * i) / corners
      return [-89.4 + 0.005 * Math.cos(angle), 43.3 + 0.005 * Math.sin(angle)]
    })
    return [...points, points[0]]
  }

  it('closes rings and simplifies detailed outlines to the corner limit', () => {
    const open = ring(4000).slice(0, -1)
    const { shapes } = shapesFrom([
      {
        type: 'FeatureCollection',
        features: [{ type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [open] } }],
      },
    ])
    expect(shapes[0].notes).toEqual(['simplified to fewer corners'])
    expect(vertexCount(shapes[0].boundary)).toBeLessThanOrEqual(1000)
    expect(shapes[0].problems).toEqual([])
  })

  it('reports a shape too large for a field rather than dropping it', () => {
    const huge: LngLat[] = [
      [-89.5, 43.2],
      [-89.3, 43.2],
      [-89.3, 43.4],
      [-89.5, 43.4],
      [-89.5, 43.2],
    ]
    const { shapes } = shapesFrom([
      {
        type: 'FeatureCollection',
        features: [{ type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [huge] } }],
      },
    ])
    expect(shapes[0].problems).toEqual(['is larger than a field (at most 1,500 acres)'])
  })

  it('keeps the largest part of a multipolygon, without its holes', () => {
    const small = ring(8).map(([lng, lat]): LngLat => [lng + 0.02, lat])
    const big = ring(12).map(([lng, lat]): LngLat => [lng, lat + (lat - 43.3)])
    const hole = ring(6).map(([lng, lat]): LngLat => [-89.4 + (lng + 89.4) / 4, 43.3 + (lat - 43.3) / 4])
    const { shapes } = shapesFrom([
      {
        type: 'FeatureCollection',
        features: [
          {
            type: 'Feature',
            properties: {},
            geometry: { type: 'MultiPolygon', coordinates: [[small], [big, hole, hole], [small]] },
          },
        ],
      },
    ])
    expect(shapes[0].boundary.coordinates).toHaveLength(1)
    expect(vertexCount(shapes[0].boundary)).toBe(12)
    expect(shapeNotes(shapes[0])).toBe('Kept the largest of 3 parts; 2 holes removed')
  })

  it('picks a name attribute: a known one first, else the first with text', () => {
    expect(nameKey([{ OBJECTID: 1, CLUNBR: 4, FIELD_NAME: 'A' }])).toBe('FIELD_NAME')
    expect(nameKey([{ OBJECTID: 1, CLUNBR: 4 }])).toBe('CLUNBR')
    expect(nameKey([{ OBJECTID: 1, farm: 'Home' }])).toBe('farm')
    expect(nameKey([{ OBJECTID: 1 }])).toBeNull()
  })
})
