import { describe, expect, it } from 'vitest'

import type { PlantingSummary } from '@/types/serializers'

import { outlook } from './outlook'
import { units } from './units'

const projection = ['2026-07-11', '2026-07-12', '2026-07-13'].map((date, i) => ({
  date,
  ad: 0.3 - i * 0.2,
  p10: null,
  p50: null,
  p90: null,
  chance: [0.1, 0.5, 0.9][i],
}))
const summary = (overrides: Partial<PlantingSummary> = {}) =>
  ({
    phase: 'active',
    date: '2026-07-10',
    target_in: null,
    crossing: null,
    projection,
    ensemble_size: 30,
    ...overrides,
  }) as PlantingSummary

describe('outlook', () => {
  it('says when to irrigate, how much, and how many forecast scenarios agree', () => {
    const result = outlook(
      summary({ crossing: { date: '2026-07-12', days: 2, ad: -0.1, refill: 1.3 } }),
      units('imperial'),
    )
    expect(result).toEqual({
      urgent: true,
      headline: 'Irrigate by Sun, Jul 12',
      detail:
        'Projected to reach the irrigation point in 2 days; about 1.30 in would refill it to field capacity then.',
      chance: '15 of 30 forecast scenarios reach it by then.',
      dry: null,
    })
  })

  it('says when a field on entered rain needs water if no rain falls, when that is sooner', () => {
    const dry_crossing = { date: '2026-07-11', days: 1, ad: -0.1, refill: 1.3 }
    expect(outlook(summary({ dry_crossing }), units('imperial'))!.dry).toBe(
      'If no rain falls: irrigate by Sat, Jul 11 (tomorrow).',
    )
    const crossing = { date: '2026-07-12', days: 2, ad: -0.1, refill: 1.3 }
    expect(outlook(summary({ crossing, dry_crossing }), units('imperial'))!.dry).toContain('Sat, Jul 11')
    expect(outlook(summary({ crossing, dry_crossing: crossing }), units('imperial'))!.dry).toBeNull()
  })

  it('names the target when there is one, and says when it is crossed already', () => {
    const result = outlook(
      summary({ target_in: 0.6, crossing: { date: '2026-07-10', days: 0, ad: 0.5, refill: 0.7 } }),
      units('metric'),
    )
    expect(result).toMatchObject({
      urgent: true,
      headline: 'Below target now',
      detail: 'About 17.8 mm refills the root zone to field capacity.',
    })
  })

  it('says how far ahead the field is fine, with the scenarios that disagree', () => {
    const result = outlook(summary(), units('imperial'))
    expect(result).toMatchObject({
      urgent: false,
      headline: 'No irrigation needed through Mon, Jul 13',
      chance: '27 of 30 forecast scenarios reach it by then.',
    })
    expect(outlook(summary({ ensemble_size: 0 }), units('imperial'))!.chance).toBeNull()
  })

  it('has nothing to say outside the season or without a forecast', () => {
    expect(outlook(summary({ phase: 'ended' }), units('imperial'))).toBeNull()
    expect(outlook(summary({ projection: [] }), units('imperial'))).toBeNull()
  })
})
