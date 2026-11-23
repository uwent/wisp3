import { describe, expect, it } from 'vitest'

import { nextRain, nextRainLine, noRain, rainOdds, rainSummary, rainWords } from './rain'
import { units } from './units'

const imperial = units('imperial')
const day = (date: string, precip_in: number | null, precip_chance: number | null) => ({
  date,
  precip_in,
  precip_chance,
})
const today = '2026-07-20'

describe('rainOdds', () => {
  it('is likely from 50%, possible from 20%, by the chance', () => {
    expect(rainOdds(day(today, 0.05, 50))).toBe('likely')
    expect(rainOdds(day(today, 0.5, 49))).toBe('possible')
    expect(rainOdds(day(today, 0.5, 20))).toBe('possible')
    expect(rainOdds(day(today, 0.5, 19))).toBeNull()
  })

  it('goes by the amount without a chance', () => {
    expect(rainOdds(day(today, 0.1, null))).toBe('likely')
    expect(rainOdds(day(today, 0.09, null))).toBeNull()
    expect(rainOdds(day(today, null, null))).toBeNull()
  })
})

describe('nextRain and its wording', () => {
  const week = [
    day('2026-07-20', 0, 5),
    day('2026-07-21', 0.02, 10),
    day('2026-07-22', 0.2, 60),
    day('2026-07-23', 0.6, 90),
  ]

  it('finds the first day with rain likely or possible', () => {
    expect(nextRain(week)).toMatchObject({ date: '2026-07-22', odds: 'likely' })
    expect(nextRain(week.slice(0, 2))).toBeNull()
  })

  it('names the day, its chance and amount', () => {
    expect(rainWords(week[2], today, imperial)).toBe('Wed, 60% chance, 0.20 in')
    expect(rainWords(day('2026-07-21', 0.4, null), today, imperial)).toBe('Tomorrow, 0.40 in')
    expect(nextRainLine(week, today, imperial)).toBe('Next rain: Wed, 60% chance, 0.20 in')
  })

  it('says when none is expected, and nothing without a forecast', () => {
    expect(nextRainLine(week.slice(0, 2), today, imperial)).toBe('No rain expected in the next 2 days')
    expect(nextRainLine([], today, imperial)).toBeNull()
  })
})

describe('rainSummary', () => {
  const dry = (date: string) => day(date, 0, 0)
  const zone = (...days: ReturnType<typeof day>[]) => ({ days })

  it('says when rain comes to every zone, with the range of amounts', () => {
    const zones = [
      zone(dry('2026-07-20'), day('2026-07-21', 0.2, 70)),
      zone(dry('2026-07-20'), day('2026-07-21', 0.4, 40)),
    ]
    expect(rainSummary(zones, today, imperial)).toBe('Rain likely tomorrow, all fields, 0.20–0.40 in')
  })

  it('says some fields when it comes first to some zones, possible when none is likely', () => {
    const zones = [zone(dry('2026-07-20'), dry('2026-07-21'), day('2026-07-22', 0.1, 30)), zone(dry('2026-07-20'))]
    expect(rainSummary(zones, today, imperial)).toBe('Rain possible on Wed, some fields, 0.10 in')
  })

  it('leaves out the amount when the forecast gives none', () => {
    expect(rainSummary([zone(day(today, 0, 30))], today, imperial)).toBe('Rain possible today')
  })

  it('leaves out which fields with one zone, and says when none is expected', () => {
    expect(rainSummary([zone(day(today, 0.3, 80))], today, imperial)).toBe('Rain likely today, 0.30 in')
    expect(rainSummary([zone(dry('2026-07-20'), dry('2026-07-21'))], today, imperial)).toBe(
      'No rain expected in the next 2 days',
    )
    expect(rainSummary([zone()], today, imperial)).toBeNull()
  })
})

describe('noRain', () => {
  it('is a day with no chance and no amount', () => {
    expect(noRain(day(today, 0, 0))).toBe(true)
    expect(noRain(day(today, 0, null))).toBe(true)
    expect(noRain(day(today, null, null))).toBe(false)
    expect(noRain(day(today, 0.01, 0))).toBe(false)
    expect(noRain(day(today, 0, 5))).toBe(false)
  })
})
