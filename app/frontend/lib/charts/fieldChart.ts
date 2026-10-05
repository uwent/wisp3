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
  /** The projection's days after today (planned irrigation is their entered irrigation) */
  forecastDays?: FieldDay[]
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
  const { days, forecastDays = [], summary, rootZoneDepth, units, mode, palette } = input
  const base = baseOption(palette)
  const all = [...days, ...forecastDays]
  const dates = all.map((day) => day.date)
  const observed = days.length
  const depth = (inches: number | null) => units.toDisplay('depth', inches)
  const round = (value: number | null, digits = 3) => (value === null ? null : Number(value.toFixed(digits)))
  // AD in the chart's units
  const level = (ad: number | null) =>
    ad === null ? null : round(mode === 'ad' ? depth(ad) : summary.pct_at_ad_zero + (ad / rootZoneDepth) * 100)
  const lines = thresholds(input)
  const zeroLine = lines.find((line) => line.name.startsWith('Irrigate'))!.value
  const wiltingLine = lines[lines.length - 1].value
  const forecastOnly = <T>(value: (day: FieldDay, i: number) => T) => all.map((day, i) => (i < observed ? null : value(day, i)))

  const balance = all.map((day, i) =>
    i < observed
      ? {
          value: level(day.ad),
          // A soil moisture reading reset the balance on this day
          ...(day.moisture_source ? { symbol: 'circle', symbolSize: 8 } : {}),
        }
      : null,
  )

  // The projection continues from today's AD; the ensemble's range opens from it
  const today = days.at(-1)
  const bands = new Map(summary.projection?.map((day) => [day.date, day]) ?? [])
  const hasBand = forecastDays.some((day) => bands.get(day.date)?.p10 != null)
  const atToday = (value: (day: FieldDay) => number | null) => all.map((day, i) => (i === observed - 1 ? level(day.ad) : i < observed ? null : value(day)))
  const projection = atToday((day) => level(day.ad))
  const bandLow = atToday((day) => level(bands.get(day.date)?.p10 ?? null))
  const bandHigh = atToday((day) => level(bands.get(day.date)?.p90 ?? null))
  const bandWidth = bandHigh.map((high, i) => (high === null || bandLow[i] === null ? null : round(high - bandLow[i]!)))
  const planned = forecastDays.some((day) => (day.irrigation ?? 0) > 0)

  const forecastArea = forecastDays.length
    ? {
        silent: true,
        itemStyle: { color: palette.inkMuted, opacity: 0.08 },
        label: { show: true, position: 'insideTop', color: palette.inkMuted, fontSize: 10, formatter: 'Forecast' },
        data: [[{ xAxis: forecastDays[0].date }, { xAxis: dates.at(-1) }]],
      }
    : undefined

  const axisLabel = { ...base.axisLabel, formatter: (iso: string) => formatDate(iso) }
  const yName = mode === 'ad' ? `AD (${units.label('depth')})` : 'Soil moisture (%)'
  const balanceName = mode === 'ad' ? 'Allowable depletion' : 'Soil moisture'

  return {
    animation: base.animation,
    textStyle: base.textStyle,
    legend: {
      type: 'scroll',
      top: 0,
      left: 0,
      right: 0,
      textStyle: { color: palette.ink, fontSize: 12 },
      data: [
        balanceName,
        ...(forecastDays.length ? ['Forecast'] : []),
        ...(hasBand ? [RANGE] : []),
        'Rain',
        'Modeled rain',
        'Irrigation',
        ...(planned ? ['Planned irrigation'] : []),
      ],
    },
    tooltip: { ...base.tooltip, formatter: (params: unknown) => tooltip(all, observed, summary, params, units) },
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
      { type: 'inside', xAxisIndex: [0, 1], startValue: dates[Math.max(0, observed - DEFAULT_WINDOW_DAYS)] },
      {
        type: 'slider',
        xAxisIndex: [0, 1],
        bottom: 8,
        height: 20,
        startValue: dates[Math.max(0, observed - DEFAULT_WINDOW_DAYS)],
        borderColor: palette.line,
        textStyle: { color: palette.inkMuted },
        labelFormatter: (_: number, iso: string) => formatDate(iso),
      },
    ],
    series: [
      // Not drawn: the slider outlines the first series, so this one carries AD through the forecast
      {
        name: SLIDER,
        type: 'line',
        xAxisIndex: 0,
        yAxisIndex: 0,
        data: all.map((day) => level(day.ad)),
        symbol: 'none',
        lineStyle: { opacity: 0 },
        tooltip: { show: false },
        silent: true,
      },
      {
        name: balanceName,
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
      // The ensemble's 10th–90th percentile range: an invisible base at the 10th, then the width
      ...(hasBand
        ? [
            {
              name: 'Range low',
              type: 'line',
              xAxisIndex: 0,
              yAxisIndex: 0,
              stack: 'range',
              stackStrategy: 'all',
              data: bandLow,
              symbol: 'none',
              lineStyle: { opacity: 0 },
              tooltip: { show: false },
              silent: true,
            },
            {
              name: RANGE,
              type: 'line',
              xAxisIndex: 0,
              yAxisIndex: 0,
              stack: 'range',
              stackStrategy: 'all',
              data: bandWidth,
              symbol: 'none',
              lineStyle: { opacity: 0 },
              itemStyle: { color: palette.ad },
              areaStyle: { color: palette.ad, opacity: 0.15 },
              silent: true,
            },
          ]
        : []),
      ...(forecastDays.length
        ? [
            {
              name: 'Forecast',
              type: 'line',
              xAxisIndex: 0,
              yAxisIndex: 0,
              data: projection,
              symbol: 'none',
              lineStyle: { width: 2, color: palette.ad, type: 'dashed' },
              itemStyle: { color: palette.ad },
              markArea: forecastArea,
              markLine: {
                silent: true,
                symbol: 'none',
                data: [{ xAxis: today!.date }],
                lineStyle: { color: palette.inkMuted, type: 'solid', width: 1 },
                label: { formatter: 'Today', position: 'insideEndTop', color: palette.inkMuted, fontSize: 10 },
              },
            },
          ]
        : []),
      {
        name: 'Rain',
        type: 'bar',
        stack: 'water',
        xAxisIndex: 1,
        yAxisIndex: 1,
        // Forecast rain is lighter
        data: all.map((day, i) => (i < observed ? round(depth(day.rain)) : { value: round(depth(day.rain)), itemStyle: { opacity: 0.4 } })),
        itemStyle: { color: palette.rain },
        barMaxWidth: 12,
        markArea: forecastArea && { ...forecastArea, label: { show: false } },
      },
      {
        name: 'Irrigation',
        type: 'bar',
        stack: 'water',
        xAxisIndex: 1,
        yAxisIndex: 1,
        data: all.map((day, i) => (i < observed ? round(depth(day.irrigation)) : null)),
        itemStyle: { color: palette.irrigation, borderRadius: [2, 2, 0, 0] },
        barMaxWidth: 12,
      },
      // Irrigation entered on future dates: outlined and hatched
      ...(planned
        ? [
            {
              name: 'Planned irrigation',
              type: 'bar',
              stack: 'water',
              xAxisIndex: 1,
              yAxisIndex: 1,
              data: forecastOnly((day) => round(depth(day.irrigation))),
              itemStyle: {
                color: palette.irrigation,
                opacity: 0.6,
                borderColor: palette.irrigation,
                borderWidth: 1.5,
                borderRadius: [2, 2, 0, 0],
                decal: { symbol: 'rect', symbolSize: 1, dashArrayX: [1, 0], dashArrayY: [2, 3], rotation: -Math.PI / 4, color: palette.surface },
              },
              barMaxWidth: 12,
            },
          ]
        : []),
      // Where an entry replaced the modeled rain, the model's amount as an outline over the bar
      {
        name: 'Modeled rain',
        type: 'bar',
        xAxisIndex: 1,
        yAxisIndex: 1,
        barGap: '-100%',
        z: 3,
        data: all.map((day) => (rainOverridden(day) ? round(depth(day.rain_model)) : null)),
        itemStyle: { color: 'transparent', borderColor: palette.rain, borderType: 'dashed', borderWidth: 1.5 },
        barMaxWidth: 12,
      },
    ],
  }
}

