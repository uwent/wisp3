import { describe, expect, it } from 'vitest'

import type { WeatherPanelDay } from '@/types/serializers'

import { addDays } from '../dates'
import { units } from '../units'
import { DEFAULT_WINDOW_DAYS } from './fieldChart'
import type { Palette } from './palette'
import { weatherChartOption, weatherPanels } from './weatherCharts'

const palette: Palette = {
  ink: '#000', inkMuted: '#666', line: '#ddd', surface: '#fff', rain: '#00f', irrigation: '#0a0', ad: '#40a', warm: '#f60',
  depths: ['#1', '#2', '#3', '#4'], status: { full: '#00f', ok: '#0f0', caution: '#fa0', irrigate: '#f00' }, dark: false,
}

// 60 observed days from Jun 1, then 5 forecast days
const days = Array.from({ length: 65 }, (_, i) => ({
  date: addDays('2026-06-01', i),
  forecast: i >= 60,
  tmax_f: 80,
  tmin_f: 60,
  soil_moisture_0_7cm: 0.2,
  soil_temp_0_7cm_f: 68,
})) as unknown as WeatherPanelDay[]

const field = { fieldCapacity: 0.1, wiltingPoint: 0.04 }
const panel = (key: string, system: 'imperial' | 'metric' = 'imperial') =>
  weatherPanels(units(system), field).find((p) => p.key === key)!

describe('weather charts', () => {
  it('opens on the last observed days and shades the forecast', () => {
    const option = weatherChartOption(panel('air_temperature'), days, units('imperial'), palette)
    expect(option.dataZoom).toEqual([{ type: 'inside', startValue: days[60 - DEFAULT_WINDOW_DAYS].date }])
    const [first] = option.series as { markArea?: { data: { xAxis: string }[][] } }[]
    expect(first.markArea!.data[0].map((point) => point.xAxis)).toEqual([days[60].date, days[64].date])
  })

  it('shows temperatures in the user units', () => {
    const option = weatherChartOption(panel('air_temperature', 'metric'), days, units('metric'), palette)
    const [high] = option.series as { data: (number | null)[] }[]
    expect(high.data[0]).toBeCloseTo(26.67, 1)
  })

  it('shows soil moisture as percent by volume, and names depths in cm for metric', () => {
    const option = weatherChartOption(panel('soil_moisture'), days, units('imperial'), palette)
    const [shallow] = option.series as { data: (number | null)[] }[]
    expect(shallow.data[0]).toBe(20)
    expect(panel('soil_moisture', 'metric').series[0].name).toBe('0–8 cm')
  })

  it('has no forecast shading without forecast days', () => {
    const observed = days.slice(0, 60)
    const [first] = weatherChartOption(panel('air_temperature'), observed, units('imperial'), palette).series as { markArea?: unknown }[]
    expect(first.markArea).toBeUndefined()
  })
})
