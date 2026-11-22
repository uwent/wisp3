import { describe, expect, it } from 'vitest'

import {
  canUseHours,
  canUsePercent,
  circleNoun,
  enteredAs,
  fieldOverride,
  fieldsOn,
  percentInches,
  sameAsBefore,
  savedAmount,
  unitsFor,
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

describe('run hours', () => {
  it("needs the pump capacity and every field's area", () => {
    const field = { area_acres: 40 }
    expect(canUseHours({ pump_capacity_gpm: 800, fields: [field, field] })).toBe(true)
    expect(canUseHours({ pump_capacity_gpm: 800, fields: [] })).toBe(true)
    expect(canUseHours({ pump_capacity_gpm: null, fields: [field] })).toBe(false)
    expect(canUseHours({ pump_capacity_gpm: 800, fields: [field, { area_acres: null }] })).toBe(false)
  })
})

describe('the percent timer', () => {
  it('needs a pivot or linear with its depth at 100%', () => {
    expect(canUsePercent({ kind: 'center', inches_at_100: 0.2 })).toBe(true)
    expect(canUsePercent({ kind: 'linear', inches_at_100: 0.2 })).toBe(true)
    expect(canUsePercent({ kind: 'center', inches_at_100: null })).toBe(false)
    expect(canUsePercent({ kind: 'traveler', inches_at_100: 0.2 })).toBe(false)
  })

  it('offers the units a system can convert, inches first', () => {
    const system = { kind: 'center', inches_at_100: 0.2, pump_capacity_gpm: 800, fields: [] }
    expect(unitsFor(system)).toEqual(['inches', 'hours', 'percent'])
    expect(unitsFor({ ...system, pump_capacity_gpm: null })).toEqual(['inches', 'percent'])
    expect(unitsFor({ ...system, kind: 'drip' })).toEqual(['inches', 'hours'])
  })

  it('puts on the depth at 100% × 100 ÷ percent for each circle', () => {
    expect(percentInches(0.2, 100)).toBeCloseTo(0.2)
    expect(percentInches(0.2, 40)).toBeCloseTo(0.5)
    expect(percentInches(0.2, 40, 0.5)).toBeCloseTo(0.25)
    expect(percentInches(0.2, 50, null)).toBeCloseTo(0.4)
    expect(percentInches(null, 40)).toBeNull()
    expect(percentInches(0.2, null)).toBeNull()
    expect(percentInches(0.2, 0)).toBeNull()
    expect(percentInches(0.2, 120)).toBeNull()
  })

  it('names a circle by the kind', () => {
    expect(circleNoun('center')).toBe('circle')
    expect(circleNoun('linear')).toBe('pass')
  })
})

describe('how an irrigation was entered', () => {
  it('takes inches first, then the percent timer, then run hours', () => {
    expect(enteredAs({ inches: null, run_hours: 6 })).toBe('hours')
    expect(enteredAs({ inches: 0.5, run_hours: null })).toBe('inches')
    expect(enteredAs({ inches: null, run_hours: null, percent_timer: 40 })).toBe('percent')
    expect(enteredAs(null)).toBe('inches')
  })

  it('gives the saved amount for the box shown', () => {
    const irrigation = { inches: 0.5, run_hours: null }
    expect(savedAmount(irrigation, 'inches')).toBe(0.5)
    expect(savedAmount(irrigation, 'hours')).toBeNull()
    expect(savedAmount({ inches: null, run_hours: null, percent_timer: 40 }, 'percent')).toBe(40)
    expect(savedAmount(null, 'inches')).toBeNull()
  })
})

describe('fieldOverride', () => {
  it('shows a field as it was saved, else in the percent while its system is', () => {
    expect(fieldOverride({ irrigation_in: 0.4, irrigation_pct: 50 }, 'inches', true)).toEqual({
      unit: 'percent',
      value: 50,
    })
    expect(fieldOverride({ irrigation_in: 0.4, irrigation_pct: null }, 'percent', true)).toEqual({
      unit: 'inches',
      value: 0.4,
    })
    expect(fieldOverride(undefined, 'percent', true)).toEqual({ unit: 'percent', value: null })
    expect(fieldOverride(undefined, 'percent', false)).toEqual({ unit: 'inches', value: null })
    expect(fieldOverride({ irrigation_in: 0.4, irrigation_pct: 50 }, 'percent', false)).toEqual({
      unit: 'inches',
      value: 0.4,
    })
  })
})

describe('sameAsBefore', () => {
  const pivot = {
    kind: 'center',
    inches_at_100: 0.2,
    pump_capacity_gpm: 800,
    fields: [
      { id: 1, area_acres: 60 },
      { id: 2, area_acres: 70 },
    ],
  }

  it('offers nothing without an irrigation the day before', () => {
    expect(sameAsBefore(null, pivot)).toBeNull()
  })

  it('offers inches, run hours or a percent, as they were entered', () => {
    expect(sameAsBefore({ inches: 0.8, run_hours: null, field_ids: null }, pivot)).toEqual({
      unit: 'inches',
      value: 0.8,
      circles: null,
      fieldIds: [1, 2],
    })
    expect(sameAsBefore({ inches: null, run_hours: 10, field_ids: [2] }, pivot)).toEqual({
      unit: 'hours',
      value: 10,
      circles: null,
      fieldIds: [2],
    })
    expect(
      sameAsBefore({ inches: null, run_hours: null, percent_timer: 40, circles: 0.5, field_ids: null }, pivot),
    ).toEqual({ unit: 'percent', value: 40, circles: 0.5, fieldIds: [1, 2] })
  })

  it("keeps only fields still on the system, and leaves out units it can't convert", () => {
    expect(sameAsBefore({ inches: 0.5, run_hours: null, field_ids: [9] }, pivot)?.fieldIds).toEqual([1, 2])
    expect(
      sameAsBefore({ inches: null, run_hours: 10, field_ids: null }, { ...pivot, pump_capacity_gpm: null }),
    ).toBeNull()
    expect(
      sameAsBefore(
        { inches: null, run_hours: null, percent_timer: 40, field_ids: null },
        { ...pivot, inches_at_100: null },
      ),
    ).toBeNull()
  })
})
