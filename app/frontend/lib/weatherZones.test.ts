import { describe, expect, it } from 'vitest'

import { fileLocation, weatherZone, weatherZoneExport } from './weatherZones'

describe('weather zone addresses', () => {
  it('keeps the comma between latitude and longitude readable', () => {
    expect(weatherZone('44.12,-89.54').url).toBe('/weather/44.12,-89.54')
    expect(weatherZone('44.12,-89.54', { query: { year: 2025 } }).url).toBe('/weather/44.12,-89.54?year=2025')
    expect(weatherZoneExport('44.12,-89.54', { query: { year: 2025 } }).url).toBe(
      '/weather/44.12,-89.54/export?year=2025',
    )
  })

  it("names files by the zone's location, as the server does", () => {
    expect(fileLocation('44.12,-89.54')).toBe('44.12N-89.54W')
    expect(fileLocation('-33.90,151.20')).toBe('33.90S-151.20E')
  })
})
