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
type Task = Parameters<typeof guidance>[2][number]
const task = (kind: Task['kind'], label: string, last_date: string | null, due: boolean, extra: Partial<Task> = {}) =>
  ({ kind, label, last_date, due, note: due ? 'due' : null, todo: null, message: null, ...extra }) as Task
const today = '2026-07-20'

describe('guidance', () => {
  it('explains the LAI curve for field corn, and where to put sensors', () => {
    const result = guidance(corn, units('imperial'), [task('soil_moisture', 'Soil moisture', null, true)], today)
    expect(result.title).toBe('How field corn is modeled')
    expect(result.paragraphs[0]).toMatch(/^Field Corn water use is modeled from leaf area index \(LAI\)/)
    expect(result.paragraphs[0]).toContain('using a field corn growth curve')
    expect(result.paragraphs.at(-1)).toContain('(8 in and 24 in deep)')
    expect(result.readings).toEqual([
      { label: 'Soil moisture', last: 'None entered this season', due: true, note: 'due' },
    ])
  })

  it("lists the planting's readings with when each was last entered, and crop notes", () => {
    const result = guidance(
      potato,
      units('imperial'),
      [
        task('soil_moisture', 'Soil moisture', '2026-07-15', false),
        task('canopy', 'Percent cover', '2026-07-10', true),
      ],
      today,
    )
    expect(result.paragraphs[0]).toMatch(/^Potato water use is modeled from percent canopy cover/)
    expect(result.paragraphs[1]).toContain('top of the hill')
    expect(result.paragraphs.at(-1)).toContain('(4 in and 12 in deep)')
    expect(result.readings).toEqual([
      { label: 'Soil moisture', last: 'Jul 15 (5 days ago)', due: false, note: null },
      { label: 'Percent cover', last: 'Jul 10 (10 days ago)', due: true, note: 'due' },
    ])
    expect(result.warning).toBeNull()
  })

  it('leaves out reminders outside the season', () => {
    expect(guidance(potato, units('imperial'), [], null).readings).toEqual([])
  })

  it('explains how readings combine with the curve, or that there is none', () => {
    const curve = guidance(potato, units('imperial'), [], today).paragraphs[0]
    expect(curve).toContain('WISP follows a potato canopy curve from the emergence date')
    expect(curve).toContain('Your readings adjust the curve')
    const lines = guidance({ ...potato, effective_canopy_interpolation: 'linear' }, units('imperial'), [], today)
    expect(lines.paragraphs[0]).toContain('draws straight lines between your readings instead')
    const none = guidance(
      { ...potato, plant_name: 'Onion', canopy_curve: false, effective_canopy_interpolation: 'linear' },
      units('imperial'),
      [],
      today,
    )
    expect(none.paragraphs[0]).toContain("There's no canopy curve for onion")
    expect(none.paragraphs[0]).toContain('Between readings WISP draws a straight line')
  })

  it('gives the canopy check as a warning, not a reading', () => {
    const check = task('canopy_check', 'Canopy readings', null, true, {
      todo: 'Check canopy readings: about 9 days ahead of the potato curve',
      message: 'Your canopy readings run about 9 days ahead of the potato curve.',
    })
    const result = guidance(potato, units('imperial'), [check], today)
    expect(result.warning).toBe('Your canopy readings run about 9 days ahead of the potato curve.')
    expect(result.readings).toEqual([])
  })
})
