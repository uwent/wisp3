import { describe, expect, it } from 'vitest'

import {
  appliedLabel,
  common,
  farmRows,
  fieldHasEntry,
  rainFields,
  type DayFarm,
  type DayField,
  type DayPivot,
  type DayPlanting,
} from './dailyEntry'

const planting = (id: number, values: Partial<DayPlanting> = {}): DayPlanting => ({
  id,
  plant_name: 'Corn',
  variety: null,
  partial: false,
  area_acres: 10,
  plot_length_ft: null,
  plot_width_ft: null,
  entry: null,
  cover: null,
  ...values,
})
const field = (id: number, plantings: DayPlanting[] = [planting(id * 10)]): DayField => ({
  id,
  name: `Field ${id}`,
  area_acres: 10,
  rain_model: null,
  entry: null,
  plantings,
})
const pivot = (id: number, fields: DayField[], pivot_group_id: number | null = null): DayPivot => ({
  id,
  name: `Pivot ${id}`,
  kind: 'center',
  kind_name: 'Pivot',
  pivot_group_id,
  pump_capacity_gpm: null,
  irrigation: null,
  fields,
})

describe('farmRows', () => {
  it('lists pivot groups, then other pivots, then pivots with nothing in season', () => {
    const grouped = pivot(1, [field(1)], 7)
    const alone = pivot(2, [field(2)])
    const idle = pivot(3, [field(3, [])])
    const idleInGroup = pivot(4, [field(4, [])], 8)
    const farm: DayFarm = {
      id: 1,
      name: 'Home',
      pivot_groups: [
        { id: 7, name: 'Gauge' },
        { id: 8, name: 'Idle gauge' },
      ],
      pivots: [grouped, alone, idle, idleInGroup],
    }
    const rows = farmRows(farm)
    expect(rows.groups).toEqual([{ id: 7, name: 'Gauge', pivots: [grouped] }])
    expect(rows.pivots).toEqual([alone])
    expect(rows.idle).toEqual([idle, idleInGroup])
  })
})

describe('rain fill-down', () => {
  it('fills only fields in season', () => {
    const growing = field(1)
    expect(rainFields([pivot(1, [growing, field(2, [])])])).toEqual([growing])
  })

  it('shows the fields’ value when all agree, and varies when not', () => {
    expect(common([0.4, 0.4])).toEqual({ value: 0.4, varies: false })
    expect(common([null, null])).toEqual({ value: null, varies: false })
    expect(common([0.4, null])).toEqual({ value: null, varies: true })
    expect(common([])).toEqual({ value: null, varies: false })
  })
})

describe('appliedLabel', () => {
  it('says how many fields a pivot’s irrigation reaches', () => {
    expect(appliedLabel(null, 6)).toBe('All 6 fields')
    expect(appliedLabel([1, 2, 3, 4, 5], 6)).toBe('5 of 6 fields')
    expect(appliedLabel(null, 1)).toBe('Its field')
  })
})

describe('fieldHasEntry', () => {
  it('counts a plot’s entry or reading', () => {
    expect(fieldHasEntry(field(1))).toBe(false)
    const plot = planting(2, { partial: true, entry: { irrigation_in: 0.5, soil_moisture_pct: null } })
    expect(fieldHasEntry(field(1, [plot]))).toBe(true)
    const read = planting(3, { cover: { kind: 'pct_cover', value: 40, due: false, last_date: null } })
    expect(fieldHasEntry(field(1, [read]))).toBe(true)
  })
})
