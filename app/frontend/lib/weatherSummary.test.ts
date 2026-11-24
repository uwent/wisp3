import { describe, expect, it } from 'vitest'

import { units } from './units'
import { weatherLines } from './weatherSummary'

const span = {
  days: 7,
  precip: 0.85,
  et0: 1.12,
  tmax: [68, 82] as [number, number],
  tmin: [48, 60] as [number, number],
}

describe('weatherLines', () => {
  it("words the last week and the next like the daily email's lines, with reference ET named in full", () => {
    expect(weatherLines({ past: span, ahead: { ...span, days: 6, tmin: [55, 55] } }, units('imperial'))).toEqual([
      'Past 7 days: 0.85 in rain · 1.12 in reference ET · highs 68–82°F, lows 48–60°F',
      'Next 6 days: 0.85 in rain · 1.12 in reference ET · highs 68–82°F, lows 55°F',
    ])
  })

  it('converts to metric', () => {
    expect(weatherLines({ past: span, ahead: null }, units('metric'))).toEqual([
      'Past 7 days: 21.6 mm rain · 28.4 mm reference ET · highs 20–28°C, lows 9–16°C',
    ])
  })

  it('leaves out what is missing, and says when a week has nothing', () => {
    const empty = { days: 1, precip: null, et0: null, tmax: null, tmin: null }
    expect(weatherLines({ past: { ...span, et0: null, tmax: null }, ahead: empty }, units('imperial'))).toEqual([
      'Past 7 days: 0.85 in rain · lows 48–60°F',
      'Next 1 day: not available yet',
    ])
    expect(weatherLines({ past: null, ahead: null }, units('imperial'))).toEqual([])
    expect(weatherLines(null, units('imperial'))).toEqual([])
  })
})
