import { formatDate } from '../dates'
import type { EChartsCoreOption } from './echarts'
import { baseOption, type Palette } from './palette'

// The admin Usage page's charts (UsageReport): accounts active each week of the
// season, with last season's line for comparison, and the entries made each week by kind

export type EntryKind = 'rain' | 'irrigation' | 'soil_moisture' | 'canopy'

// Rain and irrigation in their usual colors; soil moisture apart from rain (never beside it in the
// stack or legend), as their blues would be hard to tell apart in dark mode
export const ENTRY_KINDS: { key: EntryKind; name: string; color: (palette: Palette) => string }[] = [
  { key: 'rain', name: 'Rain', color: (p) => p.rain },
  { key: 'irrigation', name: 'Irrigation', color: (p) => p.irrigation },
  { key: 'canopy', name: 'Canopy', color: (p) => p.canopy },
  { key: 'soil_moisture', name: 'Soil moisture', color: (p) => p.ad },
]

/** Each week's label on the axis: its Monday */
export const weekLabels = (weeks: string[]) => weeks.map((week) => formatDate(week))

function axes(palette: Palette, weeks: string[]) {
  const base = baseOption(palette)
  return {
    base,
    xAxis: {
      type: 'category',
      data: weekLabels(weeks),
      axisLabel: base.axisLabel,
      axisLine: base.axisLine,
      axisTick: { show: false },
    },
    yAxis: {
      type: 'value',
      minInterval: 1,
      axisLabel: base.axisLabel,
      splitLine: base.splitLine,
    },
  }
}

const tooltipTitle = (weeks: string[], index: number) => `Week of ${formatDate(weeks[index], { year: true })}`

type AxisParam = { dataIndex: number; seriesName: string; value: number | null; marker: string }

function tooltip(weeks: string[]) {
  return (params: AxisParam | AxisParam[]) => {
    const list = Array.isArray(params) ? params : [params]
    if (!list.length) return ''
    const rows = list
      .filter((p) => p.value !== null)
      .map((p) => `${p.marker}${p.seriesName}: <b>${p.value}</b>`)
      .join('<br>')
    return `${tooltipTitle(weeks, list[0].dataIndex)}<br>${rows}`
  }
}

/** Accounts active each week, as bars; last season (when there is one) as a line on the same axis */
export function weeklyActiveOption(
  palette: Palette,
  weeks: string[],
  active: number[],
  previous: number[] | null,
  year: number,
): EChartsCoreOption {
  const { base, xAxis, yAxis } = axes(palette, weeks)
  const series: object[] = [
    {
      name: String(year),
      type: 'bar',
      data: active,
      barMaxWidth: 14,
      itemStyle: { color: palette.ad, borderRadius: [4, 4, 0, 0] },
    },
  ]
  if (previous) {
    series.push({
      name: String(year - 1),
      type: 'line',
      data: previous,
      symbol: 'none',
      lineStyle: { color: palette.inkMuted, width: 2, type: 'dashed' },
      itemStyle: { color: palette.inkMuted },
    })
  }
  return {
    ...base,
    grid: { left: 36, right: 12, top: previous ? 32 : 12, bottom: 28 },
    legend: previous
      ? {
          top: 0,
          data: series.map((s) => (s as { name: string }).name),
          textStyle: { color: palette.ink, fontSize: 12 },
        }
      : undefined,
    tooltip: { ...base.tooltip, formatter: tooltip(weeks) },
    xAxis,
    yAxis,
    series,
  }
}

/** Entries made each week, stacked by kind */
export function weeklyEntriesOption(
  palette: Palette,
  weeks: string[],
  entries: Record<EntryKind, number[]>,
): EChartsCoreOption {
  const { base, xAxis, yAxis } = axes(palette, weeks)
  return {
    ...base,
    grid: { left: 44, right: 12, top: 32, bottom: 28 },
    legend: {
      type: 'scroll',
      top: 0,
      data: ENTRY_KINDS.map((kind) => kind.name),
      textStyle: { color: palette.ink, fontSize: 12 },
    },
    tooltip: { ...base.tooltip, axisPointer: { type: 'shadow' }, formatter: tooltip(weeks) },
    xAxis,
    yAxis,
    series: ENTRY_KINDS.map((kind, index) => ({
      name: kind.name,
      type: 'bar',
      stack: 'entries',
      data: entries[kind.key],
      barMaxWidth: 14,
      // A surface-colored edge between stacked segments; the top one rounded
      itemStyle: {
        color: kind.color(palette),
        borderColor: palette.surface,
        borderWidth: 1,
        borderRadius: index === ENTRY_KINDS.length - 1 ? [4, 4, 0, 0] : 0,
      },
    })),
  }
}

/** Each step's share of the step before it (the first is 100%), or null after an empty step */
export function funnelShares(counts: number[]): (number | null)[] {
  return counts.map((count, i) => {
    if (i === 0) return counts[0] ? 1 : null
    return counts[i - 1] ? count / counts[i - 1] : null
  })
}

/** A share as a whole percent, or a dash */
export const percent = (share: number | null) => (share === null ? '—' : `${Math.round(share * 100)}%`)
