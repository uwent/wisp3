import { describe, expect, it } from 'vitest'

import type { WeatherPanelDay } from '@/types/serializers'

import { addDays } from '../dates'
import { units } from '../units'
import { DEFAULT_WINDOW_DAYS } from './fieldChart'
import type { EChartsCoreOption } from './echarts'
import type { Palette } from './palette'
import {
  combinedTable,
  correctedOn,
  defaultView,
  gddFrom,
  panelCsvRows,
  panelSummary,
  panelTable,
  runningTotal,
  seasonSliderOption,
  tableTsv,
  weatherChartOption,
  PLANTING_START_LENGTH,
  plantingStarts,
  weatherPanels,
} from './weatherCharts'

/** The legend's entry names (a line's entry is {name, itemStyle}) */
const legendNames = (option: EChartsCoreOption) =>
  (option.legend as { data: (string | { name: string })[] }).data.map((entry) =>
    typeof entry === 'string' ? entry : entry.name,
  )

const palette: Palette = {
  ink: '#000',
  inkMuted: '#666',
  line: '#ddd',
  surface: '#fff',
  rain: '#00f',
  irrigation: '#f80',
  canopy: '#0a0',
  ad: '#40a',
  warm: '#f60',
  sun: '#fc0',
  snow: '#ccc',
  system: '#2ec4f0',
  systemCasing: '#0c2d48',
  field: '#ffffff',
  fieldCasing: '#000000',
  shapeNew: '#ff8a1f',
  shapeUpdate: '#e05ce6',
  shapeSkip: '#c3c8cf',
  handle: '#1c5cab',
  depths: ['#1', '#2', '#3', '#4'],
  status: { full: '#00f', ok: '#0f0', caution: '#fa0', irrigate: '#f00' },
  dark: false,
}

