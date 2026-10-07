import type { FieldDay, PlantingSummary } from '@/types/serializers'

import { formatDate } from '../dates'
import { ET_SOURCE_LABELS, rainOverridden, SOURCE_LABELS } from '../provenance'
import type { Units } from '../units'
import type { ChartView, EChartsCoreOption } from './echarts'
import { baseOption, type Palette } from './palette'
import { forecastShading } from './shading'
import { runningTotal } from './totals'

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
  /** What the canopy is measured in: 'cover' (percent) or 'lai' */
  canopy?: 'cover' | 'lai'
  /** The days in view (indexes into days then forecastDays), for the running totals; default the opening view */
  view?: ChartView
}

/** The modeled rain the balance didn't use: replaced by an entry, or left out on a field using only entered rain */
const modelUnused = (day: FieldDay) =>
  rainOverridden(day) || (day.rain_source === 'none' && day.rain_model !== null && day.rain_model > 0)

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
  const { days, forecastDays = [], summary, rootZoneDepth, units, mode, palette, canopy = 'cover' } = input
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
  // A field using only entered rain: the projection with no rain as well (Q7)
  const hasDry = forecastDays.some((day) => bands.get(day.date)?.dry_ad != null)
  const dry = atToday((day) => level(bands.get(day.date)?.dry_ad ?? null))
  const planned = forecastDays.some((day) => (day.irrigation ?? 0) > 0)

  // Deep drainage: AD stops at field capacity and the water above it drains that day, so it's drawn
  // as an area stacked on the field capacity line, as high as the day's drainage
  const drains = all.some((day) => day.deep_drainage > 0)
  const drainage = all.map((day) => round(mode === 'ad' ? depth(day.deep_drainage) : (day.deep_drainage / rootZoneDepth) * 100))

  // Running totals over the days in view, through the forecast (as the precipitation chart)
  const openingStart = Math.max(0, observed - DEFAULT_WINDOW_DAYS)
  const view = input.view ?? { start: openingStart, end: all.length - 1 }
  const anyUnused = all.some(modelUnused)
  const totals = [
    { id: 'total-rain', group: RAIN, label: 'Rain total', color: palette.rain, type: 'solid', data: runningTotal(all, (day) => depth(day.rain), view) },
    ...(anyUnused
      ? [
          {
            id: 'total-modeled',
            group: RAIN,
            label: 'Modeled rain total',
            color: palette.rain,
            type: 'dashed',
            data: runningTotal(all, (day) => depth(day.rain_model), view),
          },
        ]
      : []),
    {
      id: 'total-irrigation',
      group: IRRIGATION,
      label: 'Irrigation total',
      color: palette.irrigation,
      type: 'solid',
      data: runningTotal(all, (day) => depth(day.irrigation), view),
    },
  ]

  // The canopy as modeled each day (interpolated between readings), and the readings themselves
  const canopyName = canopy === 'lai' ? 'LAI' : 'Canopy cover'

  // The forecast's days shaded edge to edge on every panel, and named once at the top
  const shading = forecastShading({ dates, from: forecastDays.length ? observed : -1, grids: 4, axisOffset: 4, palette })
  const forecastLabel = forecastDays.length
    ? [
        { xAxis: forecastDays[0].date, itemStyle: { opacity: 0 }, label: { show: true, position: 'insideTop', color: palette.inkMuted, fontSize: 10, formatter: 'Forecast' } },
        { xAxis: dates.at(-1) },
      ]
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
      // One entry per measure: series sharing a name show and hide together (the balance with its
      // forecast and range; rain with the modeled rain and the totals; irrigation with planned and its
      // total; the canopy with its readings). The thresholds, today and the forecast shading are on
      // series outside the legend, so they always stay.
      data: [balanceName, ...(hasDry ? [DRY] : []), ...(drains ? [DRAINAGE] : []), RAIN, IRRIGATION, canopyName],
    },
    tooltip: {
      ...base.tooltip,
      formatter: (params: unknown) => tooltip(all, observed, summary, params, units, { canopy, totals }),
    },
    axisPointer: { link: [{ xAxisIndex: 'all' }] },
    // Small multiples sharing the date axis: the balance, water in, its running totals, and the canopy
    grid: [
      { left: 48, right: 112, top: 56, height: '36%' },
      { left: 48, right: 112, top: '49%', height: '11%' },
      { left: 48, right: 112, top: '66%', height: '9%' },
      { left: 48, right: 112, top: '81%', bottom: 56 },
    ],
    xAxis: [
      ...[0, 1, 2, 3].map((gridIndex) =>
        gridIndex === 3
          ? { type: 'category', data: dates, gridIndex, axisLabel, axisLine: base.axisLine }
          : { type: 'category', data: dates, gridIndex, axisLabel: { show: false }, axisLine: base.axisLine, axisTick: { show: false } },
      ),
      ...shading.xAxis,
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
        // Field capacity at the top, unless deep drainage stacked on it reaches higher
        max: (extent: { max: number }) => (extent.max > lines[0].value + 1e-9 ? roundUp(extent.max) : lines[0].value),
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
      {
        type: 'value',
        gridIndex: 2,
        name: `Total in view (${units.label('depth')})`,
        nameTextStyle: { color: palette.inkMuted, align: 'left' },
        axisLabel: base.axisLabel,
        splitLine: base.splitLine,
        splitNumber: 2,
        min: 0,
      },
      {
        type: 'value',
        gridIndex: 3,
        name: canopy === 'lai' ? 'LAI' : 'Canopy cover (%)',
        nameTextStyle: { color: palette.inkMuted, align: 'left' },
        axisLabel: base.axisLabel,
        splitLine: base.splitLine,
        splitNumber: 2,
        min: 0,
        ...(canopy === 'lai' ? {} : { max: 100 }),
      },
      ...shading.yAxis,
    ],
    dataZoom: [
      { type: 'inside', xAxisIndex: [0, 1, 2, 3, ...shading.xAxisIndexes], startValue: dates[openingStart] },
      {
        type: 'slider',
        xAxisIndex: [0, 1, 2, 3, ...shading.xAxisIndexes],
        bottom: 8,
        height: 20,
        startValue: dates[openingStart],
        borderColor: palette.line,
        textStyle: { color: palette.inkMuted },
        labelFormatter: (_: number, iso: string) => formatDate(iso),
      },
    ],
    series: [
      // Not drawn and not in the legend: the slider outlines the first series, so this one carries AD
      // through the forecast. It also carries what always stays on the chart: the thresholds, the
      // zone below the trigger point, today, and the forecast shading.
      {
        id: 'slider',
        name: SLIDER,
        type: 'line',
        xAxisIndex: 0,
        yAxisIndex: 0,
        data: all.map((day) => level(day.ad)),
        symbol: 'none',
        lineStyle: { opacity: 0 },
        tooltip: { show: false },
        silent: true,
        markLine: {
          silent: true,
          symbol: 'none',
          data: [
            ...lines.map((line) => ({
              yAxis: line.value,
              name: line.name,
              lineStyle: { color: line.color, type: line.dashed ? 'dashed' : 'solid', width: 1 },
              label: { formatter: line.name, position: 'end', color: palette.inkMuted, fontSize: 11 },
            })),
            ...(forecastDays.length
              ? [
                  {
                    xAxis: today!.date,
                    lineStyle: { color: palette.inkMuted, type: 'solid', width: 1 },
                    label: { formatter: 'Today', position: 'insideEndTop', color: palette.inkMuted, fontSize: 10 },
                  },
                ]
              : []),
          ],
        },
        // Below the trigger point, shaded faintly in the irrigate color, and the forecast's label
        markArea: {
          silent: true,
          data: [
            [{ yAxis: zeroLine, itemStyle: { color: palette.status.irrigate, opacity: 0.07 } }, { yAxis: wiltingLine }],
            ...(forecastLabel ? [forecastLabel] : []),
          ],
        },
      },
      ...shading.series,
      // An invisible base at field capacity, then the day's drainage above it
      ...(drains
        ? [
            {
              // Outside the legend, so the legend's swatch is the drainage's own
              id: 'drainage-base',
              name: DRAINAGE_BASE,
              type: 'line',
              xAxisIndex: 0,
              yAxisIndex: 0,
              stack: 'drainage',
              data: all.map(() => lines[0].value),
              symbol: 'none',
              lineStyle: { opacity: 0 },
              tooltip: { show: false },
              silent: true,
            },
            {
              id: 'drainage',
              name: DRAINAGE,
              type: 'line',
              xAxisIndex: 0,
              yAxisIndex: 0,
              stack: 'drainage',
              data: drainage,
              symbol: 'none',
              lineStyle: { width: 1, color: palette.ad, opacity: 0.6 },
              itemStyle: { color: palette.ad },
              areaStyle: { color: palette.ad, opacity: 0.3 },
              silent: true,
            },
          ]
        : []),
      {
        id: 'balance',
        name: balanceName,
        type: 'line',
        xAxisIndex: 0,
        yAxisIndex: 0,
        data: balance,
        symbol: 'none',
        showSymbol: true,
        lineStyle: { width: 2, color: palette.ad },
        itemStyle: { color: palette.ad, borderColor: palette.surface, borderWidth: 2 },
      },
      // The ensemble's 10th–90th percentile range: an invisible base at the 10th, then the width
      ...(hasBand
        ? [
            {
              id: 'range-low',
              name: balanceName,
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
              id: 'range',
              name: balanceName,
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
              id: 'forecast',
              name: balanceName,
              type: 'line',
              xAxisIndex: 0,
              yAxisIndex: 0,
              data: projection,
              symbol: 'none',
              lineStyle: { width: 2, color: palette.ad, type: 'dashed' },
              itemStyle: { color: palette.ad },
            },
          ]
        : []),
      ...(hasDry
        ? [
            {
              id: 'dry',
              name: DRY,
              type: 'line',
              xAxisIndex: 0,
              yAxisIndex: 0,
              data: dry,
              symbol: 'none',
              lineStyle: { width: 1.5, color: palette.ad, type: 'dotted' },
              itemStyle: { color: palette.ad },
            },
          ]
        : []),
      {
        id: 'rain',
        name: RAIN,
        type: 'bar',
        stack: 'water',
        xAxisIndex: 1,
        yAxisIndex: 1,
        // Forecast rain is lighter
        data: all.map((day, i) => (i < observed ? round(depth(day.rain)) : { value: round(depth(day.rain)), itemStyle: { opacity: 0.4 } })),
        itemStyle: { color: palette.rain },
        barMaxWidth: 12,
      },
      {
        id: 'irrigation',
        name: IRRIGATION,
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
              id: 'planned',
              name: IRRIGATION,
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
      // Modeled rain the balance didn't use, as an outline beside the bar (as the precipitation chart)
      {
        id: 'modeled-rain',
        name: RAIN,
        type: 'bar',
        xAxisIndex: 1,
        yAxisIndex: 1,
        barGap: '10%',
        data: all.map((day) => (modelUnused(day) ? round(depth(day.rain_model)) : null)),
        itemStyle: { color: 'transparent', borderColor: palette.rain, borderType: 'dashed', borderWidth: 1.5 },
        barMaxWidth: 12,
      },
      ...totals.map((total) => ({
        id: total.id,
        name: total.group,
        type: 'line',
        xAxisIndex: 2,
        yAxisIndex: 2,
        data: total.data,
        symbol: 'none',
        lineStyle: { width: 2, color: total.color, type: total.type },
        itemStyle: { color: total.color },
      })),
      {
        id: 'canopy',
        name: canopyName,
        type: 'line',
        xAxisIndex: 3,
        yAxisIndex: 3,
        data: all.map((day) => round(day.canopy, 2)),
        symbol: 'none',
        lineStyle: { width: 2, color: palette.canopy },
        itemStyle: { color: palette.canopy },
      },
      {
        // Markers only (a line with no line, as scatter isn't bundled)
        id: 'canopy-readings',
        name: canopyName,
        type: 'line',
        xAxisIndex: 3,
        yAxisIndex: 3,
        data: all.map((day) => day.canopy_entered),
        symbol: 'circle',
        symbolSize: 8,
        showSymbol: true,
        // Every reading, even where ECharts would thin the markers on a crowded axis
        showAllSymbol: true,
        lineStyle: { width: 0 },
        itemStyle: { color: palette.canopy, borderColor: palette.surface, borderWidth: 2 },
        z: 3,
      },
    ],
  }
}

