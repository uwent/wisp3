import { describe, expect, it } from 'vitest'

import { units } from '@/lib/units'

import { clashes, nextSeason, plotAcres, plotSize, typicalEnd } from './plantings'

const sized = { partial: true, area_acres: plotAcres(100, 20), plot_length_ft: 100, plot_width_ft: 20 }

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
