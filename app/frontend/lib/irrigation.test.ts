import { describe, expect, it } from 'vitest'

import {
  CALCULATOR_LIMITS,
  calculatorMethods,
  circleNoun,
  common,
  fieldsOn,
  hoursInches,
  outOfRange,
  percentInches,
  rainfedOn,
} from './irrigation'

describe('fieldsOn', () => {
  const stayed = { id: 1, name: 'Stayed', here: true, seasons: [{ from: '2026-04-01', to: '2026-10-01', here: true }] }
  // Grew here in 2025, then moved to another system
  const movedAway = {
    id: 2,
    name: 'Away',
    here: false,
    seasons: [{ from: '2025-04-01', to: '2025-10-01', here: true }],
  }
  // Grew elsewhere in 2025, then moved here
  const movedHere = {
    id: 3,
    name: 'Here',
    here: true,
    seasons: [{ from: '2025-04-01', to: '2025-10-01', here: false }],
  }
  const fields = [stayed, movedAway, movedHere]

  it('takes the system a season ran on', () => {
    expect(fieldsOn(fields, '2025-07-01').map((f) => f.name)).toEqual(['Stayed', 'Away'])
  })

  it("takes the field's system now on days with nothing planted", () => {
    expect(fieldsOn(fields, '2026-07-01').map((f) => f.name)).toEqual(['Stayed', 'Here'])
    expect(fieldsOn(fields, '2025-12-01').map((f) => f.name)).toEqual(['Stayed', 'Here'])
  })
})

describe('rainfedOn', () => {
  it("is the field's crop that day, rainfed or not, and not rainfed with none", () => {
    const field = {
      id: 1,
      name: 'East 9',
      here: true,
      seasons: [
        { from: '2026-04-01', to: '2026-07-15', here: true, rainfed: true },
        { from: '2026-07-16', to: '2026-10-10', here: true, rainfed: false },
      ],
    }
    expect(rainfedOn(field, '2026-06-01')).toBe(true)
    expect(rainfedOn(field, '2026-08-01')).toBe(false)
    expect(rainfedOn(field, '2026-11-01')).toBe(false)
  })

  it('is false while an irrigated plot grows within a rainfed crop, and true when every planting is rainfed', () => {
    const crop = { from: '2026-04-01', to: '2026-10-10', here: true, rainfed: true }
    const plot = { from: '2026-06-01', to: '2026-08-31', here: true, rainfed: false }
    const field = { id: 1, name: 'East 9', here: true, seasons: [crop, plot] }
    expect(rainfedOn(field, '2026-05-01')).toBe(true)
    expect(rainfedOn(field, '2026-07-01')).toBe(false)
    expect(rainfedOn({ ...field, seasons: [crop, { ...plot, rainfed: true }] }, '2026-07-01')).toBe(true)
  })
})

describe('the calculator', () => {
  it('offers run hours for any system, and the percent timer on a pivot or linear', () => {
    expect(calculatorMethods({ kind: 'center' })).toEqual(['hours', 'percent'])
    expect(calculatorMethods({ kind: 'linear' })).toEqual(['hours', 'percent'])
    expect(calculatorMethods({ kind: 'traveler' })).toEqual(['hours'])
  })

  it('spreads run hours over the acres watered', () => {
    // 1,000 gpm for 20 hours over 190.6 acres: 1,200,000 gallons, 0.23 in
    expect(hoursInches(1000, 20, [94.7, 95.9])).toBeCloseTo(0.2319, 4)
    expect(hoursInches(1000, 0, [100])).toBe(0)
  })

  it('needs hours and every area for run hours', () => {
    expect(hoursInches(1000, null, [100])).toBeNull()
    expect(hoursInches(1000, 10, [100, null])).toBeNull()
    expect(hoursInches(1000, 10, [])).toBeNull()
    expect(hoursInches(null, 10, [100])).toBeNull()
  })

  it('puts on the depth at 100% × 100 ÷ percent for each circle', () => {
    expect(percentInches(0.2, 100)).toBeCloseTo(0.2)
    expect(percentInches(0.2, 40)).toBeCloseTo(0.5)
    expect(percentInches(0.2, 40, 2)).toBeCloseTo(1.0)
    expect(percentInches(0.2, 40, 0.5)).toBeCloseTo(0.25)
    expect(percentInches(0.2, 40, null)).toBeCloseTo(0.5)
  })

  it('reads nothing for a percent out of range, no depth at 100% or no circles', () => {
    expect(percentInches(0.2, 0)).toBeNull()
    expect(percentInches(0.2, 120)).toBeNull()
    expect(percentInches(null, 40)).toBeNull()
    expect(percentInches(0.2, null)).toBeNull()
    expect(percentInches(0.2, 40, 0)).toBeNull()
  })

  it('checks what is typed against its range: more than 0 (or at least its minimum), at most its maximum', () => {
    expect(outOfRange(null, CALCULATOR_LIMITS.hours)).toBeNull()
    expect(outOfRange(0, CALCULATOR_LIMITS.hours)).toBe('low')
    expect(outOfRange(-2, CALCULATOR_LIMITS.circles)).toBe('low')
    expect(outOfRange(24, CALCULATOR_LIMITS.hours)).toBeNull()
    expect(outOfRange(25, CALCULATOR_LIMITS.hours)).toBe('high')
    expect(outOfRange(0.5, CALCULATOR_LIMITS.percent)).toBe('low')
    expect(outOfRange(1, CALCULATOR_LIMITS.percent)).toBeNull()
    expect(outOfRange(100, CALCULATOR_LIMITS.percent)).toBeNull()
    expect(outOfRange(101, CALCULATOR_LIMITS.percent)).toBe('high')
    expect(outOfRange(0.5, CALCULATOR_LIMITS.circles)).toBeNull()
  })

  it('names a circle by the kind', () => {
    expect(circleNoun('center')).toBe('circle')
    expect(circleNoun('linear')).toBe('pass')
  })
})

describe('common', () => {
  it('gives the shared value, blank when all are blank, or varies', () => {
    expect(common([0.5, 0.5])).toEqual({ value: 0.5, varies: false })
    expect(common([null, null])).toEqual({ value: null, varies: false })
    expect(common([0.5, null])).toEqual({ value: null, varies: true })
    expect(common([0.5, 0.6])).toEqual({ value: null, varies: true })
    expect(common([])).toEqual({ value: null, varies: false })
  })
})
