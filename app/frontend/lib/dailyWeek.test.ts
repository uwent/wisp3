import { describe, expect, it } from 'vitest'

import {
  cellErrors,
  changes,
  defaultUnit,
  otherText,
  irrigationKey,
  keyMove,
  leavesBox,
  nextCell,
  overwriteMessage,
  rainKey,
  savedTexts,
  weekLabel,
  type WeekFarm,
  type WeekIrrigationDay,
  type WeekIrrigationRow,
  type WeekRainDay,
  type WeekRainRow,
} from './dailyWeek'
import type { IrrigationUnit } from './irrigation'
import { units } from './units'

const imperial = units('imperial')
const metric = units('metric')
const dates = ['2026-07-14', '2026-07-15', '2026-07-16']

const rainDay = (values: Partial<WeekRainDay> = {}): WeekRainDay => ({
  active: true,
  value: null,
  varies: false,
  fields: [
    { id: 1, name: 'North', rain_in: null },
    { id: 2, name: 'South', rain_in: null },
  ],
  ...values,
})
const irrigationDay = (values: Partial<WeekIrrigationDay> = {}): WeekIrrigationDay => ({
  active: true,
  irrigation: null,
  some_fields: null,
  ...values,
})

const rainRow: WeekRainRow = {
  key: 'group-3',
  name: 'East',
  kind: 'group',
  systems: 2,
  days: [
    rainDay(),
    rainDay({ value: 0.4, fields: [{ id: 1, name: 'North', rain_in: 0.4 }] }),
    rainDay({
      varies: true,
      fields: [
        { id: 1, name: 'North', rain_in: 0.4 },
        { id: 2, name: 'South', rain_in: 0.6 },
      ],
    }),
  ],
}
const irrigationRow: WeekIrrigationRow = {
  id: 12,
  name: 'River',
  kind: 'center',
  kind_name: 'Pivot',
  hours: true,
  inches_at_100: 0.2,
  days: [
    irrigationDay({
      irrigation: { inches: 0.8, run_hours: null, percent_timer: null, circles: null, field_ids: null },
    }),
    irrigationDay({
      irrigation: { inches: 0.6, run_hours: null, percent_timer: null, circles: null, field_ids: [1] },
      some_fields: ['North'],
    }),
    irrigationDay(),
  ],
}
const farms: WeekFarm[] = [{ id: 1, name: 'Home', rain_rows: [rainRow], irrigation_rows: [irrigationRow] }]

function edit(edits: Record<string, string>, unit: Record<number, IrrigationUnit> = { 12: 'inches' }, u = imperial) {
  const texts = { ...savedTexts(farms, dates, unit, u), ...edits }
  return changes(farms, dates, texts, unit, u)
}

describe('weekLabel', () => {
  it('names a week within a month, across months and across years', () => {
    expect(weekLabel('2026-07-14', '2026-07-20')).toBe('Jul 14–20')
    expect(weekLabel('2026-06-28', '2026-07-04')).toBe('Jun 28–Jul 4')
    expect(weekLabel('2025-12-29', '2026-01-04')).toBe('Dec 29, 2025–Jan 4, 2026')
  })
})

describe('defaultUnit', () => {
  it("takes the unit of the week's latest entry, and inches when that unit can't be used", () => {
    const row = (hours: boolean, percent: boolean, ...irrigations: WeekIrrigationDay['irrigation'][]) => ({
      ...irrigationRow,
      hours,
      inches_at_100: percent ? 0.2 : null,
      days: irrigations.map((irrigation) => irrigationDay({ irrigation })),
    })
    const byHours = { inches: null, run_hours: 6, percent_timer: null, circles: null, field_ids: null }
    const byInches = { inches: 0.8, run_hours: null, percent_timer: null, circles: null, field_ids: null }
    const byPercent = { inches: null, run_hours: null, percent_timer: 40, circles: null, field_ids: null }
    expect(defaultUnit(row(true, true, byInches, byHours, null))).toBe('hours')
    expect(defaultUnit(row(true, true, byHours, byInches))).toBe('inches')
    expect(defaultUnit(row(true, true, byHours, byPercent))).toBe('percent')
    expect(defaultUnit(row(true, true, null))).toBe('inches')
    expect(defaultUnit(row(false, true, byHours))).toBe('inches')
    expect(defaultUnit(row(true, false, byPercent))).toBe('inches')
  })
})

