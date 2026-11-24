import { describe, expect, it } from 'vitest'

import { bearing, distanceM, type LngLat, pointInPolygon } from '@/lib/geo'
import { type Boundary, GROUP_MARGIN_M } from '@/lib/boundary'
import type { FieldCard } from '@/lib/overview'
import type { PlantingSummary } from '@/types/serializers'

import {
  badgeRows,
  fieldFeatures,
  fieldBadges,
  groupFeatures,
  type MapSystem,
  packRows,
  systemBounds,
  systemFeatures,
  systemOutline,
} from './systems'
import { badgeFit, glyphProperties, MIN_POINT_PX } from './systemLayers'

const field = (status: PlantingSummary['status'], phase: PlantingSummary['phase'] = 'active'): FieldCard => ({
  id: 1,
  name: 'Field',
  plantings: [{ phase, status, weather_pending: false, crossing: null } as PlantingSummary],
})

const system = (
  id: number,
  latitude: number,
  fields: FieldCard[] = [],
  radius_ft: number | null = 1300,
): MapSystem => ({
  id,
  name: `Pivot ${id}`,
  kind_name: 'Pivot',
  irrigation_group_id: null,
  weather_updating: false,
  latitude,
  longitude: -89.5,
  kind: 'center',
  radius_ft,
  arc_start_deg: null,
  arc_end_deg: null,
  length_ft: null,
  travel_ft: null,
  travel_bearing_deg: null,
  weather_cell_id: null,
  fields,
  outlines: [],
})

const square = (lng: number, lat: number): Boundary => ({
  type: 'Polygon' as const,
  coordinates: [
    [
      [lng, lat],
      [lng + 0.002, lat],
      [lng + 0.002, lat + 0.002],
      [lng, lat + 0.002],
      [lng, lat],
    ] as LngLat[],
  ],
})

describe('systemFeatures', () => {
  it('gives each system its most urgent field in season, and marks the selection and the window', () => {
    const systems = [system(1, 44.1, [field('ok'), field('caution')]), system(2, 44.2, [field('irrigate', 'ended')])]
    const { features } = systemFeatures(systems, 2, new Set([1]))
    // Each system is its circle and a point for its glyph, with the same properties
    expect(features.map((f) => [f.id, f.geometry.type])).toEqual([
      [1, 'Polygon'],
      [1, 'Point'],
      [2, 'Polygon'],
      [2, 'Point'],
    ])
    expect(
      features
        .map(({ properties: { id, name, status, selected, dimmed, outlined, glyph } }) => ({
          id,
          name,
          status,
          selected,
          dimmed,
          outlined,
          glyph,
        }))
        .filter((_, i) => i % 2 === 0),
    ).toEqual([
      { id: 1, name: 'Pivot 1', status: 'caution', selected: false, dimmed: false, outlined: false, glyph: 'circle' },
      { id: 2, name: 'Pivot 2', status: 'none', selected: true, dimmed: true, outlined: false, glyph: 'circle' },
    ])
  })

  it('gives each kind its glyph, point kinds marked as points', () => {
    expect(glyphProperties(system(1, 44.1))).toMatchObject({ glyph: 'circle', point: false })
    const traveler = { ...system(2, 44.1), kind: 'traveler' as const, radius_ft: null }
    expect(glyphProperties(traveler)).toMatchObject({ glyph: 'diamond', point: true, rotate: 0 })
    expect(glyphProperties({ ...traveler, kind: 'point' }).glyph).toBe('triangle')
  })

  it("sizes glyphs in pixels: a point kind's to enclose its badges, any one zoomed out to ring its dot", () => {
    // One badge: a 24 px round backing; four: two rows of two, 46 px square
    expect(badgeFit('circle', [1])).toBe(31)
    expect(badgeFit('diamond', [2, 2])).toBeGreaterThan(badgeFit('diamond', [1]))
    expect(badgeFit('triangle', [1])).toBeGreaterThan(badgeFit('circle', [1]))
    expect(badgeFit('circle', [])).toBe(0)
    const fields = [field('ok'), field('ok'), field('ok'), field('ok')].map((card, i) => ({ ...card, id: i + 1 }))
    const traveler = { ...system(1, 44.1, fields), kind: 'traveler' as const, radius_ft: null }
    const props = systemFeatures([traveler], null, null).features[0].properties
    expect(props.near_px).toBe(badgeFit('diamond', [2, 2]))
    expect(props.far_px).toBe(badgeFit('diamond', [1]))
    // No fields: the smallest glyph
    expect(glyphProperties(traveler).near_px).toBe(MIN_POINT_PX)
  })

  it('draws a point kind whose fields have outlines as the area around them, 50 ft out', () => {
    const traveler: MapSystem = {
      ...system(2, 44.1, [{ ...field('ok'), id: 10, name: 'East' }]),
      kind: 'traveler',
      radius_ft: null,
      outlines: [{ field_id: 10, boundary: square(-89.5, 44.1) }],
    }
    const ring = systemOutline(traveler)!
    expect(pointInPolygon([-89.5001, 44.0999], [ring])).toBe(true) // 11 m outside the field's corner
    expect(pointInPolygon([-89.501, 44.099], [ring])).toBe(false)
    const [shape, point] = systemFeatures([traveler], null, null).features
    expect(shape.geometry.type).toBe('Polygon')
    expect(point.properties).toMatchObject({ point: false, glyph: 'diamond' })
    expect(systemOutline({ ...traveler, outlines: [] })).toBeNull()
  })

  it("takes a point kind's own location into its outline when it sits off its fields", () => {
    const traveler: MapSystem = {
      ...system(2, 44.1, [{ ...field('ok'), id: 10, name: 'East' }]),
      kind: 'traveler',
      radius_ft: null,
      longitude: -89.505,
      outlines: [{ field_id: 10, boundary: square(-89.5, 44.1) }],
    }
    const ring = systemOutline(traveler)!
    expect(pointInPolygon([-89.505, 44.1], [ring])).toBe(true)
    expect(pointInPolygon([-89.5051, 44.1], [ring])).toBe(true) // within the 50 ft margin
    expect(pointInPolygon([-89.506, 44.1], [ring])).toBe(false)
  })

  it('dims nothing without a window', () => {
    expect(systemFeatures([system(1, 44.1)], null, null).features[0].properties.dimmed).toBe(false)
  })

  it('draws the circle at its radius, or the default without one', () => {
    const [feature] = systemFeatures([system(1, 44.1, [], null)], null, null).features
    const ring = feature.geometry.coordinates as LngLat[][]
    expect(distanceM([-89.5, 44.1], ring[0][0])).toBeCloseTo(1300 / 3.28084, 0)
  })

  it('draws a linear as its rectangle', () => {
    const linear = {
      ...system(1, 44.1),
      kind: 'linear' as const,
      radius_ft: null,
      length_ft: 1300,
      travel_ft: 2640,
      travel_bearing_deg: 45,
    }
    const [feature] = systemFeatures([linear], null, null).features
    const corners = (feature.geometry.coordinates as LngLat[][])[0]
    expect(corners).toHaveLength(5)
    expect(distanceM(corners[0], corners[1]) * 3.28084).toBeCloseTo(1300, 0)
    expect(distanceM(corners[1], corners[2]) * 3.28084).toBeCloseTo(2640, 0)
    expect(bearing(corners[2], corners[1])).toBeCloseTo(45, 0) // turned to its direction of travel
  })

  it('draws a point kind at its location', () => {
    const traveler = { ...system(1, 44.1), kind: 'traveler' as const, radius_ft: null }
    expect(systemFeatures([traveler], null, null).features[0].geometry).toEqual({
      type: 'Point',
      coordinates: [-89.5, 44.1],
    })
  })
})

