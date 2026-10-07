import { describe, expect, it } from 'vitest'

import type { FieldDay, PlantingSummary } from '@/types/serializers'

import { units } from '../units'
import { fieldChartOption, roundUp, thresholds } from './fieldChart'
import type { Palette } from './palette'
import { weatherPanels } from './weatherCharts'

const palette: Palette = {
  ink: '#000', inkMuted: '#666', line: '#ddd', surface: '#fff', rain: '#00f', irrigation: '#f80', canopy: '#0a0', ad: '#40a', warm: '#f60', snow: '#ccc',
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

  it('outlines modeled rain only where an entry replaced it, on a field using modeled rain', () => {
    const days = [
      day('2026-07-01', { rain: 1, rain_source: 'entered', rain_model: 0.4 }),
      day('2026-07-02', { rain: 0.3, rain_source: 'model', rain_model: 0.3 }),
      day('2026-07-03', { soil_moisture_pct: 9, moisture_source: 'entered' }),
    ]
    const option = fieldChartOption({ days, summary, rootZoneDepth: 16, units: units('imperial'), mode: 'ad', palette })
    const series = option.series as { id: string; name: string; data: unknown[] }[]
    expect(series.find((s) => s.id === 'modeled-rain')!.data).toEqual([0.4, null, null])
    expect(series.find((s) => s.id === 'rain')!.data).toEqual([1, 0.3, 0])
    // the reading day is marked on the AD line
    expect(series.find((s) => s.id === 'balance')!.data[2]).toMatchObject({ symbol: 'circle' })
  })

  it('dodges the modeled rain beside the rain, and outlines it on days a field using only entered rain left it out', () => {
    const days = [day('2026-07-01', { rain: 1, rain_source: 'entered', rain_model: 0.4 }), day('2026-07-02', { rain: 0, rain_source: 'none', rain_model: 0.3 })]
    const series = fieldChartOption({ days, summary, rootZoneDepth: 16, units: units('imperial'), mode: 'ad', palette }).series as {
      id: string
      name: string
      data: unknown[]
      barGap?: string
    }[]
    const modeled = series.find((s) => s.id === 'modeled-rain')!
    expect(modeled.data).toEqual([0.4, 0.3])
    expect(modeled.barGap).not.toBe('-100%')
  })

  it('totals rain and irrigation over the days in view, with the modeled rain when the balance left some out', () => {
    const days = [
      day('2026-07-01', { rain: 0.5, rain_model: 0.5 }),
      day('2026-07-02', { rain: 1, rain_source: 'entered', rain_model: 0.4, irrigation: 0.6, irrigation_source: 'entered' }),
      day('2026-07-03', { rain: 0.2, rain_model: 0.2 }),
    ]
    const totals = (view?: { start: number; end: number }) => {
      const series = fieldChartOption({ days, summary, rootZoneDepth: 16, units: units('imperial'), mode: 'ad', palette, view }).series as {
        id: string
        data: (number | null)[]
      }[]
      return Object.fromEntries(series.filter((s) => s.id.startsWith('total-')).map((s) => [s.id, s.data]))
    }
    expect(totals()).toEqual({ 'total-rain': [0.5, 1.5, 1.7], 'total-modeled': [0.5, 0.9, 1.1], 'total-irrigation': [0, 0.6, 0.6] })
    expect(totals({ start: 1, end: 2 })['total-rain']).toEqual([null, 1, 1.2])
    const plain = days.map((d) => ({ ...d, rain: d.rain_model, rain_source: 'model' as const }))
    const ids = (fieldChartOption({ days: plain, summary, rootZoneDepth: 16, units: units('imperial'), mode: 'ad', palette }).series as { id: string }[]).map((s) => s.id)
    expect(ids).not.toContain('total-modeled')
  })

  it('draws the canopy as modeled, with dots for the readings', () => {
    const days = [day('2026-07-01', { canopy: 20, canopy_entered: 20 }), day('2026-07-02', { canopy: 25 }), day('2026-07-03', { canopy: 30.456 })]
    const option = fieldChartOption({ days, summary, rootZoneDepth: 16, units: units('imperial'), mode: 'ad', palette })
    const series = option.series as { id: string; name: string; type: string; data: unknown[]; xAxisIndex: number }[]
    expect(series.find((s) => s.id === 'canopy')).toMatchObject({ name: 'Canopy cover', type: 'line', xAxisIndex: 3, data: [20, 25, 30.46] })
    expect(series.find((s) => s.id === 'canopy-readings')).toMatchObject({ name: 'Canopy cover' })
    expect(series.find((s) => s.id === 'canopy-readings')).toMatchObject({ type: 'line', symbol: 'circle', lineStyle: { width: 0 }, xAxisIndex: 3, data: [20, null, null] })
    const lai = fieldChartOption({ days, summary, rootZoneDepth: 16, units: units('imperial'), mode: 'ad', palette, canopy: 'lai' })
    expect((lai.series as { id: string; name: string }[]).find((s) => s.id === 'canopy-readings')!.name).toBe('LAI')
    expect((lai.yAxis as { name: string }[])[3].name).toBe('LAI')
  })

  it('continues the line dashed through the forecast, with the ensemble range and planned irrigation', () => {
    const days = [day('2026-07-01', { ad: 0.3 }), day('2026-07-02', { ad: 0.2 })]
    const forecastDays = [
      day('2026-07-03', { ad: 0.1, rain: 0.2, rain_source: 'forecast' }),
      day('2026-07-04', { ad: 0.4, irrigation: 0.5, irrigation_source: 'entered' }),
    ]
    const projection = [
      { date: '2026-07-03', ad: 0.1, p10: 0.05, p50: 0.1, p90: 0.2, chance: 0.1, dry_ad: null },
      { date: '2026-07-04', ad: 0.4, p10: 0.3, p50: 0.4, p90: 0.45, chance: 0.2, dry_ad: null },
    ]
    const option = fieldChartOption({
      days, forecastDays, summary: { ...summary, projection }, rootZoneDepth: 16, units: units('imperial'), mode: 'ad', palette,
    })
    const series = option.series as { id: string; name: string; data: unknown[]; stack?: string }[]
    const named = (id: string) => series.find((s) => s.id === id)!
    expect(named('balance').data).toEqual([{ value: 0.3 }, { value: 0.2 }, null, null])
    // From today's AD on
    expect(named('forecast').data).toEqual([null, 0.2, 0.1, 0.4])
    expect(named('range-low').data).toEqual([null, 0.2, 0.05, 0.3])
    expect(named('range').data).toEqual([null, 0, 0.15, 0.15])
    expect(named('irrigation').data).toEqual([0, 0, null, null])
    expect(named('planned').data).toEqual([null, null, 0, 0.5])
    expect(named('rain').data[2]).toMatchObject({ value: 0.2, itemStyle: { opacity: 0.4 } })
    // The slider outlines the first series: observed and projected AD
    expect(series[0].data).toEqual([0.3, 0.2, 0.1, 0.4])
  })

  it('adds the no-rain projection for a field using only entered rain', () => {
    const days = [day('2026-07-01', { ad: 0.3 }), day('2026-07-02', { ad: 0.2 })]
    const forecastDays = [day('2026-07-03', { ad: 0.6, rain: 0.5, rain_source: 'forecast' })]
    const projection = [{ date: '2026-07-03', ad: 0.6, p10: null, p50: null, p90: null, chance: null, dry_ad: 0.1 }]
    const option = fieldChartOption({
      days, forecastDays, summary: { ...summary, projection }, rootZoneDepth: 16, units: units('imperial'), mode: 'ad', palette,
    })
    const dry = (option.series as { name: string; data: unknown[] }[]).find((s) => s.name === 'If no rain falls')!
    expect(dry.data).toEqual([null, 0.2, 0.1])
    expect((option.legend as { data: string[] }).data).toContain('If no rain falls')
    const without = fieldChartOption({
      days, forecastDays, summary: { ...summary, projection: [{ ...projection[0], dry_ad: null }] }, rootZoneDepth: 16, units: units('imperial'), mode: 'ad', palette,
    })
    expect((without.series as { name: string }[]).map((s) => s.name)).not.toContain('If no rain falls')
  })

  it('groups the legend by measure, and keeps the thresholds, today and the forecast shading out of it', () => {
    const days = [day('2026-07-01', { ad: 0.3 }), day('2026-07-02', { ad: 0.2 })]
    const forecastDays = [day('2026-07-03', { ad: 0.1, irrigation: 0.5, irrigation_source: 'entered' })]
    const projection = [{ date: '2026-07-03', ad: 0.1, p10: 0.05, p50: 0.1, p90: 0.2, chance: 0.1, dry_ad: null }]
    const option = fieldChartOption({
      days, forecastDays, summary: { ...summary, projection }, rootZoneDepth: 16, units: units('imperial'), mode: 'ad', palette,
    })
    expect((option.legend as { data: string[] }).data).toEqual(['Allowable depletion', 'Rain', 'Irrigation', 'Canopy cover'])
    const series = option.series as { id: string; name: string; markLine?: { data: object[] }; markArea?: { data: unknown[] } }[]
    const group = (name: string) => series.filter((s) => s.name === name).map((s) => s.id)
    expect(group('Allowable depletion')).toEqual(['balance', 'range-low', 'range', 'forecast'])
    expect(group('Rain')).toEqual(['rain', 'modeled-rain', 'total-rain'])
    expect(group('Irrigation')).toEqual(['irrigation', 'planned', 'total-irrigation'])
    // On the series outside the legend: four threshold lines and today; the zone below the trigger and the forecast
    const always = series.find((s) => s.id === 'slider')!
    expect(always.markLine!.data).toHaveLength(5)
    expect(always.markLine!.data.at(-1)).toMatchObject({ xAxis: '2026-07-02' })
    expect(always.markArea!.data).toHaveLength(2)
    expect(series.filter((s) => s.id !== 'slider').every((s) => !s.markLine && !s.markArea)).toBe(true)
    // The forecast shaded edge to edge on all four panels, by full-width bars on hidden axes the zoom moves too
    const shading = series.filter((s) => s.id.startsWith('shading-')) as unknown as { xAxisIndex: number; data: unknown[]; barWidth: string }[]
    expect(shading.map((s) => [s.xAxisIndex, s.barWidth])).toEqual([[4, '100%'], [5, '100%'], [6, '100%'], [7, '100%']])
    expect(shading[0].data).toEqual([null, null, 1])
    expect((option.dataZoom as { xAxisIndex: number[] }[])[0].xAxisIndex).toEqual([0, 1, 2, 3, 4, 5, 6, 7])
  })

  it('stacks deep drainage on the field capacity line, and lists it in the tooltip even when none', () => {
    const days = [day('2026-07-01', { ad: 0.48, deep_drainage: 0.3 }), day('2026-07-02', { ad: 0.4 })]
    const option = fieldChartOption({ days, summary, rootZoneDepth: 16, units: units('imperial'), mode: 'ad', palette })
    const series = option.series as { id: string; name: string; data: unknown[]; stack?: string }[]
    expect(series.find((s) => s.id === 'drainage-base')).toMatchObject({ stack: 'drainage', data: [0.48, 0.48] })
    expect(series.find((s) => s.id === 'drainage')).toMatchObject({ name: 'Deep drainage', stack: 'drainage', data: [0.3, 0] })
    expect((option.legend as { data: string[] }).data).toContain('Deep drainage')
    const formatter = (option.tooltip as { formatter: (params: unknown) => string }).formatter
    expect(formatter([{ dataIndex: 0 }])).toContain('Deep drainage</td><td>0.30 in')
    expect(formatter([{ dataIndex: 1 }])).toContain('Deep drainage</td><td>0.00 in')

    // In percent moisture, the same depth over the root zone; and none of it without drainage
    const moisture = fieldChartOption({ days, summary, rootZoneDepth: 16, units: units('imperial'), mode: 'moisture', palette })
    expect((moisture.series as { id: string; data: unknown[] }[]).find((s) => s.id === 'drainage')!.data).toEqual([1.875, 0])
    const dry = fieldChartOption({ days: [day('2026-07-02')], summary, rootZoneDepth: 16, units: units('imperial'), mode: 'ad', palette })
    expect((dry.series as { id: string }[]).map((s) => s.id)).not.toContain('drainage')
  })

  it('rounds an axis top up to a round number', () => {
    expect([roundUp(1.764), roundUp(45), roundUp(12.3), roundUp(0.48), roundUp(2)]).toEqual([2, 45, 15, 0.5, 2])
  })

  it('leaves the forecast out when there is none', () => {
    const option = fieldChartOption({ days: [day('2026-07-01')], summary, rootZoneDepth: 16, units: units('imperial'), mode: 'ad', palette })
    const ids = (option.series as { id: string }[]).map((s) => s.id)
    expect(ids).not.toContain('forecast')
    expect(ids).not.toContain('planned')
  })

  it('compares modeled soil moisture with the field capacity in percent', () => {
    const panel = weatherPanels(units('imperial'), { field: { fieldCapacity: 0.1, wiltingPoint: 0.04 } }).find((p) => p.key === 'soil_moisture')!
    expect(panel.lines).toEqual([{ name: 'Field capacity', value: 10 }, { name: 'Wilting point', value: 4 }])
  })
})
