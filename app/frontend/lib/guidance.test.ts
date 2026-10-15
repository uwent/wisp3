import { describe, expect, it } from 'vitest'

import { guidance } from './guidance'
import { units } from './units'

const corn = {
  plant_name: 'Field Corn',
  plant_key: 'field_corn',
  et_method: 'lai',
  max_root_zone_depth: 32,
} as const
const potato = {
  plant_name: 'Potato',
  plant_key: 'potato',
  et_method: 'pct_cover',
  max_root_zone_depth: 16,
} as const
const day = (date: string, entered: { moisture?: boolean; canopy?: number } = {}) => ({
  date,
  moisture_source: entered.moisture ? ('entered' as const) : null,
  canopy_entered: entered.canopy ?? null,
})
const today = '2026-07-20'

describe('guidance', () => {
  it('explains the LAI curve for field corn, and where to put sensors', () => {
    const result = guidance(corn, [], units('imperial'), today)
    expect(result.title).toBe('How field corn is modeled')
    expect(result.paragraphs[0]).toMatch(/^Field Corn water use is modeled from leaf area index \(LAI\)/)
    expect(result.paragraphs[0]).toContain('on a field corn growth curve')
    expect(result.paragraphs.at(-1)).toContain('(8 in and 24 in deep)')
    // The curve stands in for LAI readings, so only soil moisture is asked for
    expect(result.readings).toEqual([{ label: 'Soil moisture', last: 'None this season', due: true, note: 'due' }])
  })

  it('asks for LAI readings once the first one replaces the curve', () => {
    const result = guidance(corn, [day('2026-07-01', { canopy: 2.5 })], units('metric'), today)
    expect(result.readings.map((reading) => [reading.label, reading.due])).toEqual([
      ['Soil moisture', true],
      ['LAI', true],
    ])
  })

  it('asks for percent cover weekly until the canopy is nearly closed, with notes for the crop', () => {
    const result = guidance(
      potato,
      [day('2026-07-10', { canopy: 60 }), day('2026-07-15', { moisture: true })],
      units('imperial'),
      today,
    )
    expect(result.paragraphs[0]).toMatch(/^Potato water use is modeled from percent canopy cover/)
    expect(result.paragraphs[1]).toContain('top of the hill')
    expect(result.paragraphs.at(-1)).toContain('(4 in and 12 in deep)')
    expect(result.readings).toEqual([
      { label: 'Soil moisture', last: 'Jul 15 (5 days ago)', due: false, note: null },
      { label: 'Percent cover', last: 'Jul 10 (10 days ago)', due: true, note: 'due' },
    ])

    const closed = guidance(potato, [day('2026-07-01', { canopy: 85 })], units('imperial'), today)
    expect(closed.readings[1]).toMatchObject({ label: 'Percent cover', due: false, note: 'canopy closed' })
  })

  it('leaves out reminders outside the season', () => {
    expect(guidance(potato, [], units('imperial'), null).readings).toEqual([])
  })
})
