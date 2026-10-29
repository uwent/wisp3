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
})
