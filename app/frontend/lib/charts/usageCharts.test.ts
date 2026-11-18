import { describe, expect, it } from 'vitest'

import type { Palette } from './palette'
import { funnelShares, percent, weeklyActiveOption, weeklyEntriesOption } from './usageCharts'

const palette = {
  ink: '#000',
  inkMuted: '#666',
  line: '#ddd',
  surface: '#fff',
  rain: '#00f',
  irrigation: '#f80',
  canopy: '#0a0',
  ad: '#40a',
  depths: ['#1', '#2', '#3', '#4'],
} as unknown as Palette

const weeks = ['2026-07-06', '2026-07-13']
type Series = { name: string; type: string; data: number[]; stack?: string; itemStyle: { color: string } }

describe('weeklyActiveOption', () => {
  it('draws the season as bars, with no legend when alone', () => {
    const option = weeklyActiveOption(palette, weeks, [3, 5], null, 2026)
    const series = option.series as Series[]
    expect(series).toHaveLength(1)
    expect(series[0]).toMatchObject({ name: '2026', type: 'bar', data: [3, 5] })
    expect(option.legend).toBeUndefined()
    expect((option.xAxis as { data: string[] }).data).toEqual(['Jul 6', 'Jul 13'])
  })

  it('adds last season as a line on the same axis, with a legend', () => {
    const option = weeklyActiveOption(palette, weeks, [3, 5], [2, 4], 2026)
    const series = option.series as Series[]
    expect(series.map((s) => [s.name, s.type])).toEqual([
      ['2026', 'bar'],
      ['2025', 'line'],
    ])
    expect((option.legend as { data: string[] }).data).toEqual(['2026', '2025'])
    expect(Array.isArray(option.yAxis)).toBe(false)
  })
})

describe('weeklyEntriesOption', () => {
  it('stacks the kinds of entry in a fixed order and color', () => {
    const option = weeklyEntriesOption(palette, weeks, {
      rain: [1, 2],
      irrigation: [3, 0],
      soil_moisture: [0, 1],
      canopy: [0, 0],
    })
    const series = option.series as Series[]
    expect(series.map((s) => s.name)).toEqual(['Rain', 'Irrigation', 'Canopy', 'Soil moisture'])
    expect(series.every((s) => s.stack === 'entries')).toBe(true)
    expect(series.map((s) => s.itemStyle.color)).toEqual(['#00f', '#f80', '#0a0', '#40a'])
    expect(series[1].data).toEqual([3, 0])
  })
})

describe('funnelShares', () => {
  it("gives each step's share of the one before", () => {
    expect(funnelShares([40, 30, 15, 0, 0])).toEqual([1, 0.75, 0.5, 0, null])
    expect(funnelShares([0, 0])).toEqual([null, null])
  })

  it('formats shares as whole percents', () => {
    expect(percent(0.756)).toBe('76%')
    expect(percent(null)).toBe('—')
  })
})
