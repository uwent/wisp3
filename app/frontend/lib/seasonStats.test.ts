import { describe, expect, it } from 'vitest'

import type { FieldDay } from '@/types/serializers'

import { addDays } from './dates'
import { median, seasonStats } from './seasonStats'

// A day with the model's rain, used by the balance, unless overridden
const day = (i: number, overrides: Partial<FieldDay> = {}): FieldDay =>
  ({
    date: addDays('2026-07-01', i),
    rain: 0,
    rain_source: 'model',
    rain_model: 0,
    irrigation: 0,
    irrigation_source: 'none',
    deep_drainage: 0,
    ...overrides,
  }) as FieldDay

const entered = (i: number, rain: number, model: number) => day(i, { rain, rain_source: 'entered', rain_model: model })
const modeled = (i: number, rain: number) => day(i, { rain, rain_model: rain })

describe('season stats', () => {
  it('takes the middle value, or the mean of the middle two', () => {
    expect([median([]), median([3, 1, 2]), median([4, 1, 3, 2])]).toEqual([null, 2, 2.5])
  })

  it('counts entered and modeled rain, with rain days at measurable amounts', () => {
    const stats = seasonStats([entered(0, 0.8, 0.5), entered(1, 0, 0.3), modeled(2, 0.005), modeled(3, 0.4), day(4, { rain_source: 'group', rain: 0.2, rain_model: null })])
    expect(stats.entered).toEqual({ readings: 3, rainDays: 2, inches: 1 })
    // 0.5 + 0.3 + 0.4: the 0.005 drizzle isn't a rain day
    expect(stats.modeled).toEqual({ days: 3, inches: 1.2 })
  })

  it('sets the gauge against the model, day by day', () => {
    const stats = seasonStats([
      entered(0, 0.8, 0.5), // both, off by more than 0.1 and 25%
      entered(1, 0.55, 0.5), // both, close
      entered(2, 0.3, 0), // missed by the model
      entered(3, 0, 0.4), // zeroed
      modeled(4, 0.2), // no reading
      entered(5, 0, 0), // both dry: not counted anywhere
    ])
    expect(stats.comparison).toEqual({
      both: { days: 2, inches: 1.35, disagree: 1, typicalAdjustment: 0.175, ratio: 1.35 },
      missed: { days: 1, inches: 0.3 },
      zeroed: { days: 1, inches: 0.4 },
      noReading: { days: 1, inches: 0.2 },
    })
  })

  it('counts the modeled rain a field using only entered rain left out', () => {
    const stats = seasonStats([day(0, { rain: 0, rain_source: 'none', rain_model: 0.6 }), day(1, { rain_source: 'none', rain_model: 0 }), entered(2, 0.4, 0.3)])
    expect(stats.leftOut).toEqual({ days: 1, inches: 0.6 })
    expect(stats.comparison.noReading).toEqual({ days: 1, inches: 0.6 })
  })

  it('finds the typical gap between irrigations and the typical amount', () => {
    const irrigation = (i: number, inches: number) => day(i, { irrigation: inches, irrigation_source: 'entered' })
    const stats = seasonStats([irrigation(0, 1), day(1), day(2), irrigation(3, 0.5), day(4), irrigation(5, 0.75), irrigation(9, 0.75)])
    expect(stats.irrigation).toEqual({ days: 4, inches: 3, typicalInterval: 3, typicalAmount: 0.75 })
    expect(seasonStats([irrigation(0, 1)]).irrigation).toMatchObject({ typicalInterval: null, typicalAmount: 1 })
  })

  it('totals deep drainage, and has nothing to compare without data', () => {
    expect(seasonStats([day(0, { deep_drainage: 0.25 }), day(1, { deep_drainage: 0.5 })]).deepDrainage).toBe(0.75)
    const empty = seasonStats([])
    expect(empty.comparison.both).toEqual({ days: 0, inches: 0, disagree: 0, typicalAdjustment: null, ratio: null })
    expect(empty.irrigation).toEqual({ days: 0, inches: 0, typicalInterval: null, typicalAmount: null })
  })
})
