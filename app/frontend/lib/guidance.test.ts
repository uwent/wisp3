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
  end_date: '2026-10-15',
  vine_kill_crop: false,
  vine_kill_date: null,
} as const
const potato = {
  plant_name: 'Potato',
  plant_key: 'potato',
  et_method: 'pct_cover',
  max_root_zone_depth: 16,
  canopy_curve: true,
  effective_canopy_interpolation: 'curve',
  emergence_date: '2026-05-15',
  end_date: '2026-09-30',
  vine_kill_crop: true,
  vine_kill_date: null,
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

  it('explains vine kill for potato, then gives its dates once entered', () => {
    const before = guidance(potato, units('imperial'), [], today).paragraphs
    expect(before).toContain(
      "Enter the vine kill date in this potato's settings in Setup. From it the canopy ramps down to nothing over 14 " +
        'days, and WISP keeps the water balance going until harvest (the end date), so you can keep the soil moist ' +
        'through skin set.',
    )
    const after = guidance({ ...potato, vine_kill_date: '2026-09-01' }, units('imperial'), [], today).paragraphs
    expect(after).toContain(
      'Vine kill is Sep 1: the canopy ramps down to nothing by Sep 15, and WISP keeps the water balance going until ' +
        'harvest on Sep 30. A canopy reading after vine kill is used as entered.',
    )
    expect(guidance(corn, units('imperial'), [], today).paragraphs.join(' ')).not.toContain('vine kill')
  })

  it('says how the curve has been fitted to the readings so far', () => {
    const fitted = (fit: { shift: number; stretch: number; height: number } | null) =>
      guidance(potato, units('imperial'), [], today, fit).paragraphs[0]
    expect(fitted(null)).not.toContain('So far')
    expect(fitted({ shift: 0, stretch: 1, height: 1 })).toContain(
      'So far your readings match the typical potato curve, so WISP follows it as it is.',
    )
    expect(fitted({ shift: -4, stretch: 0.905, height: 1.051 })).toContain(
      'So far, fitted to your readings, the potato curve runs about 4 days ahead of the typical one, grows 10% faster ' +
        'and is 5% fuller.',
    )
    expect(fitted({ shift: 1, stretch: 1.0, height: 1.02 })).toContain('runs about 1 day behind the typical one.')
    expect(fitted({ shift: 0, stretch: 1.105, height: 1 })).toContain('the potato curve grows 10% slower.')
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
