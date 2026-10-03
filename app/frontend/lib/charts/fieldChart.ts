import type { FieldDay, PlantingSummary } from '@/types/serializers'

import { formatDate } from '../dates'
import { ET_SOURCE_LABELS, rainOverridden, SOURCE_LABELS } from '../provenance'
import type { Units } from '../units'
import type { EChartsCoreOption } from './echarts'
import { baseOption, type Palette } from './palette'

/** Days shown before zooming out to the whole season */
export const DEFAULT_WINDOW_DAYS = 30

export type FieldChartMode = 'ad' | 'moisture'

export type FieldChartInput = {
  days: FieldDay[]
  summary: PlantingSummary
  rootZoneDepth: number
  units: Units
  mode: FieldChartMode
  palette: Palette
}

type Threshold = { name: string; value: number; color: string; dashed: boolean }

/** The horizontal reference lines, in the chart's units (display depth, or percent moisture) */
export function thresholds({ summary, rootZoneDepth, units, mode, palette }: Omit<FieldChartInput, 'days'>): Threshold[] {
  const value = (ad: number) =>
    mode === 'ad' ? (units.toDisplay('depth', ad) ?? 0) : summary.pct_at_ad_zero + (ad / rootZoneDepth) * 100
  const lines: Threshold[] = [
    { name: 'Field capacity', value: value(summary.ad_max), color: palette.status.full, dashed: true },
    { name: 'Irrigate (MAD)', value: value(0), color: palette.status.irrigate, dashed: false },
    { name: 'Wilting point', value: value(summary.ad_pwp), color: palette.inkMuted, dashed: true },
  ]
  if (summary.target_in !== null) {
    lines.splice(1, 0, { name: 'Target', value: value(summary.target_in), color: palette.status.caution, dashed: true })
  }
  return lines
}