// 60 observed days from Jun 1, then 5 forecast days; corrected from Jun 3 (the first two stored before)
const days = Array.from({ length: 65 }, (_, i) => ({
  date: addDays('2026-06-01', i),
  forecast: i >= 60,
  corrections: i >= 2 ? ['openmeteo-shortwave v1', 'openmeteo-rh v1', 'et0-fao56 v1'] : [],
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

const panel = (key: string, system: 'imperial' | 'metric' = 'imperial') =>
  weatherPanels(units(system)).find((p) => p.key === key)!
type SeriesOption = { name: string; type: string; stack?: string; xAxisIndex: number; data: (number | null)[] }

describe('weather charts', () => {
  it('opens on the last observed days and shades the forecast edge to edge', () => {
    const option = weatherChartOption(panel('air_temperature'), days, units('imperial'), palette)
    // The chart's axis and the shading's hidden one move together
    expect(option.dataZoom).toEqual([
      { type: 'inside', xAxisIndex: [0, 1], startValue: days[60 - DEFAULT_WINDOW_DAYS].date },
    ])
    const series = option.series as {
      id?: string
      type: string
      xAxisIndex?: number
      data: unknown[]
      barWidth?: string
      markArea?: { data: { xAxis: string }[][] }
    }[]
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
    const [first] = weatherChartOption(panel('air_temperature'), observed, units('imperial'), palette).series as {
      markArea?: unknown
    }[]
    expect(first.markArea).toBeUndefined()
  })

  it('stacks rain and the rest of the precipitation, with a running total in view below', () => {
    const option = weatherChartOption(panel('precipitation'), days, units('imperial'), palette)
    const [rain, other, total] = option.series as SeriesOption[]
    expect([rain, other].map((s) => [s.type, s.stack, s.xAxisIndex])).toEqual([
      ['bar', 'precipitation', 0],
      ['bar', 'precipitation', 0],
    ])
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

  it('draws reference ET as bars, with its running total in view below', () => {
    const option = weatherChartOption(panel('et'), days, units('imperial'), palette)
    const [reference, referenceTotal] = option.series as SeriesOption[]
    expect([reference.type, reference.stack, reference.data[61]]).toEqual(['bar', undefined, 0.2])
    expect(referenceTotal.data[64]).toBe(Number((0.2 * (65 - defaultView(days).start)).toFixed(2)))
  })

  it('shows precipitation in mm for metric', () => {
    const option = weatherChartOption(panel('precipitation', 'metric'), days, units('metric'), palette)
    expect((option.series as SeriesOption[])[0].data[0]).toBeCloseTo(10.16, 2)
  })

  it('adds snow to the precipitation chart only when there is snow', () => {
    const names = (d: WeatherPanelDay[]) =>
      (weatherChartOption(panel('precipitation'), d, units('imperial'), palette).series as SeriesOption[]).map(
        (s) => s.name,
      )
    expect(names(days)).toEqual([
      'Rain',
      'Snow and other',
      'Precipitation total',
      'Forecast shading',
      'Forecast shading',
    ])
    const snowy = days.map((day, i) =>
      i === 3 ? { ...day, snowfall_in: 1.5, snow_depth_in: 2 } : i === 4 ? { ...day, snow_depth_in: 1 } : day,
    )
    const [, , snowfall, snowDepth] = weatherChartOption(panel('precipitation'), snowy, units('imperial'), palette)
      .series as SeriesOption[]
    expect([snowfall.name, snowfall.type, snowfall.stack]).toEqual(['Snowfall', 'bar', undefined])
    expect([snowDepth.name, snowDepth.type]).toEqual(['Snow depth', 'line'])
    // Zero snow is no snow: a gap in the chart
    expect(snowfall.data.slice(2, 5)).toEqual([null, 1.5, null])
    expect(snowDepth.data.slice(2, 5)).toEqual([null, 2, 1])
  })

  it('names snow in the legend only when the days in view have some', () => {
    const legend = (d: WeatherPanelDay[], view?: { start: number; end: number }) =>
      legendNames(weatherChartOption(panel('precipitation'), d, units('imperial'), palette, view))
    // Snow early in the season, outside the opening view
    const snowy = days.map((day, i) => (i === 3 ? { ...day, snowfall_in: 1.5, snow_depth_in: 2 } : day))
    expect(legend(snowy)).toEqual(['Rain', 'Snow and other', 'Precipitation total'])
    expect(legend(snowy, { start: 0, end: 20 })).toEqual([
      'Rain',
      'Snow and other',
      'Snowfall',
      'Snow depth',
      'Precipitation total',
    ])
    // The series stay on the chart, for scrolling back to them
    const names = (
      weatherChartOption(panel('precipitation'), snowy, units('imperial'), palette).series as SeriesOption[]
    ).map((s) => s.name)
    expect(names).toContain('Snow depth')
  })

  it('leaves snow out of the tooltip on days without it', () => {
    const snowy = days.map((day, i) => (i === 3 ? { ...day, snowfall_in: 1.5 } : day))
    const option = weatherChartOption(panel('precipitation'), snowy, units('imperial'), palette)
    const formatter = (option.tooltip as { formatter: (params: unknown) => string }).formatter
    const param = (seriesIndex: number, seriesName: string, value: number | null) => ({
      axisValue: '2026-06-02',
      seriesIndex,
      seriesName,
      marker: '',
      value,
    })
    const html = formatter([param(0, 'Rain', 0), param(1, 'Snow and other', null), param(2, 'Snowfall', null)])
    expect(html).toContain('Snow and other')
    expect(html).not.toContain('Snowfall')
    expect(formatter([param(2, 'Snowfall', 1.5)])).toContain('1.50 in')
  })

  it('treats a missing day as a gap in the running total, not a zero', () => {
    const value = (day: WeatherPanelDay) => (day.date === days[2].date ? null : 1)
    expect(runningTotal(days.slice(0, 4), value, { start: 0, end: 3 })).toEqual([1, 2, null, 3])
  })

  it("draws a related measure's daily values in the lower grid, not added up", () => {
    const warm = days.map((day, i) => ({
      ...day,
      gdd: 20,
      gdd_since_emergence: 20 * (i + 1),
      cloud_cover_pct: 40,
      shortwave_mj: 20,
    }))
    const option = weatherChartOption(panel('gdd'), warm, units('imperial'), palette)
    const series = option.series as SeriesOption[]
    expect(series.map((s) => [s.name, s.type, s.xAxisIndex]).slice(0, 3)).toEqual([
      ['Degree days (50/86)', 'bar', 0],
      ['Since emergence', 'line', 1],
      ['Since the first day in view', 'line', 1],
    ])
    expect(series[1].data.slice(0, 3)).toEqual([20, 40, 60])
    const yAxis = option.yAxis as { name?: string; max?: number }[]
    expect(yAxis[1].name).toBe('Total')
    // Each series in the tooltip with its own decimals
    const formatter = (option.tooltip as { formatter: (params: unknown) => string }).formatter
    const html = formatter([
      { axisValue: warm[5].date, seriesIndex: 0, seriesName: 'Degree days (50/86)', marker: '', value: 20 },
      { axisValue: warm[5].date, seriesIndex: 1, seriesName: 'Since emergence', marker: '', value: 120 },
    ])
    expect(html).toContain('20.0 °F·d')
    expect(html).toContain('120 °F·d')

    // Lines' legend entries hide the symbol ECharts draws on them; bars keep theirs
    expect((option.legend as { data: unknown[] }).data).toEqual([
      'Degree days (50/86)',
      { name: 'Since emergence', itemStyle: { opacity: 0 } },
      { name: 'Since the first day in view', itemStyle: { opacity: 0 } },
    ])
    // The total in view starts again at the first day in view; a planting's total from its date
    const view = { start: 10, end: 20 }
    const inView = weatherChartOption(panel('gdd'), warm, units('imperial'), palette, view).series as SeriesOption[]
    expect(inView[2].data.slice(9, 13)).toEqual([null, 20, 40, 60])
    const planted = weatherPanels(units('imperial'), {
      gddPlanting: { label: 'planting (Jun 3)', totals: gddFrom(warm, warm[2].date) },
    }).find((p) => p.key === 'gdd')!
    const withPlanting = weatherChartOption(planted, warm, units('imperial'), palette).series as SeriesOption[]
    expect(withPlanting[3].name).toBe('Since planting (Jun 3)')
    expect(withPlanting[3].data.slice(0, 4)).toEqual([null, null, 20, 40])
    // A view's total isn't a day's value, so tables leave it out
    expect(panelTable(planted, warm, units('imperial')).columns).toEqual([
      'Degree days (50/86) (°F·d)',
      'Since emergence (°F·d)',
      'Since planting (Jun 3) (°F·d)',
    ])

    const solar = weatherChartOption(panel('solar'), warm, units('imperial'), palette)
    expect((solar.yAxis as { name?: string; max?: number }[])[1]).toMatchObject({ name: 'Cloud cover (%)', max: 100 })
    const cloud = (solar.tooltip as { formatter: (params: unknown) => string }).formatter([
      { axisValue: warm[5].date, seriesIndex: 1, seriesName: 'Cloud cover', marker: '', value: 40 },
    ])
    expect(cloud).toContain('40 %')
  })

  it('gives the charts a season slider opening on the same days', () => {
    const option = seasonSliderOption(days, palette, units('imperial'))
    const [slider] = option.dataZoom as { type: string; startValue: string; left: number; right: number }[]
    const chart = weatherChartOption(panel('air_temperature'), days, units('imperial'), palette)
    const [inside] = chart.dataZoom as { startValue: string }[]
    expect(slider).toMatchObject({ type: 'slider', startValue: inside.startValue, showDetail: false })
    expect((option.xAxis as { data: string[] }).data).toHaveLength(days.length)
  })

  it('offers each planting date once in the degree days menu, naming its plantings', () => {
    expect(
      plantingStarts([
        { label: 'River Sweet Corn', planted: '2026-05-10' },
        { label: 'Home North Potato', planted: '2026-04-01' },
        { label: 'Home South Potato', planted: '2026-04-01' },
      ]),
    ).toEqual([
      { date: '2026-04-01', label: 'Apr 1 – Home North Potato, Home South Potato' },
      { date: '2026-05-10', label: 'May 10 – River Sweet Corn' },
    ])
    const [long] = plantingStarts(
      ['A', 'B', 'C', 'D'].map((name) => ({ label: `Field ${name} Sweet Corn`, planted: '2026-04-01' })),
    )
    expect(long.label).toHaveLength(PLANTING_START_LENGTH)
    expect(long.label).toMatch(/^Apr 1 – Field A Sweet Corn, .*…$/)
  })

  it("marks freezing on the air temperature chart, in the user's units", () => {
    expect(panel('air_temperature').lines).toEqual([{ name: '32 °F', value: 32 }])
    expect(panel('air_temperature', 'metric').lines).toEqual([{ name: '0 °C', value: 0 }])
  })

  it('explains every chart', () => {
    for (const p of weatherPanels(units('metric'))) expect(p.info.length).toBeGreaterThan(40)
    expect(panel('air_temperature', 'metric').info).toContain('30 °C')
  })

  it('shows the day once in the tooltip, daily values before totals', () => {
    const option = weatherChartOption(panel('et'), days, units('imperial'), palette)
    const formatter = (option.tooltip as { formatter: (params: unknown) => string }).formatter
    const param = (seriesIndex: number, seriesName: string, value: number | null) => ({
      axisValue: '2026-06-02',
      seriesIndex,
      seriesName,
      marker: '',
      value,
    })
    const html = formatter([param(1, 'Reference ET total', 1.5), param(0, 'Reference ET', 0.2)])
    expect(html.match(/<strong>[^<]*<\/strong>/)![0]).not.toContain('2026-06-02')
    expect(html.indexOf('Reference ET<')).toBeLessThan(html.indexOf('Reference ET total'))
    expect(html).toContain('0.20 in')
    expect(formatter([param(0, 'Reference ET', null)])).toContain('—')
    expect(html).not.toContain('Corrected') // stored before the corrections
    const later = formatter([{ ...param(0, 'Reference ET', 0.2), axisValue: '2026-06-03' }])
    expect(later).toContain('Corrected (About › Weather)')
  })

  it('marks the panels whose values are corrected', () => {
    const corrected = Object.fromEntries(
      weatherPanels(units('imperial'))
        .filter((p) => p.corrected)
        .map((p) => [p.key, p.corrected]),
    )
    expect(corrected).toEqual({
      et: 'et0-fao56',
      humidity: 'openmeteo-rh',
      vpd: 'openmeteo-rh',
      solar: 'openmeteo-shortwave',
    })
    expect(correctedOn(days[2], 'openmeteo-rh')).toBe(true)
    expect(correctedOn(days[0], 'openmeteo-rh')).toBe(false)
  })
})

describe('gddFrom', () => {
  it('counts degree days from another day, none before it', () => {
    const counted = gddFrom(
      [
        { date: '2026-05-01', gdd: 5, gdd_since_emergence: 5 },
        { date: '2026-05-02', gdd: 7.25, gdd_since_emergence: 12.3 },
        { date: '2026-05-03', gdd: null, gdd_since_emergence: 12.3 },
        { date: '2026-05-04', gdd: 4, gdd_since_emergence: 16.3 },
      ] as unknown as WeatherPanelDay[],
      '2026-05-02',
    )
    expect(Object.values(counted)).toEqual([null, 7.3, 7.3, 11.3])
  })
})

describe('weather charts in words and tables', () => {
  it('adds up amounts over the last 7 days and the forecast', () => {
    // It rains every 10th day: none in the last 7 observed days (53–59), and on day 60, the first forecast day
    expect(panelSummary(panel('precipitation'), days, units('imperial'))).toBe(
      'Last 7 days: Rain 0.00, Snow and other 0.00 in. Next 5 days (forecast): Rain 0.40, Snow and other 0.10 in.',
    )
  })

  it('gives levels on the latest observed day and their range', () => {
    const changing = days.map((day, i) => ({ ...day, tmax_f: 70 + i }))
    expect(panelSummary(panel('air_temperature'), changing, units('imperial'))).toBe(
      'Jul 30: High 129.0, Low 60.0 °F. Last 7 days: High 123.0 to 129.0, Low 60.0 °F. ' +
        'Next 5 days (forecast): High 130.0 to 134.0, Low 60.0 °F.',
    )
  })

  it("names a lower grid's measure on the latest day, and lists it in its own unit", () => {
    const sunny = days.map((day) => ({ ...day, shortwave_mj: 20, cloud_cover_pct: 35 }))
    expect(panelSummary(panel('solar'), sunny, units('imperial'))).toBe(
      'Jul 30: Cloud cover 35 %. Last 7 days: Solar radiation 140.00 MJ/m². ' +
        'Next 5 days (forecast): Solar radiation 100.00 MJ/m².',
    )
    const table = panelTable(panel('solar'), sunny, units('imperial'))
    expect(table.columns).toEqual(['Solar radiation (MJ/m²)', 'Cloud cover (%)'])
    expect(table.rows[0].values).toEqual(['20.00', '35'])
    expect(panelCsvRows(panel('solar'), sunny, units('imperial'))[0]).toEqual([
      'Date',
      'Forecast',
      'Solar radiation (MJ/m²)',
      'Cloud cover (%)',
    ])
  })

  it('says so when there are no values', () => {
    expect(panelSummary(panel('air_temperature'), [], units('imperial'))).toBe('No weather values yet.')
  })

  it('lists the daily values newest first, in the user units', () => {
    const table = panelTable(panel('air_temperature', 'metric'), days, units('metric'))
    expect(table.columns).toEqual(['High (°C)', 'Low (°C)'])
    expect(table.rows[0]).toEqual({ date: days[64].date, forecast: true, values: ['26.7', '15.6'] })
    expect(table.rows).toHaveLength(65)
  })

  it("puts every panel's columns in one table, a shared one once, and copies it as tab-separated text", () => {
    const sunny = days.map((day) => ({ ...day, shortwave_mj: 20, cloud_cover_pct: 35 }))
    const both = [panel('air_temperature'), panel('solar'), panel('solar')]
    const table = combinedTable(both, sunny, units('imperial'))
    expect(table.columns).toEqual(['High (°F)', 'Low (°F)', 'Solar radiation (MJ/m²)', 'Cloud cover (%)'])
    expect(table.rows[0].values).toEqual(['80.0', '60.0', '20.00', '35'])
    expect(table.rows).toHaveLength(65)
    const lines = tableTsv(table).split('\n')
    expect(lines[0]).toBe('Date\tForecast\tHigh (°F)\tLow (°F)\tSolar radiation (MJ/m²)\tCloud cover (%)')
    expect(lines[1]).toBe(`${days[64].date}\tyes\t80.0\t60.0\t20.00\t35`)
    expect(tableTsv({ columns: ['Notes'], rows: [{ date: '2026-07-01', forecast: false, values: [null] }] })).toBe(
      'Date\tForecast\tNotes\n2026-07-01\tno\t',
    )
  })

  it('gives the daily values for a CSV oldest first, as stored, with zeros kept', () => {
    const rows = panelCsvRows(panel('precipitation'), days, units('imperial'))
    expect(rows[0]).toEqual(['Date', 'Forecast', 'Rain (in)', 'Snow and other (in)'])
    expect(rows[1]).toEqual(['2026-06-01', 'no', 0.4, 0.1])
    expect(rows[2]).toEqual(['2026-06-02', 'no', 0, 0])
    expect(rows.at(-1)).toEqual([days[64].date, 'yes', 0, 0])
    expect(rows).toHaveLength(66)
  })
})
