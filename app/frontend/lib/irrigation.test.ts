import { describe, expect, it } from 'vitest'

import { canUseHours, enteredAsHours, fieldsOn, savedAmount } from './irrigation'

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

  it('tells an irrigation entered as run hours by its missing inches', () => {
    expect(enteredAsHours({ inches: null, run_hours: 6 })).toBe(true)
    expect(enteredAsHours({ inches: 0.5, run_hours: null })).toBe(false)
    expect(enteredAsHours(null)).toBe(false)
  })

  it('gives the saved amount for the box shown', () => {
    const irrigation = { inches: 0.5, run_hours: null }
    expect(savedAmount(irrigation, false)).toBe(0.5)
    expect(savedAmount(irrigation, true)).toBeNull()
    expect(savedAmount(null, false)).toBeNull()
  })
})
