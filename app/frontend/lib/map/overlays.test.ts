import { describe, expect, it } from 'vitest'

import type { LngLat } from '@/lib/geo'

import {
  type DroughtData,
  droughtAt,
  droughtBounds,
  droughtDate,
  droughtUrl,
  OVERLAY_ORDER,
  OVERLAYS,
  parseWpcTime,
  RAIN_OVERLAYS,
  type RasterOverlay,
  SOIL_OVERLAY,
} from './overlays'

const square = (west: number, south: number, east: number, north: number): LngLat[] => [
  [west, south],
  [east, south],
  [east, north],
  [west, north],
  [west, south],
]

describe('overlays', () => {
  it('has a place in the drawing order for every overlay', () => {
    expect(OVERLAYS.map((o) => o.id).toSorted()).toEqual(OVERLAY_ORDER.toSorted())
  })

  it("builds tile URLs with the refresh stamp, and the forecast's layer and box", () => {
    const radar = RAIN_OVERLAYS.find((o) => o.id === 'radar')!
    expect(radar.tiles(42)).toEqual([
      'https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/{z}/{x}/{y}.png?t=42',
    ])
    const week = RAIN_OVERLAYS.find((o) => o.id === 'qpf7')!
    const [url] = week.tiles(1)
    expect(url).toContain('/wpc_qpf/MapServer/export?bbox={bbox-epsg-3857}')
    expect(url).toContain('layers=show:11')
  })

  it('asks the soil survey for map units in the tile, only zoomed in', () => {
    expect((SOIL_OVERLAY as RasterOverlay).tiles(1)[0]).toContain('LAYERS=mapunitpoly')
    expect(SOIL_OVERLAY.minzoom).toBeGreaterThanOrEqual(12)
  })

  it("reads WPC's issue time as UTC", () => {
    expect(parseWpcTime('2026-10-17 22:03:02').toISOString()).toBe('2026-10-17T22:03:02.000Z')
  })
})

describe('drought', () => {
  const data: DroughtData = {
    type: 'FeatureCollection',
    features: [
      {
        type: 'Feature',
        properties: { DM: 0, ValidStart: Date.UTC(2026, 9, 13) },
        geometry: { type: 'Polygon', coordinates: [square(-91, 43, -88, 46)] },
      },
      {
        type: 'Feature',
        properties: { DM: 1 },
        geometry: { type: 'MultiPolygon', coordinates: [[square(-90, 44, -89, 45)]] },
      },
      { type: 'Feature', properties: { DM: 2 }, geometry: null },
    ],
  }

  it('finds the highest category at a point, or none', () => {
    expect(droughtAt(data, [-89.5, 44.5])?.label).toBe('D1 Moderate drought')
    expect(droughtAt(data, [-90.5, 43.5])?.label).toBe('D0 Abnormally dry')
    expect(droughtAt(data, [-80, 40])).toBeNull()
  })

  it("gives the map's week", () => {
    expect(droughtDate(data)?.toISOString()).toBe('2026-10-13T00:00:00.000Z')
  })

  it('loads the area around the pivots, or Wisconsin without any', () => {
    expect(droughtBounds([[-89.5, 44.1]], 2)).toEqual([-91.5, 42.1, -87.5, 46.1])
    expect(droughtBounds([])).toEqual([-93, 42.4, -86.7, 47.1])
    const url = new URL(droughtUrl([-91.5, 42.1, -87.5, 46.1]))
    expect(url.searchParams.get('geometry')).toBe('-91.500,42.100,-87.500,46.100')
    expect(url.searchParams.get('f')).toBe('geojson')
  })
})
