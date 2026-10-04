import { describe, expect, it } from 'vitest'

import type { FieldDay, PlantingSummary } from '@/types/serializers'

import { units } from '../units'
import { fieldChartOption, thresholds } from './fieldChart'
import type { Palette } from './palette'
import { weatherPanels } from './weatherCharts'

const palette: Palette = {
  ink: '#000', inkMuted: '#666', line: '#ddd', surface: '#fff', rain: '#00f', irrigation: '#0a0', ad: '#40a', warm: '#f60',
  depths: ['#1', '#2', '#3', '#4'], status: { full: '#00f', ok: '#0f0', caution: '#fa0', irrigate: '#f00' }, dark: false,
}

const summary = {
  ad_max: 0.48, ad_pwp: -0.48, target_in: 0.192, pct_at_ad_zero: 7, taw: 0.96,
} as PlantingSummary

const day = (date: string, overrides: Partial<FieldDay> = {}): FieldDay => ({
  date, et0: 0.2, et0_source: 'model', adj_et: 0.15, et_source: 'computed', rain: 0, rain_source: 'model', rain_model: 0,
  irrigation: 0, irrigation_source: 'none', pivot_inches: null, soil_moisture_pct: null, moisture_source: null, canopy: 50,
  canopy_entered: null, ad: 0.3, pct_moisture: 9.5, deep_drainage: 0, notes: null, ...overrides,
})

describe('field chart', () => {
  it('draws thresholds in display units', () => {
    const lines = thresholds({ summary, rootZoneDepth: 16, units: units('metric'), mode: 'ad', palette })
    expect(lines.map((line) => line.name)).toEqual(['Field capacity', 'Target', 'Irrigate (MAD)', 'Wilting point'])
    expect(lines[0].value).toBeCloseTo(12.192)
  })

  it('draws thresholds as percent moisture', () => {
    const lines = thresholds({ summary, rootZoneDepth: 16, units: units('imperial'), mode: 'moisture', palette })
    expect(lines[0].value).toBeCloseTo(10) // field capacity
    expect(lines[2].value).toBeCloseTo(7) // AD = 0
  })

  it('outlines modeled rain only where an entry replaced it', () => {
    const days = [
      day('2026-07-01', { rain: 1, rain_source: 'entered', rain_model: 0.4 }),
      day('2026-07-02', { rain: 0.3, rain_source: 'model', rain_model: 0.3 }),
      day('2026-07-03', { soil_moisture_pct: 9, moisture_source: 'entered' }),
    ]
    const option = fieldChartOption({ days, summary, rootZoneDepth: 16, units: units('imperial'), mode: 'ad', palette })
    const series = option.series as { name: string; data: unknown[] }[]
    expect(series.find((s) => s.name === 'Modeled rain')!.data).toEqual([0.4, null, null])
    expect(series.find((s) => s.name === 'Rain')!.data).toEqual([1, 0.3, 0])
    // the reading day is marked on the AD line
    expect(series[0].data[2]).toMatchObject({ symbol: 'circle' })
  })

  it('compares modeled soil moisture with the field capacity in percent', () => {
    const panel = weatherPanels(units('imperial'), { fieldCapacity: 0.1, wiltingPoint: 0.04 }).find((p) => p.key === 'soil_moisture')!
    expect(panel.lines).toEqual([{ name: 'Field capacity', value: 10 }, { name: 'Wilting point', value: 4 }])
  })
})
