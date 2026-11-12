import { describe, expect, it } from 'vitest'

import { dayName, skyFor } from './forecast'

const day = (overrides: Partial<Parameters<typeof skyFor>[0]> = {}) => ({
  weather_code: null,
  cloud_cover_pct: null,
  precip_in: null,
  snowfall_in: null,
  ...overrides,
})

describe('skyFor', () => {
  it('words precipitation, fog and storms from the code', () => {
    expect(skyFor(day({ weather_code: 95, cloud_cover_pct: 10 }))).toEqual({ sky: 'thunder', label: 'Thunderstorms' })
    expect(skyFor(day({ weather_code: 66 }))?.label).toBe('Freezing rain')
    expect(skyFor(day({ weather_code: 45 }))?.sky).toBe('fog')
    expect(skyFor(day({ weather_code: 81 }))?.sky).toBe('showers')
  })

  it("words a dry day from its mean cloud cover, not the cloudiest hour's code", () => {
    expect(skyFor(day({ weather_code: 3, cloud_cover_pct: 15 }))).toEqual({ sky: 'clear', label: 'Sunny' })
    expect(skyFor(day({ weather_code: 3, cloud_cover_pct: 65 }))?.label).toBe('Partly cloudy')
    expect(skyFor(day({ weather_code: 3, cloud_cover_pct: 90 }))?.sky).toBe('cloudy')
    expect(skyFor(day({ weather_code: 0 }))?.sky).toBe('clear')
    expect(skyFor(day({ weather_code: 3 }))?.sky).toBe('cloudy')
  })

  it('falls back to snow, precipitation and cloud cover without a code', () => {
    expect(skyFor(day({ snowfall_in: 0.5, precip_in: 0.05 }))?.sky).toBe('snow')
    expect(skyFor(day({ precip_in: 0.4, cloud_cover_pct: 90 }))?.sky).toBe('rain')
    expect(skyFor(day({ precip_in: 0.02 }))?.sky).toBe('showers')
    expect(skyFor(day({ precip_in: 0, cloud_cover_pct: 40 }))?.label).toBe('Mostly sunny')
    expect(skyFor(day())).toBeNull()
  })
})

describe('dayName', () => {
  it('says today and tomorrow, then the weekday', () => {
    expect(dayName('2026-11-11', '2026-11-11')).toBe('Today')
    expect(dayName('2026-11-12', '2026-11-11')).toBe('Tomorrow')
    expect(dayName('2026-11-13', '2026-11-11')).toBe('Fri')
    expect(dayName('2027-01-01', '2026-12-31')).toBe('Tomorrow')
  })
})
