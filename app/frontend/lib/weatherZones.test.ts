import { describe, expect, it } from 'vitest'

import { weatherZone, weatherZoneExport } from './weatherZones'

describe('weather zone addresses (G.6)', () => {
  it('keeps the comma between latitude and longitude readable', () => {
    expect(weatherZone('44.12,-89.54').url).toBe('/weather/44.12,-89.54')
    expect(weatherZone('44.12,-89.54', { query: { year: 2025 } }).url).toBe('/weather/44.12,-89.54?year=2025')
    expect(weatherZoneExport('44.12,-89.54', { query: { year: 2025 } }).url).toBe(
      '/weather/44.12,-89.54/export?year=2025',
    )
  })
})
