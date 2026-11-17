import { describe, expect, it } from 'vitest'

import { units } from '@/lib/units'

import {
  cardWhen,
  canReplace,
  clashes,
  dateProblems,
  nextSeason,
  plantingLabel,
  plantingWhen,
  plotAcres,
  plotSize,
  seasonLine,
  endedSeasonStats,
  typicalEnd,
} from './plantings'

const sized = { partial: true, area_acres: plotAcres(100, 20), plot_length_ft: 100, plot_width_ft: 20 }

describe('plantingWhen and plantingLabel', () => {
  const potato = { plant_name: 'Potato', variety: 'Superior', season_start: '2026-04-01', end_date: '2026-08-30' }
  it('names a planting by when it is: its start and days in season, else its dates', () => {
    expect(plantingWhen(potato, '2026-05-15')).toBe('Apr 1, 44 days')
    expect(plantingWhen(potato, '2026-11-12')).toBe('Apr 1 – Aug 30')
    expect(plantingWhen(potato, '2026-03-01')).toBe('Apr 1 – Aug 30')
  })
  it('puts the variety and when in one pair of brackets', () => {
    expect(plantingLabel(potato, '2026-11-12')).toBe('Potato (Superior, Apr 1 – Aug 30)')
    expect(plantingLabel({ ...potato, variety: null }, '2026-11-12')).toBe('Potato (Apr 1 – Aug 30)')
  })
})

describe('plotSize', () => {
  it('gives length × width with the acres, or just the acres', () => {
    expect(plotSize(sized, units('imperial'))).toBe('100 × 20 ft (0.05 ac)')
    expect(plotSize({ ...sized, plot_length_ft: null, plot_width_ft: null, area_acres: 0.25 }, units())).toBe('0.25 ac')
    expect(plotSize(sized, units('metric'))).toBe('30 × 6 m (0.02 ha)')
  })

  it('is null for the whole field', () => {
    expect(plotSize({ ...sized, partial: false }, units())).toBeNull()
  })
})

describe('clashes', () => {
  const whole = { id: 1, season_start: '2026-04-01', end_date: '2026-09-30', partial: false }
  const plot = { id: 2, season_start: '2026-05-01', end_date: '2026-08-31', partial: true }

  it('finds every overlap for a whole-field planting, and only whole-field ones for a plot', () => {
    const fresh = { season_start: '2026-06-01', end_date: '2026-10-31', partial: false }
    expect(clashes(fresh, [whole, plot])).toEqual([whole, plot])
    expect(clashes({ ...fresh, partial: true }, [whole, plot])).toEqual([whole])
  })

  it('leaves out the planting itself and ones in other dates', () => {
    expect(clashes(whole, [whole])).toEqual([])
    expect(clashes({ season_start: '2026-10-01', end_date: '2026-11-30', partial: false }, [whole])).toEqual([])
  })
})

describe('nextSeason', () => {
  it('starts the day after and runs to the end of November', () => {
    expect(nextSeason({ end_date: '2026-06-15' })).toEqual({
      season_start: '2026-06-16',
      emergence_date: '2026-06-23',
      end_date: '2026-11-30',
    })
  })

  it('runs a month when it starts late in the year', () => {
    expect(nextSeason({ end_date: '2026-11-20' }).end_date).toBe('2026-12-21')
  })
})

describe('typicalEnd', () => {
  it("adds the crop's season to emergence, no later than Nov 30", () => {
    expect(typicalEnd(105, '2026-05-20')).toBe('2026-09-02')
    expect(typicalEnd(140, '2026-08-01')).toBe('2026-11-30')
    expect(typicalEnd(null, '2026-05-01')).toBe('2026-11-30')
  })
})

