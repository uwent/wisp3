import { beforeEach, describe, expect, it } from 'vitest'

import { lastPlanting, lastSoil, rememberPlanting, rememberSoil } from './lastChoices'

const corn = { plant_id: 1, season_start: '2026-04-15', emergence_date: '2026-05-10', end_date: '2026-09-20' }

describe('last choices', () => {
  beforeEach(() => sessionStorage.clear())

  it('remembers the last planting for its season', () => {
    expect(lastPlanting(2026)).toBeNull()
    rememberPlanting(corn)
    expect(lastPlanting(2026)).toEqual(corn)
    expect(lastPlanting(2027)).toBeNull()
  })

  it('ignores what it cannot read', () => {
    sessionStorage.setItem('setup.lastPlanting', '{"plant_id":"1"}')
    expect(lastPlanting(2026)).toBeNull()
    sessionStorage.setItem('setup.lastSoil', 'sand')
    expect(lastSoil()).toBeNull()
  })

  it('remembers the last soil', () => {
    expect(lastSoil()).toBeNull()
    rememberSoil(4)
    expect(lastSoil()).toBe(4)
  })
})