describe('groupFeatures', () => {
  const grouped = (id: number, latitude: number, group: number | null, kind: MapSystem['kind'] = 'center') => ({
    ...system(id, latitude),
    kind,
    radius_ft: kind === 'center' ? 1300 : null,
    irrigation_group_id: group,
  })

  it('outlines each group around its systems shown, with a margin', () => {
    const systems = [grouped(1, 44.1, 7), grouped(2, 44.12, 7, 'drip'), grouped(3, 44.3, null)]
    const farms = [{ id: 1, name: 'Farm', irrigation_groups: [{ id: 7, name: 'East gauge' }], systems }]
    const { features } = groupFeatures(farms, systems)
    expect(features).toHaveLength(1)
    expect(features[0].properties).toEqual({ name: 'East gauge', selected: false })
    const outline = features[0].geometry.coordinates as LngLat[][]
    // The system's far edge and the drip block, but not the ungrouped system
    const north = (1300 / 3.28084 + GROUP_MARGIN_M / 2) / 111_000
    expect(pointInPolygon([-89.5, 44.1 - north], outline)).toBe(true)
    expect(pointInPolygon([-89.5, 44.12], outline)).toBe(true)
    expect(pointInPolygon([-89.5, 44.3], outline)).toBe(false)
  })

  it("reaches around its systems' field outlines too", () => {
    const systems = [{ ...grouped(1, 44.1, 7), outlines: [{ field_id: 1, boundary: square(-89.44, 44.1) }] }]
    const farms = [{ id: 1, name: 'Farm', irrigation_groups: [{ id: 7, name: 'East gauge' }], systems }]
    const outline = groupFeatures(farms, systems).features[0].geometry.coordinates as LngLat[][]
    expect(pointInPolygon([-89.438, 44.102], outline)).toBe(true)
  })

  it('marks the selected group', () => {
    const systems = [grouped(1, 44.1, 7), grouped(2, 44.3, 8)]
    const farms = [
      {
        id: 1,
        name: 'Farm',
        irrigation_groups: [
          { id: 7, name: 'East gauge' },
          { id: 8, name: 'West gauge' },
        ],
        systems,
      },
    ]
    const selected = groupFeatures(farms, systems, 8).features.map((feature) => feature.properties.selected)
    expect(selected).toEqual([false, true])
  })

  it('leaves out a group with none of its systems shown', () => {
    const systems = [grouped(1, 44.1, 7)]
    const farms = [{ id: 1, name: 'Farm', irrigation_groups: [{ id: 7, name: 'East gauge' }], systems }]
    expect(groupFeatures(farms, []).features).toEqual([])
  })
})