describe('otherText', () => {
  it('shows a day saved in another unit as it was entered', () => {
    const day = (irrigation: WeekIrrigationDay['irrigation']) => irrigationDay({ irrigation })
    const byPercent = { inches: null, run_hours: null, percent_timer: 40, circles: null, field_ids: null }
    const byHours = { inches: null, run_hours: 6, percent_timer: null, circles: null, field_ids: null }
    expect(otherText(day(byPercent), 'inches', imperial)).toBe('40%')
    expect(otherText(day(byHours), 'percent', imperial)).toBe('6 h')
    expect(otherText(day(byPercent), 'percent', imperial)).toBe('')
    expect(otherText(day(null), 'inches', imperial)).toBe('')
  })
})

describe('changes', () => {
  it('sends nothing for cells left as saved', () => {
    expect(edit({})).toEqual({ cells: [], inputs: [] })
    // The same amount typed differently, or with spaces, is a change only when its text differs
    expect(edit({ [rainKey(rainRow, dates[1])]: ' 0.4 ' }).inputs).toEqual([])
  })

  it("fills a rain cell's fields with what's typed, in stored inches", () => {
    expect(edit({ [rainKey(rainRow, dates[0])]: '0.5' }).inputs).toEqual([
      { name: 'days[2026-07-14][fields][1][rain_in]', value: '0.5' },
      { name: 'days[2026-07-14][fields][2][rain_in]', value: '0.5' },
    ])
    const mm = savedTexts(farms, dates, { 12: 'inches' }, metric)
    expect(
      changes(farms, dates, { ...mm, [rainKey(rainRow, dates[0])]: '25.4' }, { 12: 'inches' }, metric).inputs[0],
    ).toEqual({
      name: 'days[2026-07-14][fields][1][rain_in]',
      value: '1',
    })
  })

  it('clears rain cleared, and marks a cell that had different amounts', () => {
    const { cells, inputs } = edit({ [rainKey(rainRow, dates[1])]: '', [rainKey(rainRow, dates[2])]: '0.5' })
    expect(inputs).toContainEqual({ name: 'days[2026-07-15][fields][1][rain_in]', value: '' })
    expect(cells.map((cell) => [cell.date, cell.varies])).toEqual([
      ['2026-07-15', false],
      ['2026-07-16', true],
    ])
  })

  it('sends a new irrigation for all fields, and keeps the fields a saved one applies to', () => {
    expect(edit({ [irrigationKey(irrigationRow, dates[2])]: '1' }).inputs).toEqual([
      { name: 'days[2026-07-16][pivots][12][inches]', value: '1' },
      { name: 'days[2026-07-16][pivots][12][run_hours]', value: '' },
      { name: 'days[2026-07-16][pivots][12][percent_timer]', value: '' },
      { name: 'days[2026-07-16][pivots][12][circles]', value: '' },
    ])
    expect(edit({ [irrigationKey(irrigationRow, dates[1])]: '0.7' }).inputs).toEqual([
      { name: 'days[2026-07-15][pivots][12][inches]', value: '0.7' },
      { name: 'days[2026-07-15][pivots][12][run_hours]', value: '' },
      { name: 'days[2026-07-15][pivots][12][percent_timer]', value: '' },
      { name: 'days[2026-07-15][pivots][12][circles]', value: '' },
      { name: 'days[2026-07-15][pivots][12][field_ids][]', value: '' },
      { name: 'days[2026-07-15][pivots][12][field_ids][]', value: '1' },
    ])
  })

  it('removes an irrigation cleared, and sends run hours in the hours unit', () => {
    expect(edit({ [irrigationKey(irrigationRow, dates[0])]: '' }).inputs).toEqual([
      { name: 'days[2026-07-14][pivots][12][inches]', value: '' },
      { name: 'days[2026-07-14][pivots][12][run_hours]', value: '' },
      { name: 'days[2026-07-14][pivots][12][percent_timer]', value: '' },
      { name: 'days[2026-07-14][pivots][12][circles]', value: '' },
    ])
    // In hours, a day saved in inches starts blank: left alone, it's kept
    expect(edit({}, { 12: 'hours' }).inputs).toEqual([])
    expect(edit({ [irrigationKey(irrigationRow, dates[0])]: '6' }, { 12: 'hours' }).inputs).toEqual([
      { name: 'days[2026-07-14][pivots][12][inches]', value: '' },
      { name: 'days[2026-07-14][pivots][12][run_hours]', value: '6' },
      { name: 'days[2026-07-14][pivots][12][percent_timer]', value: '' },
      { name: 'days[2026-07-14][pivots][12][circles]', value: '' },
    ])
  })

  it('sends a percent in the percent unit, for one circle', () => {
    expect(edit({ [irrigationKey(irrigationRow, dates[2])]: '40' }, { 12: 'percent' }).inputs).toEqual([
      { name: 'days[2026-07-16][pivots][12][inches]', value: '' },
      { name: 'days[2026-07-16][pivots][12][run_hours]', value: '' },
      { name: 'days[2026-07-16][pivots][12][percent_timer]', value: '40' },
      { name: 'days[2026-07-16][pivots][12][circles]', value: '' },
    ])
  })

  it("leaves out a cell that can't be read", () => {
    expect(edit({ [rainKey(rainRow, dates[0])]: 'lots' })).toEqual({ cells: [], inputs: [] })
  })
})

