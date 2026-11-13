import { describe, expect, it } from 'vitest'

import { fieldsOn } from './irrigation'

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