describe('systemBounds', () => {
  it('covers every system to its edge', () => {
    const [[west, south], [east, north]] = systemBounds([system(1, 44.1), system(2, 44.3)])!
    expect(south).toBeLessThan(44.1)
    expect(north).toBeGreaterThan(44.3)
    expect(west).toBeLessThan(-89.5)
    expect(east).toBeGreaterThan(-89.5)
  })

  it('includes a point kind', () => {
    const drip = { ...system(2, 44.5), kind: 'drip' as const, radius_ft: null }
    expect(systemBounds([system(1, 44.1), drip])![1][1]).toBe(44.5)
  })

  it('is null without systems', () => {
    expect(systemBounds([])).toBeNull()
  })
})

describe('fields with outlines and pinned plots', () => {
  const card = (id: number, name: string, plantings: Partial<PlantingSummary>[]): FieldCard => ({
    id,
    name,
    plantings: plantings.map(
      (p) =>
        ({
          phase: 'active',
          weather_pending: false,
          crossing: null,
          variety: null,
          season_start: '2026-05-15',
          end_date: '2026-09-15',
          ...p,
        }) as PlantingSummary,
    ),
  })
  const north = card(10, 'Home North', [{ planting_id: 100, status: 'irrigate', plant_name: 'Potato' }])
  const plots = card(11, 'Plots', [
    { planting_id: 110, status: 'ok', plant_name: 'Soybean' },
    { planting_id: 111, status: 'caution', plant_name: 'Corn', phase: 'ended', end_date: '2026-07-01' },
  ])
  const outlined: MapSystem = {
    ...system(1, 44.1, [north, plots]),
    outlines: [{ field_id: 10, boundary: square(-89.501, 44.1) }],
  }

  it('draws each outlined field in its status, with a point on its top edge for its name', () => {
    const { features } = fieldFeatures([outlined], 10, new Set([2]))
    expect(features.map((f) => [f.properties.kind, f.geometry.type])).toEqual([
      ['outline', 'Polygon'],
      ['label', 'Point'],
    ])
    expect(features[0].properties).toEqual({
      id: 10,
      system_id: 1,
      name: 'Home North',
      status: 'irrigate',
      selected: true,
      dimmed: true,
      kind: 'outline',
    })
    const [lng, lat] = features[1].geometry.coordinates as LngLat
    expect(lng).toBeCloseTo(-89.5, 6)
    expect(lat).toBeCloseTo(44.102, 6)
  })

  it('gives each outlined field a badge per planting at its center, named for the hover label', () => {
    const both = { ...outlined, outlines: [...outlined.outlines, { field_id: 11, boundary: square(-89.6, 44.2) }] }
    const [home, plotted] = fieldBadges([both], '2026-07-19')
    expect(home).toMatchObject({ field_id: 10, system_id: 1, field_name: 'Home North' })
    expect(home.badges).toEqual([{ key: 100, status: 'irrigate', lines: ['Planting: Potato (May 15, 65 days)'] }])
    expect(plotted.badges).toEqual([
      { key: 110, status: 'ok', lines: ['Planting: Soybean (May 15, 65 days)'] },
      { key: 111, status: null, lines: ['Planting: Corn (May 15 – Jul 1)'] },
    ])
    expect(pointInPolygon(plotted.center, square(-89.6, 44.2).coordinates)).toBe(true)
    // A field with nothing planted is a gray dot; one without an outline has none here
    const empty = fieldBadges([{ ...outlined, fields: [card(10, 'Home North', [])] }], '2026-07-19')
    expect(empty[0].badges).toEqual([{ key: 0, status: null, lines: ['No crop this season'] }])
  })

  it('draws a system with outlined fields as a line', () => {
    expect(systemFeatures([outlined], null, null).features[0].properties.outlined).toBe(true)
  })

  it('fits the map around outlines that reach past the system', () => {
    const far = { ...outlined, outlines: [{ field_id: 10, boundary: square(-89.45, 44.1) }] }
    expect(systemBounds([far])![1][0]).toBeCloseTo(-89.448, 3)
  })
})

describe('badgeRows', () => {
  it('packs badges into rows of about √n, longer rows first', () => {
    expect([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(badgeRows)).toEqual([
      [],
      [1],
      [2],
      [2, 1],
      [2, 2],
      [3, 2],
      [3, 3],
      [3, 2, 2],
      [3, 3, 2],
      [3, 3, 3],
      [4, 3, 3],
    ])
  })

  it('slices items into those rows', () => {
    expect(packRows(['a', 'b', 'c', 'd', 'e'])).toEqual([
      ['a', 'b', 'c'],
      ['d', 'e'],
    ])
    expect(packRows([])).toEqual([])
  })
})
