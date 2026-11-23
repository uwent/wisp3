import { describe, expect, it } from 'vitest'

import {
  farmRows,
  fieldBox,
  fieldBoxes,
  fieldHasEntry,
  fieldRowBoxes,
  plotBox,
  rainFields,
  rainNote,
  rainView,
  rowAmount,
  savedIrrigation,
  systemBoxes,
  yesterdayBoxes,
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
  rainfed: false,
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
  inches_at_100: null,
  yesterday: null,
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
      use_model_precip: true,
      pivot_groups: [
        { id: 7, name: 'Gauge', use_model_precip: null },
        { id: 8, name: 'Idle gauge', use_model_precip: null },
      ],
      pivots: [grouped, alone, idle, idleInGroup],
    }
    const rows = farmRows(farm)
    expect(rows.groups).toEqual([{ id: 7, name: 'Gauge', use_model_precip: null, pivots: [grouped] }])
    expect(rows.pivots).toEqual([alone])
    expect(rows.idle).toEqual([idle, idleInGroup])
  })
})

describe('rainNote', () => {
  const farm = (use_model_precip: boolean): DayFarm => ({
    id: 1,
    name: 'Home',
    use_model_precip,
    pivot_groups: [],
    pivots: [],
  })

  it("notes a group's own setting only where it differs from its farm's", () => {
    expect(rainNote({ use_model_precip: null }, farm(false))).toBe('')
    expect(rainNote({ use_model_precip: false }, farm(false))).toBe('')
    expect(rainNote({ use_model_precip: false }, farm(true))).toBe(' · only entered rain counts')
    expect(rainNote({ use_model_precip: true }, farm(false))).toBe(' · modeled rain counts')
  })
})

describe('rain fill-down', () => {
  it('fills only fields in season', () => {
    const growing = field(1)
    expect(rainFields([pivot(1, [growing, field(2, [])])])).toEqual([growing])
  })

  it("shows the fields' entered value when all agree, else their shared amount entered or modeled, or varies", () => {
    const fields = [
      { ...field(1), rain_model: 0.2 },
      { ...field(2), rain_model: 0.2 },
    ]
    expect(rainView(fields, { 1: 0.4, 2: 0.4 })).toEqual({ value: 0.4, shown: 0.4, modeled: false, varies: false })
    expect(rainView(fields, { 1: null, 2: null })).toEqual({ value: null, shown: 0.2, modeled: true, varies: false })
    expect(rainView(fields, { 1: 0.2, 2: null })).toEqual({ value: null, shown: 0.2, modeled: false, varies: false })
    expect(rainView(fields, { 1: 0.4, 2: null })).toEqual({ value: null, shown: null, modeled: false, varies: true })
    const apart = [
      { ...field(1), rain_model: 0.2 },
      { ...field(2), rain_model: 0.3 },
    ]
    expect(rainView(apart, {})).toMatchObject({ value: null, modeled: true, varies: true })
  })
})

describe('irrigation boxes', () => {
  const plot = (id: number, irrigation_in: number | null = null) =>
    planting(id, { partial: true, entry: irrigation_in === null ? null : { irrigation_in, soil_moisture_pct: null } })
  const whole = { ...field(1), entry: { rain_in: null, irrigation_in: 0.8, soil_moisture_pct: null } }
  const withPlots = field(2, [planting(20), plot(21, 0.8), plot(22, 0.5)])
  const plotsOnly = field(3, [plot(31, 0.6), plot(32, 0.6)])
  const idle = field(4, [])
  const system = pivot(1, [whole, withPlots, plotsOnly, idle])

  it("fills a field's and its plots' boxes, and a system's fields in season with their plots", () => {
    expect(fieldBoxes(withPlots)).toEqual(['field-2', 'plot-21', 'plot-22'])
    expect(systemBoxes(system)).toEqual(['field-1', 'field-2', 'plot-21', 'plot-22', 'field-3', 'plot-31', 'plot-32'])
  })

  it("leaves a rainfed field or plot out of a system's or field's fill, and Same as yesterday", () => {
    const rainfed = field(5, [planting(50, { rainfed: true }), plot(51)])
    const mixed = field(6, [planting(60), plot(61), { ...plot(62), rainfed: true }])
    const dry = pivot(2, [rainfed, mixed])
    expect(systemBoxes(dry)).toEqual(['plot-51', 'field-6', 'plot-61'])
    expect(fieldBoxes(mixed)).toEqual(['field-6', 'plot-61'])
    // Its own box still takes what's typed in it
    expect(fieldRowBoxes(rainfed)).toEqual(['field-5'])
    const plotsOnly = field(7, [{ ...plot(71), rainfed: true }, plot(72)])
    expect(fieldRowBoxes(plotsOnly)).toEqual(['plot-72'])
    const before = { ...dry, yesterday: { fields: { 5: 0.5, 6: 0.4 }, plantings: { 62: 0.3 } } }
    expect(yesterdayBoxes(before)).toEqual({ 'field-6': 0.4, 'plot-51': null, 'plot-61': null })
  })

  it('reads every field and plot as saved', () => {
    expect(savedIrrigation([system])).toEqual({
      'field-1': 0.8,
      'field-2': null,
      'plot-21': 0.8,
      'plot-22': 0.5,
      'field-3': null,
      'plot-31': 0.6,
      'plot-32': 0.6,
      'field-4': null,
    })
  })

  it("shows a field's own amount, or for a field of plots only, theirs", () => {
    const values = savedIrrigation([system])
    expect(rowAmount(fieldRowBoxes(whole), values)).toEqual({ value: 0.8, varies: false })
    expect(rowAmount(fieldRowBoxes(withPlots), values)).toEqual({ value: null, varies: false })
    expect(rowAmount(fieldRowBoxes(plotsOnly), values)).toEqual({ value: 0.6, varies: false })
  })

  it("shows a system's shared amount, or varies", () => {
    const values = { ...savedIrrigation([system]) }
    expect(rowAmount(systemBoxes(system), values).varies).toBe(true)
    for (const box of systemBoxes(system)) values[box] = 0.7
    expect(rowAmount(systemBoxes(system), values)).toEqual({ value: 0.7, varies: false })
  })

  it("fills the day before's amounts for Same as yesterday", () => {
    expect(yesterdayBoxes(system)).toBeNull()
    const before = { ...system, yesterday: { fields: { 1: 0.5 }, plantings: { 21: 0.4 } } }
    expect(yesterdayBoxes(before)).toEqual({
      [fieldBox(1)]: 0.5,
      [fieldBox(2)]: null,
      [plotBox(21)]: 0.4,
      [plotBox(22)]: null,
      [fieldBox(3)]: null,
      [plotBox(31)]: null,
      [plotBox(32)]: null,
    })
  })
})

describe('fieldHasEntry', () => {
  it("counts a plot's entry or reading", () => {
    expect(fieldHasEntry(field(1))).toBe(false)
    const plot = planting(2, { partial: true, entry: { irrigation_in: 0.5, soil_moisture_pct: null } })
    expect(fieldHasEntry(field(1, [plot]))).toBe(true)
    const read = planting(3, { cover: { kind: 'pct_cover', value: 40, due: false, last_date: null } })
    expect(fieldHasEntry(field(1, [read]))).toBe(true)
  })
})