describe('overwriteMessage', () => {
  it('lists the cells replacing different amounts, or is null', () => {
    expect(overwriteMessage(edit({ [rainKey(rainRow, dates[0])]: '0.5' }).cells)).toBeNull()
    expect(overwriteMessage(edit({ [rainKey(rainRow, dates[2])]: '0.5' }).cells)).toBe(
      'This replaces different amounts on each field for: East, Thu, Jul 16. Save anyway?',
    )
  })
})

describe('cellErrors', () => {
  it("puts each error at its cell, a rain error at the row's cell", () => {
    const found = cellErrors(farms, dates, {
      'days.2026-07-15.fields.1.rain_in': ["can't be entered for a future date"],
      'days.2026-07-16.pivots.12.run_hours': 'can be used only when…',
    })
    expect(found).toEqual({
      [rainKey(rainRow, dates[1])]: {
        label: 'East rain',
        date: dates[1],
        message: "can't be entered for a future date",
      },
      [irrigationKey(irrigationRow, dates[2])]: {
        label: 'River irrigation',
        date: dates[2],
        message: 'can be used only when…',
      },
    })
  })
})

describe('keyboard navigation', () => {
  const cells = [
    { row: 0, col: 0 },
    { row: 0, col: 2 },
    { row: 1, col: 0 },
    { row: 1, col: 1 },
    { row: 3, col: 2 },
  ]

  it('moves to the nearest cell taking a value in each direction, staying at the edge', () => {
    expect(nextCell(cells, { row: 0, col: 0 }, 'right')).toEqual({ row: 0, col: 2 })
    expect(nextCell(cells, { row: 0, col: 2 }, 'left')).toEqual({ row: 0, col: 0 })
    expect(nextCell(cells, { row: 0, col: 0 }, 'down')).toEqual({ row: 1, col: 0 })
    expect(nextCell(cells, { row: 0, col: 2 }, 'down')).toEqual({ row: 3, col: 2 })
    expect(nextCell(cells, { row: 3, col: 2 }, 'up')).toEqual({ row: 0, col: 2 })
    expect(nextCell(cells, { row: 1, col: 1 }, 'right')).toBeNull()
    expect(nextCell(cells, { row: 0, col: 0 }, 'up')).toBeNull()
  })

  it('reads arrows and Enter (down) as moves, and moves the caret within a box first', () => {
    expect(keyMove('Enter')).toBe('down')
    expect(keyMove('ArrowLeft')).toBe('left')
    expect(keyMove('a')).toBeNull()
    expect(leavesBox('left', 0, 0, 3)).toBe(true)
    expect(leavesBox('left', 2, 2, 3)).toBe(false)
    expect(leavesBox('right', 3, 3, 3)).toBe(true)
    expect(leavesBox('right', 1, 1, 3)).toBe(false)
    expect(leavesBox('right', 0, 3, 3)).toBe(true) // all selected
    expect(leavesBox('up', 1, 1, 3)).toBe(true)
  })
})