const RANGE = 'Forecast range (10–90%)'
const SLIDER = 'Slider outline'

function tooltip(days: FieldDay[], observed: number, summary: PlantingSummary, params: unknown, units: Units): string {
  const list = (Array.isArray(params) ? params : [params]) as { dataIndex: number }[]
  const index = list.length ? list[0].dataIndex : -1
  const day = days[index]
  if (!day) return ''
  const depth = (value: number | null) => units.format('depth', value)
  const source = (label: string) => `<span style="opacity:.7">${label}</span>`
  const forecast = index >= observed
  const band = forecast ? summary.projection?.find((p) => p.date === day.date) : undefined
  const rows = [
    [forecast ? 'Projected AD' : 'AD', depth(day.ad)],
    ...(band?.p10 != null && band.p90 != null ? [['Range (10–90%)', `${depth(band.p10)} to ${depth(band.p90)}`]] : []),
    ...(band?.chance != null
      ? [[summary.target_in === null ? 'Chance at 0 AD by now' : 'Chance below target by now', `${Math.round(band.chance * 100)}%`]]
      : []),
    ['Soil moisture', `${day.pct_moisture.toFixed(1)}%`],
    ['Adjusted ET', `${depth(day.adj_et)} ${source(ET_SOURCE_LABELS[day.et_source])}`],
    [
      'Rain',
      `${depth(day.rain)} ${source(SOURCE_LABELS[day.rain_source])}` +
        (rainOverridden(day) ? ` ${source(`model ${depth(day.rain_model)}`)}` : ''),
    ],
    ['Irrigation', `${depth(day.irrigation)} ${source(forecast && day.irrigation_source === 'entered' ? 'planned' : SOURCE_LABELS[day.irrigation_source])}`],
  ]
  if (day.soil_moisture_pct !== null) rows.push(['Moisture reading', `${day.soil_moisture_pct}%`])
  if (day.deep_drainage > 0) rows.push(['Deep drainage', depth(day.deep_drainage)])
  const body = rows.map(([name, value]) => `<tr><td style="padding-right:12px">${name}</td><td>${value}</td></tr>`)
  const heading = `${formatDate(day.date, { weekday: true })}${forecast ? ' · forecast' : ''}`
  return `<strong>${heading}</strong><table>${body.join('')}</table>`
}
