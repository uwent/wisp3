import { describe, expect, it } from 'vitest'

import type { PlantingSummary } from '@/types/serializers'

import {
  daysToIrrigate,
  type FieldCard,
  type ListItem,
  needsWaterWithin,
  pivotStatus,
  sortItems,
  urgency,
} from './overview'

const summary = (overrides: Partial<PlantingSummary>) =>
  ({ phase: 'active', status: 'ok', weather_pending: false, crossing: null, ...overrides }) as PlantingSummary

const card = (name: string, overrides: Partial<PlantingSummary> | null = {}): FieldCard => ({
  id: name.length,
  name,
  summary: overrides && summary(overrides),
})

const crossing = (days: number) => ({ date: '2026-07-20', days, ad: 0, refill: 1 })

describe('urgency', () => {
  it('puts statuses in season first, then upcoming, ended and no crop', () => {
    const cards = [
      card('none', null),
      card('ended', { phase: 'ended' }),
      card('upcoming', { phase: 'upcoming', status: null }),
      card('pending', { weather_pending: true }),
      card('full', { status: 'full' }),
      card('ok'),
      card('caution', { status: 'caution' }),
      card('irrigate', { status: 'irrigate' }),
    ]
    expect(cards.toSorted((a, b) => urgency(a) - urgency(b)).map((c) => c.name)).toEqual([
      'irrigate',
      'caution',
      'ok',
      'full',
      'pending',
      'upcoming',
      'ended',
      'none',
    ])
  })
})

describe('needing water', () => {
  it('counts a field at the irrigation point as now, and others by the projected crossing', () => {
    expect(daysToIrrigate(card('dry', { status: 'irrigate' }))).toBe(0)
    expect(daysToIrrigate(card('soon', { status: 'caution', crossing: crossing(2) }))).toBe(2)
    expect(daysToIrrigate(card('wet'))).toBeNull()
    expect(daysToIrrigate(card('ended', { phase: 'ended', crossing: crossing(1) }))).toBeNull()
  })

  it('picks the fields within the window', () => {
    const soon = card('soon', { status: 'caution', crossing: crossing(3) })
    expect(needsWaterWithin(soon, 3)).toBe(true)
    expect(needsWaterWithin(soon, 0)).toBe(false)
    expect(needsWaterWithin(card('wet'), 7)).toBe(false)
  })
})

describe('pivotStatus', () => {
  it("is the most urgent status among the pivot's fields in season", () => {
    expect(
      pivotStatus([card('a'), card('b', { status: 'caution' }), card('c', { phase: 'ended', status: 'irrigate' })]),
    ).toBe('caution')
    expect(pivotStatus([card('a', { phase: 'ended' }), card('b', null)])).toBeNull()
    expect(pivotStatus([])).toBeNull()
  })
})

describe('sortItems', () => {
  const item = (c: FieldCard, pivot: string, latitude: number, id = latitude): ListItem => ({
    card: c,
    pivot: { id, name: pivot, latitude },
    farm: { id: 1, name: 'Farm' },
  })
  const items = [
    item(card('B ok'), 'South', 44.0),
    item(card('A later', { status: 'caution', crossing: crossing(3) }), 'North', 44.5),
    item(card('C sooner', { status: 'caution', crossing: crossing(1) }), 'Middle', 44.2),
    item(card('D ended', { phase: 'ended' }), 'North', 44.5),
    item(card('E dry', { status: 'irrigate' }), 'South', 44.0),
  ]
  const names = (sorted: ListItem[]) => sorted.map((i) => i.card.name)

  it('sorts by need, soonest first, ended last', () => {
    expect(names(sortItems(items, 'urgent'))).toEqual(['E dry', 'C sooner', 'A later', 'B ok', 'D ended'])
  })

  it("sorts north to south, keeping a pivot's fields together", () => {
    expect(names(sortItems(items, 'north'))).toEqual(['A later', 'D ended', 'C sooner', 'B ok', 'E dry'])
  })
})
