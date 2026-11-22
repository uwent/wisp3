import { describe, expect, it } from 'vitest'

import {
  cellErrors,
  changes,
  irrigationKey,
  keyMove,
  leavesBox,
  nextCell,
  overwriteMessage,
  rainKey,
  savedTexts,
  settledText,
  weekLabel,
  type WeekDay,
  type WeekFarm,
  type WeekIrrigationRow,
  type WeekRainRow,
} from './dailyWeek'
import { units } from './units'

const imperial = units('imperial')
const metric = units('metric')
const dates = ['2026-07-14', '2026-07-15', '2026-07-16']

const weekDay = (values: Partial<WeekDay> = {}): WeekDay => ({
  active: true,
  value: null,
  varies: false,
  fields: [
    { id: 1, name: 'North', value: null },
    { id: 2, name: 'South', value: null },
  ],
  ...values,
})
const varied = weekDay({
  varies: true,
  fields: [
    { id: 1, name: 'North', value: 0.4 },
    { id: 2, name: 'South', value: 0.6 },
  ],
})

const rainRow: WeekRainRow = {
  key: 'group-3',
  name: 'East',
  kind: 'group',
  systems: 2,
  days: [weekDay(), weekDay({ value: 0.4, fields: [{ id: 1, name: 'North', value: 0.4 }] }), varied],
}
const irrigationRow: WeekIrrigationRow = {
  key: 'pivot-12',
  id: 12,
  name: 'River',
  kind: 'center',
  kind_name: 'Pivot',
  pump_capacity_gpm: null,
  inches_at_100: null,
  days: [
    weekDay({
      value: 0.8,
      fields: [
        { id: 1, name: 'North', value: 0.8 },
        { id: 2, name: 'South', value: 0.8 },
      ],
    }),
    varied,
    weekDay(),
  ],
}
const farms: WeekFarm[] = [{ id: 1, name: 'Home', rain_rows: [rainRow], irrigation_rows: [irrigationRow] }]

function edit(edits: Record<string, string>, u = imperial) {
  const texts = { ...savedTexts(farms, dates, u), ...edits }
  return changes(farms, dates, texts, u)
}

describe('weekLabel', () => {
  it('names a week within a month, across months and across years', () => {
    expect(weekLabel('2026-07-14', '2026-07-20')).toBe('Jul 14–20')
    expect(weekLabel('2026-06-28', '2026-07-04')).toBe('Jun 28–Jul 4')
    expect(weekLabel('2025-12-29', '2026-01-04')).toBe('Dec 29, 2025–Jan 4, 2026')
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
    const mm = savedTexts(farms, dates, metric)
    expect(changes(farms, dates, { ...mm, [rainKey(rainRow, dates[0])]: '25.4' }, metric).inputs[0]).toEqual({
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

  it("fills an irrigation cell's fields, clears them, and marks one that had different amounts", () => {
    expect(edit({ [irrigationKey(irrigationRow, dates[2])]: '1' }).inputs).toEqual([
      { name: 'days[2026-07-16][fields][1][irrigation_in]', value: '1' },
      { name: 'days[2026-07-16][fields][2][irrigation_in]', value: '1' },
    ])
    expect(edit({ [irrigationKey(irrigationRow, dates[0])]: '' }).inputs).toEqual([
      { name: 'days[2026-07-14][fields][1][irrigation_in]', value: '' },
      { name: 'days[2026-07-14][fields][2][irrigation_in]', value: '' },
    ])
    expect(edit({ [irrigationKey(irrigationRow, dates[1])]: '0.7' }).cells).toEqual([
      { key: irrigationKey(irrigationRow, dates[1]), label: 'River irrigation', date: dates[1], varies: true },
    ])
  })

  it("starts a varied cell blank, so leaving it keeps each field's amount", () => {
    expect(savedTexts(farms, dates, imperial)[irrigationKey(irrigationRow, dates[1])]).toBe('')
    expect(savedTexts(farms, dates, imperial)[irrigationKey(irrigationRow, dates[0])]).toBe('0.80')
  })

  it('shows two decimal places, and sends nothing for the same amount typed another way', () => {
    expect(settledText('1', imperial)).toBe('1.00')
    expect(settledText('0.456', imperial)).toBe('0.46')
    expect(settledText('', imperial)).toBe('')
    expect(settledText('lots', imperial)).toBe('lots')
    // Millimeters to one place
    expect(settledText('25.44', metric)).toBe('25.4')
    expect(savedTexts(farms, dates, metric)[irrigationKey(irrigationRow, dates[0])]).toBe('20.3')
    expect(edit({ [irrigationKey(irrigationRow, dates[0])]: '0.8' }).inputs).toEqual([])
    // Typed with more places, it's sent as shown
    expect(edit({ [irrigationKey(irrigationRow, dates[2])]: '0.456' }).inputs[0]).toEqual({
      name: 'days[2026-07-16][fields][1][irrigation_in]',
      value: '0.46',
    })
  })

  it('leaves alone a saved amount with more places than it shows', () => {
    const precise = { ...irrigationRow, days: [weekDay({ value: 0.177 }), weekDay(), weekDay()] }
    const week: WeekFarm[] = [{ id: 1, name: 'Home', rain_rows: [], irrigation_rows: [precise] }]
    const texts = savedTexts(week, dates, imperial)
    expect(texts[irrigationKey(precise, dates[0])]).toBe('0.18')
    expect(changes(week, dates, texts, imperial).inputs).toEqual([])
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
      'days.2026-07-16.fields.2.irrigation_in': 'must be greater than or equal to 0',
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
        message: 'must be greater than or equal to 0',
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
