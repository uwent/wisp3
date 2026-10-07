import { describe, expect, it } from 'vitest'

import type { WeatherPanelDay } from '@/types/serializers'

import { addDays } from '../dates'
import { units } from '../units'
import { DEFAULT_WINDOW_DAYS } from './fieldChart'
import type { Palette } from './palette'
import { defaultView, type FieldRain, runningTotal, weatherChartOption, weatherPanels } from './weatherCharts'

const palette: Palette = {
  ink: '#000', inkMuted: '#666', line: '#ddd', surface: '#fff', rain: '#00f', irrigation: '#f80', canopy: '#0a0', ad: '#40a', warm: '#f60', snow: '#ccc',
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
// The balance's crop ET, through the projection; the last forecast day has none (the projection ends there)
const cropEt = Object.fromEntries(days.slice(0, -1).map((day) => [day.date, 0.1]))
const panel = (key: string, system: 'imperial' | 'metric' = 'imperial') =>
  weatherPanels(units(system), { field, cropEt }).find((p) => p.key === key)!
type SeriesOption = { name: string; type: string; stack?: string; xAxisIndex: number; data: (number | null)[] }

describe('weather charts', () => {
  it('opens on the last observed days and shades the forecast edge to edge', () => {
    const option = weatherChartOption(panel('air_temperature'), days, units('imperial'), palette)
    // The chart's axis and the shading's hidden one move together
    expect(option.dataZoom).toEqual([{ type: 'inside', xAxisIndex: [0, 1], startValue: days[60 - DEFAULT_WINDOW_DAYS].date }])
    const series = option.series as { id?: string; type: string; xAxisIndex?: number; data: unknown[]; barWidth?: string; markArea?: { data: { xAxis: string }[][] } }[]
    // Named over the forecast days
    expect(series[0].markArea!.data[0].map((point) => point.xAxis)).toEqual([days[60].date, days[64].date])
    // Shaded by full-width bars on the forecast days, on the hidden axis
    const shading = series.find((s) => s.id === 'shading-0')!
    expect(shading).toMatchObject({ type: 'bar', xAxisIndex: 1, barWidth: '100%' })
    expect(shading.data.slice(58, 62)).toEqual([null, null, 1, 1])
    expect((option.xAxis as { show?: boolean }[])[1].show).toBe(false)
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

  it('pairs reference and crop ET bars, with crop ET through the projection', () => {
    const option = weatherChartOption(panel('et'), days, units('imperial'), palette)
    const [reference, crop, referenceTotal, cropTotal] = option.series as SeriesOption[]
    expect([reference.stack, crop.stack]).toEqual([undefined, undefined])
    expect([reference.data[61], crop.data[59], crop.data[61], crop.data[64]]).toEqual([0.2, 0.1, 0.1, null])
    expect(referenceTotal.data[64]).toBe(Number((0.2 * (65 - defaultView(days).start)).toFixed(2)))
    expect(cropTotal.data[63]).toBe(Number((0.1 * (DEFAULT_WINDOW_DAYS + 4)).toFixed(2)))
    expect(cropTotal.data[64]).toBeNull()
  })

  it('shows precipitation in mm for metric', () => {
    const option = weatherChartOption(panel('precipitation', 'metric'), days, units('metric'), palette)
    expect((option.series as SeriesOption[])[0].data[0]).toBeCloseTo(10.16, 2)
  })

  it('adds snow to the precipitation chart only when there is snow', () => {
    const names = (d: WeatherPanelDay[]) =>
      (weatherChartOption(panel('precipitation'), d, units('imperial'), palette).series as SeriesOption[]).map((s) => s.name)
    expect(names(days)).toEqual(['Rain', 'Snow and other', 'Precipitation total', 'Forecast shading', 'Forecast shading'])
    const snowy = days.map((day, i) => (i === 3 ? { ...day, snowfall_in: 1.5, snow_depth_in: 2 } : i === 4 ? { ...day, snow_depth_in: 1 } : day))
    const [, , snowfall, snowDepth] = weatherChartOption(panel('precipitation'), snowy, units('imperial'), palette).series as SeriesOption[]
    expect([snowfall.name, snowfall.type, snowfall.stack]).toEqual(['Snowfall', 'bar', undefined])
    expect([snowDepth.name, snowDepth.type]).toEqual(['Snow depth', 'line'])
    // Zero snow is no snow: a gap in the chart
    expect(snowfall.data.slice(2, 5)).toEqual([null, 1.5, null])
    expect(snowDepth.data.slice(2, 5)).toEqual([null, 2, 1])
  })

  it('names snow in the legend only when the days in view have some', () => {
    const legend = (d: WeatherPanelDay[], view?: { start: number; end: number }) =>
      (weatherChartOption(panel('precipitation'), d, units('imperial'), palette, view).legend as { data: string[] }).data
    // Snow early in the season, outside the opening view
    const snowy = days.map((day, i) => (i === 3 ? { ...day, snowfall_in: 1.5, snow_depth_in: 2 } : day))
    expect(legend(snowy)).toEqual(['Rain', 'Snow and other', 'Precipitation total'])
    expect(legend(snowy, { start: 0, end: 20 })).toEqual(['Rain', 'Snow and other', 'Snowfall', 'Snow depth', 'Precipitation total'])
    // The series stay on the chart, for scrolling back to them
    const names = (weatherChartOption(panel('precipitation'), snowy, units('imperial'), palette).series as SeriesOption[]).map((s) => s.name)
    expect(names).toContain('Snow depth')
  })

  it('leaves snow out of the tooltip on days without it', () => {
    const snowy = days.map((day, i) => (i === 3 ? { ...day, snowfall_in: 1.5 } : day))
    const option = weatherChartOption(panel('precipitation'), snowy, units('imperial'), palette)
    const formatter = (option.tooltip as { formatter: (params: unknown) => string }).formatter
    const param = (seriesIndex: number, seriesName: string, value: number | null) => ({ axisValue: '2026-06-02', seriesIndex, seriesName, marker: '', value })
    const html = formatter([param(0, 'Rain', 0), param(1, 'Snow and other', null), param(2, 'Snowfall', null)])
    expect(html).toContain('Snow and other')
    expect(html).not.toContain('Snowfall')
    expect(formatter([param(2, 'Snowfall', 1.5)])).toContain('1.50 in')
  })

  describe("with the field's rain", () => {
    // Day 30: rain entered over the model's 0.5; day 31: an entered zero; day 40: the model's, used
    const fieldRain = (unused: 'none' | 'model' = 'model'): FieldRain =>
      Object.fromEntries(
        days.map((day, i) => [
          day.date,
          i === 30
            ? { rain: 0.8, rain_source: 'entered', rain_model: 0.5 }
            : i === 31
              ? { rain: 0, rain_source: 'entered', rain_model: 0 }
              : { rain: unused === 'none' && !day.forecast ? 0 : day.precip_in, rain_source: day.forecast ? 'forecast' : unused, rain_model: day.precip_in },
        ]),
      )
    const option = (rain: FieldRain, view?: { start: number; end: number }) =>
      weatherChartOption(weatherPanels(units('imperial'), { fieldRain: rain }).find((p) => p.key === 'precipitation')!, days, units('imperial'), palette, view)
    type Item = number | null | { value: number; unused?: boolean; itemStyle: { color: string; borderType: string } }

    it('adds the entered rain beside the model, and outlines the modeled rain it replaced', () => {
      const series = option(fieldRain()).series as { name: string; data: Item[]; stack?: string }[]
      expect(series.map((s) => s.name).filter((name) => name !== 'Forecast shading')).toEqual([
        'Rain',
        'Snow and other',
        'Entered rain',
        'Modeled total',
        'Used by the balance',
      ])
      const [rain, , entered] = series
      expect(entered.stack).toBeUndefined()
      expect(entered.data.slice(29, 33)).toEqual([null, 0.8, 0, null])
      expect(rain.data[30]).toMatchObject({ value: 0.4, unused: true, itemStyle: { color: 'transparent', borderType: 'dashed' } })
      expect(rain.data[40]).toBe(0.4)
    })

    it('outlines every modeled day the balance leaves out on a field using only entered rain, but not the forecast', () => {
      const [rain] = option(fieldRain('none')).series as { data: Item[] }[]
      expect(rain.data[40]).toMatchObject({ value: 0.4, unused: true })
      expect(rain.data[60]).toBe(0.4)
    })

    it("totals the model's precipitation and the rain the balance used", () => {
      const series = option(fieldRain('none'), { start: 30, end: 64 }).series as { name: string; data: (number | null)[] }[]
      const total = (name: string) => series.find((s) => s.name === name)!.data[64]
      // Model: days 30, 40, 50 and 60; balance: the 0.8 entered and the forecast's 0.5 on day 60
      expect([total('Modeled total'), total('Used by the balance')]).toEqual([2, 1.3])
    })

    it('names entered rain in the legend and tooltip only where there is some', () => {
      const legend = (view: { start: number; end: number }) => (option(fieldRain(), view).legend as { data: string[] }).data
      expect(legend({ start: 0, end: 20 })).not.toContain('Entered rain')
      expect(legend({ start: 20, end: 40 })).toContain('Entered rain')
      const formatter = (option(fieldRain()).tooltip as { formatter: (params: unknown) => string }).formatter
      const param = (seriesIndex: number, seriesName: string, value: number | null, data: unknown = value) =>
        ({ axisValue: days[30].date, seriesIndex, seriesName, marker: '', value, data })
      expect(formatter([param(0, 'Rain', 0.4), param(2, 'Entered rain', null)])).not.toContain('Entered rain')
      expect(formatter([param(0, 'Rain', 0.4, { value: 0.4, unused: true }), param(2, 'Entered rain', 0)])).toMatch(/not used[\s\S]*Entered rain/)
    })
  })

  it('treats a missing day as a gap in the running total, not a zero', () => {
    const value = (day: WeatherPanelDay) => (day.date === days[2].date ? null : 1)
    expect(runningTotal(days.slice(0, 4), value, { start: 0, end: 3 })).toEqual([1, 2, null, 3])
  })

  it('explains every chart', () => {
    for (const p of weatherPanels(units('metric'), { field })) expect(p.info.length).toBeGreaterThan(40)
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
