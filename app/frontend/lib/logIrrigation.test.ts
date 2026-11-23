import { describe, expect, it } from 'vitest'

import { inSeason, lastIrrigationLine, replacing } from './logIrrigation'
import type { FieldCard } from './overview'
import { units } from './units'

const imperial = units('imperial')
const today = '2026-07-20'
const card = (id: number, last: { date: string; inches: number } | null) =>
  ({ id, name: `F${id}`, plantings: [{ last_irrigation: last }] }) as unknown as FieldCard

describe('inSeason', () => {
  it('is a day within one of its seasons on the system', () => {
    const season = { from: '2026-05-01', to: '2026-09-15', here: true }
    const field = { id: 1, name: 'North', acres: 60, here: true, seasons: [season] }
    expect(inSeason(field, '2026-05-01')).toBe(true)
    expect(inSeason(field, '2026-09-16')).toBe(false)
    expect(inSeason({ ...field, seasons: [{ ...season, here: false }] }, today)).toBe(false)
    expect(inSeason({ ...field, seasons: [] }, today)).toBe(false)
  })
})

describe('lastIrrigationLine', () => {
  it('gives the latest day over the fields, with its amounts', () => {
    const cards = [card(1, { date: '2026-07-19', inches: 0.8 }), card(2, { date: '2026-07-19', inches: 0.5 })]
    expect(lastIrrigationLine(cards, today, imperial)).toBe('Last irrigated yesterday, 0.50–0.80 in')
    expect(lastIrrigationLine([card(1, { date: '2026-07-17', inches: 0.8 }), card(2, null)], today, imperial)).toBe(
      'Last irrigated Fri, Jul 17, 0.80 in',
    )
    expect(lastIrrigationLine([card(1, null)], today, imperial)).toBe('No irrigation entered this season')
  })
})

describe('replacing', () => {
  const recent = { [today]: { '1': 0.8, '2': 0.5 } }
  const north = { id: 1, name: 'North' }
  const south = { id: 2, name: 'South' }

  it('names what saving would replace on the fields chosen', () => {
    expect(replacing(recent, today, [north], imperial)).toBe('Already 0.80 in on North that day')
    expect(replacing(recent, today, [north, south], imperial)).toBe(
      'Already irrigation that day on North (0.80 in) and South (0.50 in)',
    )
    expect(replacing(recent, '2026-07-19', [north], imperial)).toBeNull()
    expect(replacing(recent, today, [{ id: 3, name: 'East' }], imperial)).toBeNull()
  })
})