export function fieldChartOption(input: FieldChartInput): EChartsCoreOption {
  const { days, units, mode, palette } = input
  const base = baseOption(palette)
  const dates = days.map((day) => day.date)
  const depth = (inches: number | null) => units.toDisplay('depth', inches)
  const round = (value: number | null, digits = 3) => (value === null ? null : Number(value.toFixed(digits)))
  const lines = thresholds(input)
  const zeroLine = lines.find((line) => line.name.startsWith('Irrigate'))!.value
  const wiltingLine = lines[lines.length - 1].value

  const balance = days.map((day) => ({
    value: round(mode === 'ad' ? depth(day.ad) : day.pct_moisture),
    // A soil moisture reading reset the balance on this day
    ...(day.moisture_source ? { symbol: 'circle', symbolSize: 8 } : {}),
  }))

  const axisLabel = { ...base.axisLabel, formatter: (iso: string) => formatDate(iso) }
  const yName = mode === 'ad' ? `AD (${units.label('depth')})` : 'Soil moisture (%)'

  return {
    animation: base.animation,
    textStyle: base.textStyle,
    legend: {
      type: 'scroll',
      top: 0,
      left: 0,
      right: 0,
      textStyle: { color: palette.ink, fontSize: 12 },
      data: [mode === 'ad' ? 'Allowable depletion' : 'Soil moisture', 'Rain', 'Modeled rain', 'Irrigation'],
    },
    tooltip: { ...base.tooltip, formatter: (params: unknown) => tooltip(days, params, units) },
    axisPointer: { link: [{ xAxisIndex: 'all' }] },
    grid: [
      { left: 48, right: 112, top: 56, height: '50%' },
      { left: 48, right: 112, top: '72%', bottom: 56 },
    ],
    xAxis: [
      { type: 'category', data: dates, gridIndex: 0, axisLabel: { show: false }, axisLine: base.axisLine, axisTick: { show: false } },
      { type: 'category', data: dates, gridIndex: 1, axisLabel, axisLine: base.axisLine },
    ],
    yAxis: [
      {
        type: 'value',
        gridIndex: 0,
        name: yName,
        nameTextStyle: { color: palette.inkMuted, align: 'left' },
        axisLabel: base.axisLabel,
        splitLine: base.splitLine,
        min: (extent: { min: number }) => Math.min(extent.min, wiltingLine),
        max: (extent: { max: number }) => Math.max(extent.max, lines[0].value),
      },
      {
        type: 'value',
        gridIndex: 1,
        name: `Water in (${units.label('depth')})`,
        nameTextStyle: { color: palette.inkMuted, align: 'left' },
        axisLabel: base.axisLabel,
        splitLine: base.splitLine,
        splitNumber: 2,
        min: 0,
      },
    ],
    dataZoom: [
      { type: 'inside', xAxisIndex: [0, 1], startValue: dates[Math.max(0, dates.length - DEFAULT_WINDOW_DAYS)] },
      {
        type: 'slider',
        xAxisIndex: [0, 1],
        bottom: 8,
        height: 20,
        startValue: dates[Math.max(0, dates.length - DEFAULT_WINDOW_DAYS)],
        borderColor: palette.line,
        textStyle: { color: palette.inkMuted },
        labelFormatter: (_: number, iso: string) => formatDate(iso),
      },
    ],
    series: [
      {
        name: mode === 'ad' ? 'Allowable depletion' : 'Soil moisture',
        type: 'line',
        xAxisIndex: 0,
        yAxisIndex: 0,
        data: balance,
        symbol: 'none',
        showSymbol: true,
        lineStyle: { width: 2, color: palette.ad },
        itemStyle: { color: palette.ad, borderColor: palette.surface, borderWidth: 2 },
        markLine: {
          silent: true,
          symbol: 'none',
          data: lines.map((line) => ({
            yAxis: line.value,
            name: line.name,
            lineStyle: { color: line.color, type: line.dashed ? 'dashed' : 'solid', width: 1 },
            label: { formatter: line.name, position: 'end', color: palette.inkMuted, fontSize: 11 },
          })),
        },
        // Below the trigger point, shaded faintly in the irrigate color
        markArea: {
          silent: true,
          itemStyle: { color: palette.status.irrigate, opacity: 0.07 },
          data: [[{ yAxis: zeroLine }, { yAxis: wiltingLine }]],
        },
      },
      {
        name: 'Rain',
        type: 'bar',
        stack: 'water',
        xAxisIndex: 1,
        yAxisIndex: 1,
        data: days.map((day) => round(depth(day.rain))),
        itemStyle: { color: palette.rain },
        barMaxWidth: 12,
      },
      {
        name: 'Irrigation',
        type: 'bar',
        stack: 'water',
        xAxisIndex: 1,
        yAxisIndex: 1,
        data: days.map((day) => round(depth(day.irrigation))),
        itemStyle: { color: palette.irrigation, borderRadius: [2, 2, 0, 0] },
        barMaxWidth: 12,
      },
      // Where an entry replaced the modeled rain, the model's amount as an outline over the bar
      {
        name: 'Modeled rain',
        type: 'bar',
        xAxisIndex: 1,
        yAxisIndex: 1,
        barGap: '-100%',
        z: 3,
        data: days.map((day) => (rainOverridden(day) ? round(depth(day.rain_model)) : null)),
        itemStyle: { color: 'transparent', borderColor: palette.rain, borderType: 'dashed', borderWidth: 1.5 },
        barMaxWidth: 12,
      },
    ],
  }
}

function tooltip(days: FieldDay[], params: unknown, units: Units): string {
  const list = (Array.isArray(params) ? params : [params]) as { dataIndex: number }[]
  const day = list.length ? days[list[0].dataIndex] : undefined
  if (!day) return ''
  const depth = (value: number | null) => units.format('depth', value)
  const source = (label: string) => `<span style="opacity:.7">${label}</span>`
  const rows = [
    ['AD', depth(day.ad)],
    ['Soil moisture', `${day.pct_moisture.toFixed(1)}%`],
    ['Adjusted ET', `${depth(day.adj_et)} ${source(ET_SOURCE_LABELS[day.et_source])}`],
    [
      'Rain',
      `${depth(day.rain)} ${source(SOURCE_LABELS[day.rain_source])}` +
        (rainOverridden(day) ? ` ${source(`model ${depth(day.rain_model)}`)}` : ''),
    ],
    ['Irrigation', `${depth(day.irrigation)} ${source(SOURCE_LABELS[day.irrigation_source])}`],
  ]
  if (day.soil_moisture_pct !== null) rows.push(['Moisture reading', `${day.soil_moisture_pct}%`])
  if (day.deep_drainage > 0) rows.push(['Deep drainage', depth(day.deep_drainage)])
  const body = rows.map(([name, value]) => `<tr><td style="padding-right:12px">${name}</td><td>${value}</td></tr>`)
  return `<strong>${formatDate(day.date, { weekday: true })}</strong><table>${body.join('')}</table>`
}
