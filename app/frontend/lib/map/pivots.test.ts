import { describe, expect, it } from 'vitest'

import { bearing, distanceM, GROUP_MARGIN_M, type LngLat, pointInPolygon } from '@/lib/geo'
import type { FieldCard } from '@/lib/overview'
import type { PlantingSummary } from '@/types/serializers'

import { groupFeatures, type MapPivot, pivotBounds, pivotFeatures } from './pivots'

const field = (status: PlantingSummary['status'], phase: PlantingSummary['phase'] = 'active'): FieldCard => ({
  id: 1,
  name: 'Field',
  plantings: [{ phase, status, weather_pending: false, crossing: null } as PlantingSummary],
})

const pivot = (id: number, latitude: number, fields: FieldCard[] = [], radius_ft: number | null = 1300): MapPivot => ({
  id,
  name: `Pivot ${id}`,
  kind_name: 'Pivot',
  pivot_group_id: null,
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
  weather: null,
  fields,
})

describe('pivotFeatures', () => {
  it('colors each pivot by its most urgent field in season, and marks the selection and the window', () => {
    const pivots = [pivot(1, 44.1, [field('ok'), field('caution')]), pivot(2, 44.2, [field('irrigate', 'ended')])]
    const { features } = pivotFeatures(pivots, 2, new Set([1]))
    expect(features.map((f) => f.properties)).toEqual([
      { id: 1, name: 'Pivot 1', status: 'caution', selected: false, dimmed: false },
      { id: 2, name: 'Pivot 2', status: 'none', selected: true, dimmed: true },
    ])
  })

  it('dims nothing without a window', () => {
    expect(pivotFeatures([pivot(1, 44.1)], null, null).features[0].properties.dimmed).toBe(false)
  })

  it('draws the circle at its radius, or the default without one', () => {
    const [feature] = pivotFeatures([pivot(1, 44.1, [], null)], null, null).features
    const ring = feature.geometry.coordinates as LngLat[][]
    expect(distanceM([-89.5, 44.1], ring[0][0])).toBeCloseTo(1300 / 3.28084, 0)
  })

  it('draws a linear move as its rectangle', () => {
    const linear = {
      ...pivot(1, 44.1),
      kind: 'linear' as const,
      radius_ft: null,
      length_ft: 1300,
      travel_ft: 2640,
      travel_bearing_deg: 45,
    }
    const [feature] = pivotFeatures([linear], null, null).features
    const corners = (feature.geometry.coordinates as LngLat[][])[0]
    expect(corners).toHaveLength(5)
    expect(distanceM(corners[0], corners[1]) * 3.28084).toBeCloseTo(1300, 0)
    expect(distanceM(corners[1], corners[2]) * 3.28084).toBeCloseTo(2640, 0)
    expect(bearing(corners[2], corners[1])).toBeCloseTo(45, 0) // turned to its direction of travel
  })

  it('draws a point kind at its location', () => {
    const traveler = { ...pivot(1, 44.1), kind: 'traveler' as const, radius_ft: null }
    expect(pivotFeatures([traveler], null, null).features[0].geometry).toEqual({
      type: 'Point',
      coordinates: [-89.5, 44.1],
    })
  })
})

describe('groupFeatures', () => {
  const grouped = (id: number, latitude: number, group: number | null, kind: MapPivot['kind'] = 'center') => ({
    ...pivot(id, latitude),
    kind,
    radius_ft: kind === 'center' ? 1300 : null,
    pivot_group_id: group,
  })

  it('outlines each group around its systems shown, with a margin', () => {
    const pivots = [grouped(1, 44.1, 7), grouped(2, 44.12, 7, 'drip'), grouped(3, 44.3, null)]
    const farms = [{ id: 1, name: 'Farm', pivot_groups: [{ id: 7, name: 'East gauge' }], pivots }]
    const { features } = groupFeatures(farms, pivots)
    expect(features).toHaveLength(1)
    expect(features[0].properties).toEqual({ name: 'East gauge' })
    const outline = features[0].geometry.coordinates as LngLat[][]
    // The pivot's far edge and the drip block, but not the ungrouped pivot
    const north = (1300 / 3.28084 + GROUP_MARGIN_M / 2) / 111_000
    expect(pointInPolygon([-89.5, 44.1 - north], outline)).toBe(true)
    expect(pointInPolygon([-89.5, 44.12], outline)).toBe(true)
    expect(pointInPolygon([-89.5, 44.3], outline)).toBe(false)
  })

  it('leaves out a group with none of its systems shown', () => {
    const pivots = [grouped(1, 44.1, 7)]
    const farms = [{ id: 1, name: 'Farm', pivot_groups: [{ id: 7, name: 'East gauge' }], pivots }]
    expect(groupFeatures(farms, []).features).toEqual([])
  })
})

describe('pivotBounds', () => {
  it('covers every pivot to its edge', () => {
    const [[west, south], [east, north]] = pivotBounds([pivot(1, 44.1), pivot(2, 44.3)])!
    expect(south).toBeLessThan(44.1)
    expect(north).toBeGreaterThan(44.3)
    expect(west).toBeLessThan(-89.5)
    expect(east).toBeGreaterThan(-89.5)
  })

  it('includes a point kind', () => {
    const drip = { ...pivot(2, 44.5), kind: 'drip' as const, radius_ft: null }
    expect(pivotBounds([pivot(1, 44.1), drip])![1][1]).toBe(44.5)
  })

  it('is null without pivots', () => {
    expect(pivotBounds([])).toBeNull()
  })
})