describe('an ended season on its card (G.6)', () => {
  const imperial = units('imperial')
  const totals = {
    rain: 11.8,
    irrigation: 7.2,
    deep_drainage: 1.9,
    irrigation_days: 9,
    rain_days: 24,
    drainage_days: 4,
    stress_days: 3,
  }

  it("gives an ended season's dates their length, and leaves the others as they are", () => {
    const potato = { season_start: '2026-05-20', end_date: '2026-09-15' }
    expect(cardWhen(potato, '2026-10-01')).toBe('May 20 – Sep 15 (118 days)')
    expect(cardWhen(potato, '2026-07-01')).toBe(plantingWhen(potato, '2026-07-01'))
  })

  it('counts irrigation, rain, drainage and stress', () => {
    expect(endedSeasonStats(totals, imperial)).toEqual([
      { label: 'Irrigated', value: '9 times, 7.20 in' },
      { label: 'Rain', value: '24 days, 11.80 in' },
      { label: 'Deep drainage', value: '4 days, 1.90 in' },
      { label: 'Below the irrigation point', value: '3 days' },
    ])
    expect(seasonLine(totals, imperial)).toBe('Irrigated 7.20 in · rain 11.80 in · 3 days below the irrigation point')
  })

  it('says never and none, and no data for rain without weather', () => {
    const quiet = {
      ...totals,
      rain: null,
      irrigation: 0,
      irrigation_days: 0,
      deep_drainage: 0,
      drainage_days: 0,
      stress_days: 0,
    }
    expect(endedSeasonStats({ ...quiet, irrigation_days: 1, irrigation: 1 }, imperial)[0].value).toBe('once, 1.00 in')
    expect(endedSeasonStats(quiet, imperial).map((stat) => stat.value)).toEqual(['Never', 'No data', 'None', 'Never'])
    expect(seasonLine(quiet, imperial)).toBe('No irrigation · never below the irrigation point')
  })
})

describe('dateProblems (G.13 part 3)', () => {
  const dates = { seasonStart: '2026-04-01', emergence: '2026-05-01', end: '2026-09-30' }

  it('accepts a season in order, a transplant emerging on its first day, and a crop up before it', () => {
    expect(dateProblems(dates)).toEqual({})
    expect(dateProblems({ ...dates, emergence: '2026-04-01' })).toEqual({})
    expect(dateProblems({ ...dates, emergence: '2026-03-15' })).toEqual({})
  })

  it('needs harvest after emergence and the season start: at least a day', () => {
    expect(dateProblems({ ...dates, end: '2026-05-01' }, 'Harvest or kill').end).toBe(
      'Harvest or kill must be after emergence (May 1).',
    )
    expect(dateProblems({ seasonStart: '2026-04-01', emergence: '2026-03-01', end: '2026-04-01' }).end).toBe(
      'Harvest must be after the season start (Apr 1).',
    )
  })

  it('keeps vine kill between emergence and harvest', () => {
    expect(dateProblems({ ...dates, vineKill: '2026-04-20' }).vineKill).toBe(
      "Vine kill can't be before emergence (May 1).",
    )
    expect(dateProblems({ ...dates, vineKill: '2026-10-02' }).vineKill).toBe(
      "Vine kill can't be after harvest (Sep 30).",
    )
    expect(dateProblems({ ...dates, vineKill: '2026-09-01' })).toEqual({})
  })

  it('holds a saved planting whose dates are unchanged to the rules it was saved under', () => {
    // Harvest on emergence day was allowed before G.13: still editable, as on the server
    const old = { ...dates, end: '2026-05-01' }
    expect(dateProblems(old, 'Harvest', { loose: true })).toEqual({})
    expect(dateProblems({ ...old, end: '2026-04-30' }, 'Harvest', { loose: true }).end).toBe(
      'Harvest must be on or after emergence (May 1).',
    )
  })
})

describe('canReplace', () => {
  it('ends another planting the day before only if that leaves it at least a day', () => {
    const other = { season_start: '2026-04-01', emergence_date: '2026-04-15' }
    expect(canReplace(other, '2026-07-01')).toBe(true)
    expect(canReplace({ ...other, emergence_date: '2026-06-30' }, '2026-07-01')).toBe(false)
    expect(canReplace({ ...other, emergence_date: '2026-06-29' }, '2026-07-01')).toBe(true)
    expect(canReplace({ season_start: '2026-06-30', emergence_date: '2026-06-01' }, '2026-07-01')).toBe(false)
  })
})