const RAIN = 'Rain'
const IRRIGATION = 'Irrigation'
const DRY = 'If no rain falls'
const DRAINAGE = 'Deep drainage'
const DRAINAGE_BASE = 'Deep drainage base'

/** A round number at or above value for an axis' top, in steps of half its order of magnitude: 1.76 → 2, 12.3 → 15, 45 → 45 */
export function roundUp(value: number): number {
  if (value <= 0) return value
  const step = 10 ** Math.floor(Math.log10(value)) / 2
  return Number((Math.ceil(value / step) * step).toFixed(6))
}
const SLIDER = 'Slider outline'

function tooltip(
  days: FieldDay[],
  observed: number,
  summary: PlantingSummary,
  params: unknown,
  units: Units,
  { canopy, totals }: { canopy: 'cover' | 'lai'; totals: { label: string; data: (number | null)[] }[] },
): string {
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
    ...(band?.dry_ad != null ? [['If no rain falls', depth(band.dry_ad)]] : []),
    ...(band?.p10 != null && band.p90 != null ? [['Range (10–90%)', `${depth(band.p10)} to ${depth(band.p90)}`]] : []),
    ...(band?.chance != null
      ? [[summary.target_in === null ? 'Chance at 0 AD by now' : 'Chance below target by now', `${Math.round(band.chance * 100)}%`]]
      : []),
    ['Soil moisture', `${day.pct_moisture.toFixed(1)}%`],
    ['Adjusted ET', `${depth(day.adj_et)} ${source(ET_SOURCE_LABELS[day.et_source])}`],
    [
      'Rain',
      `${depth(day.rain)} ${source(SOURCE_LABELS[day.rain_source])}` +
        (modelUnused(day) ? ` ${source(`model ${depth(day.rain_model)}`)}` : ''),
    ],
    ['Irrigation', `${depth(day.irrigation)} ${source(forecast && day.irrigation_source === 'entered' ? 'planned' : SOURCE_LABELS[day.irrigation_source])}`],
    ['Deep drainage', depth(day.deep_drainage)],
    // Running totals are already in display units
    ...totals.flatMap((total) => {
      const value = total.data[index]
      return value === null ? [] : [[`${total.label} in view`, `${value.toFixed(2)} ${units.label('depth')}`]]
    }),
    [
      canopy === 'lai' ? 'LAI' : 'Canopy cover',
      (canopy === 'lai' ? day.canopy.toFixed(2) : `${day.canopy.toFixed(0)}%`) + ` ${source(day.canopy_entered === null ? 'estimated' : 'reading')}`,
    ],
  ]
  if (day.soil_moisture_pct !== null) rows.push(['Moisture reading', `${day.soil_moisture_pct}%`])
  const body = rows.map(([name, value]) => `<tr><td style="padding-right:12px">${name}</td><td>${value}</td></tr>`)
  const heading = `${formatDate(day.date, { weekday: true })}${forecast ? ' · forecast' : ''}`
  return `<strong>${heading}</strong><table>${body.join('')}</table>`
}
