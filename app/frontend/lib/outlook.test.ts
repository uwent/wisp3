import { describe, expect, it } from 'vitest'

import type { PlantingSummary } from '@/types/serializers'

// The cases spec/services/outlook_spec.rb runs too, so the digest and the field page say the same
import outlookCases from '../../../spec/fixtures/files/outlook_cases.json'
import { outlook } from './outlook'
import { units, type UnitSystem } from './units'

describe('outlook', () => {
  for (const example of outlookCases.cases) {
    it(example.name, () => {
      const summary = { ...outlookCases.base, ...example.summary } as unknown as PlantingSummary
      expect(outlook(summary, units(example.units as UnitSystem))).toEqual(example.expected)
    })
  }

  // Time travel (PLAN.md Phase 8 F): the field page only, so not in the shared cases
  describe('on the weather that followed', () => {
    const base = { ...outlookCases.base, projection_source: 'observed', ensemble_size: 0 }
    const crossing = { date: '2026-07-13', days: 3, ad: 0.1, refill: 0.7 }
    const dryCrossing = { date: '2026-07-11', days: 1, ad: 0, refill: 0.8 }

    it('says what the weather that followed did, without the dry case', () => {
      const summary = { ...base, crossing, dry_crossing: dryCrossing } as unknown as PlantingSummary
      expect(outlook(summary, units('imperial'))).toEqual({
        urgent: true,
        headline: 'Reached the irrigation point Mon, Jul 13',
        detail:
          'With the weather that followed and what was entered for those days, it reached the irrigation point 3 days later, when about 0.70 in would have refilled the root zone to field capacity.',
        chance: null,
        dry: null,
      })
    })

    it('says the next day, and when it stayed above', () => {
      const next = { ...base, crossing: { ...crossing, date: '2026-07-11', days: 1 } } as unknown as PlantingSummary
      expect(outlook(next, units('imperial'))?.detail).toMatch(/irrigation point the next day/)
      expect(outlook(base as unknown as PlantingSummary, units('imperial'))).toMatchObject({
        headline: 'Stayed above the irrigation point through Mon, Jul 13',
        detail:
          'With the weather that followed and what was entered for those days, it stayed above the irrigation point.',
      })
    })
  })
})
