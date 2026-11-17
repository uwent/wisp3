import { describe, expect, it } from 'vitest'

import { cellLabel, cellText, cellValue, depthUnitName, irrigationFrom, type DayRow } from './fieldDays'
import { units } from './units'

const imperial = units('imperial')
const metric = units('metric')
const day: DayRow = {
  date: '2026-07-15',
  rain: 0.5,
  rain_source: 'model',
  irrigation: 1,
  irrigation_source: 'entered',
  notes: 'Gauge',
  soil_moisture_pct: 18,
  moisture_source: 'entered',
  canopy_entered: null,
}

describe('field day cells', () => {
  it('start with what was entered, not what was modeled', () => {
    expect(cellText(day, 'rain_in', imperial)).toBe('')
    expect(cellText(day, 'irrigation_in', imperial)).toBe('1')
    expect(cellText(day, 'irrigation_in', metric)).toBe('25.4')
    expect(cellText(day, 'soil_moisture_pct', imperial)).toBe('18')
    expect(cellText(day, 'canopy', imperial)).toBe('')
    expect(cellText(day, 'notes', imperial)).toBe('Gauge')
  })

  it('read depths in the user’s units and trim notes, blank clearing', () => {
    expect(cellValue('irrigation_in', '25.4', metric)).toEqual({ ok: true, value: 1 })
    expect(cellValue('notes', '  ', imperial)).toEqual({ ok: true, value: null })
    expect(cellValue('canopy', 'lots', imperial).ok).toBe(false)
  })

  it('are named by day and say where irrigation came from', () => {
    expect(cellLabel(day, 'Rain')).toBe('Rain, Wed, Jul 15')
    expect(depthUnitName(metric)).toBe('millimeters')
    expect(irrigationFrom('pivot', 'traveler')).toBe('from traveler')
    expect(irrigationFrom('field', 'pivot')).toBe('from field')
    expect(irrigationFrom('entered', 'pivot')).toBeNull()
  })
})
