import { describe, expect, it } from 'vitest'

import type { WeatherPanelDay } from '@/types/serializers'

import { addDays } from '../dates'
import { units } from '../units'
import { DEFAULT_WINDOW_DAYS } from './fieldChart'
import type { Palette } from './palette'
import { defaultView, runningTotal, showPanel, weatherChartOption, weatherPanels } from './weatherCharts'

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
  et0_in: 0.2,
  precip_in: i % 10 === 0 ? 0.5 : 0,
  rain_in: i % 10 === 0 ? 0.4 : 0,
  snowfall_in: 0,
  snow_depth_in: null,
})) as unknown as WeatherPanelDay[]

const field = { fieldCapacity: 0.1, wiltingPoint: 0.04 }
// The balance's crop ET runs through the observed days
const cropEt = Object.fromEntries(days.filter((day) => !day.forecast).map((day) => [day.date, 0.1]))
const panel = (key: string, system: 'imperial' | 'metric' = 'imperial') =>
  weatherPanels(units(system), field, cropEt).find((p) => p.key === key)!
type SeriesOption = { name: string; type: string; stack?: string; xAxisIndex: number; data: (number | null)[] }

describe('weather charts', () => {
  it('opens on the last observed days and shades the forecast', () => {
    const option = weatherChartOption(panel('air_temperature'), days, units('imperial'), palette)
    expect(option.dataZoom).toEqual([{ type: 'inside', xAxisIndex: [0], startValue: days[60 - DEFAULT_WINDOW_DAYS].date }])
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

  it('stacks rain and the rest of the precipitation, with a running total in view below', () => {
    const option = weatherChartOption(panel('precipitation'), days, units('imperial'), palette)
    const [rain, other, total] = option.series as SeriesOption[]
    expect([rain, other].map((s) => [s.type, s.stack, s.xAxisIndex])).toEqual([['bar', 'precipitation', 0], ['bar', 'precipitation', 0]])
    expect([rain.data[30], other.data[30]]).toEqual([0.4, 0.1])
    expect(total).toMatchObject({ name: 'Precipitation total', type: 'line', xAxisIndex: 1 })
    // Counting from the first day in view (day 30), through the forecast: days 30, 40, 50 and 60
    const start = 60 - DEFAULT_WINDOW_DAYS
    expect(total.data[start - 1]).toBeNull()
    expect(total.data[start]).toBe(0.5)
    expect(total.data[64]).toBe(2)
  })

  it('recounts running totals for the days in view after a zoom', () => {
    const option = weatherChartOption(panel('precipitation'), days, units('imperial'), palette, { start: 0, end: 20 })
    const total = (option.series as SeriesOption[])[2]
    expect(total.data.slice(0, 21).at(-1)).toBe(1.5)
    expect(total.data[21]).toBeNull()
  })

  it('pairs reference and crop ET bars, and stops crop ET at today', () => {
    const option = weatherChartOption(panel('et'), days, units('imperial'), palette)
    const [reference, crop, referenceTotal, cropTotal] = option.series as SeriesOption[]
    expect([reference.stack, crop.stack]).toEqual([undefined, undefined])
    expect([reference.data[61], crop.data[59], crop.data[61]]).toEqual([0.2, 0.1, null])
    expect(referenceTotal.data[64]).toBe(Number((0.2 * (65 - defaultView(days).start)).toFixed(2)))
    expect(cropTotal.data[59]).toBe(Number((0.1 * DEFAULT_WINDOW_DAYS).toFixed(2)))
    expect(cropTotal.data[60]).toBeNull()
  })

  it('shows precipitation in mm for metric', () => {
    const option = weatherChartOption(panel('precipitation', 'metric'), days, units('metric'), palette)
    expect((option.series as SeriesOption[])[0].data[0]).toBeCloseTo(10.16, 2)
  })

  it('shows the snow chart only when there is snow', () => {
    expect(showPanel(panel('snow'), days)).toBe(false)
    const snowy = days.map((day, i) => (i === 3 ? { ...day, snow_depth_in: 2 } : day))
    expect(showPanel(panel('snow'), snowy)).toBe(true)
    expect(showPanel(panel('air_temperature'), days)).toBe(true)
  })

  it('treats a missing day as a gap in the running total, not a zero', () => {
    const value = (day: WeatherPanelDay) => (day.date === days[2].date ? null : 1)
    expect(runningTotal(days.slice(0, 4), value, { start: 0, end: 3 })).toEqual([1, 2, null, 3])
  })

  it('explains every chart', () => {
    for (const p of weatherPanels(units('metric'), field)) expect(p.info.length).toBeGreaterThan(40)
    expect(panel('air_temperature', 'metric').info).toContain('30 °C')
  })

  it('shows the day once in the tooltip, daily values before totals', () => {
    const option = weatherChartOption(panel('et'), days, units('imperial'), palette)
    const formatter = (option.tooltip as { formatter: (params: unknown) => string }).formatter
    const param = (seriesIndex: number, seriesName: string, value: number | null) => ({ axisValue: '2026-06-02', seriesIndex, seriesName, marker: '', value })
    const html = formatter([param(2, 'Reference ET total', 1.5), param(0, 'Reference ET', 0.2), param(1, 'Crop ET', null)])
    expect(html.match(/<strong>[^<]*<\/strong>/)![0]).not.toContain('2026-06-02')
    expect(html.indexOf('Reference ET<')).toBeLessThan(html.indexOf('Reference ET total'))
    expect(html).toContain('0.20 in')
    expect(html).toContain('—')
  })
})
