import { describe, expect, it } from 'vitest'

import { guidance } from './guidance'
import { units } from './units'

const corn = {
  plant_name: 'Field Corn',
  plant_key: 'field_corn',
  et_method: 'lai',
  max_root_zone_depth: 32,
  canopy_curve: true,
  effective_canopy_interpolation: 'curve',
  emergence_date: '2026-05-12',
} as const
const potato = {
  plant_name: 'Potato',
  plant_key: 'potato',
  et_method: 'pct_cover',
  max_root_zone_depth: 16,
  canopy_curve: true,
  effective_canopy_interpolation: 'curve',
  emergence_date: '2026-05-15',
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

  it('explains how readings combine with the curve, or that there is none', () => {
    const curve = guidance(potato, [], units('imperial'), today).paragraphs[0]
    expect(curve).toContain('WISP follows a potato canopy curve from the emergence date')
    expect(curve).toContain('Your readings scale the curve')
    const lines = guidance({ ...potato, effective_canopy_interpolation: 'linear' }, [], units('imperial'), today)
    expect(lines.paragraphs[0]).toContain('draws straight lines between your readings instead')
    const none = guidance(
      { ...potato, plant_name: 'Onion', canopy_curve: false, effective_canopy_interpolation: 'linear' },
      [],
      units('imperial'),
      today,
    )
    expect(none.paragraphs[0]).toContain("There's no canopy curve for onion")
    expect(none.paragraphs[0]).toContain('Between readings WISP draws a straight line')
    expect(none.warning).toBeNull()
  })

  it('warns when readings run ahead of or behind the curve, or fall', () => {
    const ahead = guidance(potato, [], units('imperial'), today, { days_ahead: 9, drop: null })
    expect(ahead.warning).toContain('run about 9 days ahead of the potato curve')
    expect(ahead.warning).toContain('check the emergence date (May 15)')
    expect(ahead.warning).toContain('WISP still follows the curve')
    const behind = guidance(potato, [], units('imperial'), today, { days_ahead: -8, drop: null })
    expect(behind.warning).toContain('8 days behind the potato curve')
    const drop = guidance(potato, [], units('imperial'), today, {
      days_ahead: null,
      drop: { date: '2026-06-17', from: 60, to: 40 },
    })
    expect(drop.warning).toContain('reading on Jun 17 (40%) is lower than the one before it (60%)')
  })
})
