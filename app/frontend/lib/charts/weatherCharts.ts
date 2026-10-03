import type { WeatherPanelDay } from '@/types/serializers'

import { formatDate } from '../dates'
import type { Quantity, Units } from '../units'
import type { EChartsCoreOption } from './echarts'
import { baseOption, type Palette } from './palette'

// The weather panels on a field's page: small multiples, one measure each, sharing the date axis,
// with the forecast days shaded

type Series = { name: string; color: (palette: Palette) => string; value: (day: WeatherPanelDay) => number | null }

export type WeatherPanel = {
  key: string
  title: string
  /** Unit label for the y axis */
  unit: (units: Units) => string
  series: Series[]
  /** Reference lines (e.g. the field's capacity and wilting point) */
  lines?: { name: string; value: number }[]
}

const DEPTHS = [
  ['0_7cm', '0–3 in'],
  ['7_28cm', '3–11 in'],
  ['28_100cm', '11–39 in'],
  ['100_255cm', '39–100 in'],
] as const

const converted = (units: Units, quantity: Quantity, value: number | null) => units.toDisplay(quantity, value)

export function weatherPanels(units: Units, field: { fieldCapacity: number; wiltingPoint: number }): WeatherPanel[] {
  const depthName = (label: string) =>
    units.system === 'metric' ? label.replace(/(\d+)/g, (n) => String(Math.round(Number(n) * 2.54))).replace('in', 'cm') : label
  return [
    {
      key: 'soil_moisture',
      title: 'Modeled soil moisture',
      unit: () => '% by volume',
      series: DEPTHS.map(([key, label], i) => ({
        name: depthName(label),
        color: (p) => p.depths[i],
        value: (day) => {
          const value = day[`soil_moisture_${key}` as keyof WeatherPanelDay] as number | null
          return value === null ? null : value * 100
        },
      })),
      lines: [
        { name: 'Field capacity', value: field.fieldCapacity * 100 },
        { name: 'Wilting point', value: field.wiltingPoint * 100 },
      ],
    },
    {
      key: 'soil_temperature',
      title: 'Soil temperature',
      unit: (u) => u.label('temperature'),
      series: DEPTHS.map(([key, label], i) => ({
        name: depthName(label),
        color: (p) => p.depths[i],
        value: (day) => converted(units, 'temperature', day[`soil_temp_${key}_f` as keyof WeatherPanelDay] as number | null),
      })),
    },
    {
      key: 'air_temperature',
      title: 'Air temperature',
      unit: (u) => u.label('temperature'),
      series: [
        { name: 'High', color: (p) => p.warm, value: (day) => converted(units, 'temperature', day.tmax_f) },
        { name: 'Low', color: (p) => p.rain, value: (day) => converted(units, 'temperature', day.tmin_f) },
      ],
    },
    {
      key: 'gdd',
      title: 'Growing degree days since emergence',
      unit: (u) => u.label('degreeDays'),
      series: [{ name: 'GDD (50/86)', color: (p) => p.warm, value: (day) => converted(units, 'degreeDays', day.gdd_since_emergence) }],
    },
    {
      key: 'humidity',
      title: 'Relative humidity',
      unit: () => '%',
      series: [
        { name: 'Daily mean', color: (p) => p.rain, value: (day) => day.rh_mean_pct },
        { name: 'Daily low', color: (p) => p.irrigation, value: (day) => day.rh_min_pct },
      ],
    },
    {
      key: 'vpd',
      title: 'Vapor pressure deficit (daily high)',
      unit: () => 'kPa',
      series: [{ name: 'VPD', color: (p) => p.warm, value: (day) => day.vpd_max_kpa }],
    },
    {
      key: 'wind',
      title: 'Wind',
      unit: (u) => u.label('speed'),
      series: [
        { name: 'Mean', color: (p) => p.rain, value: (day) => converted(units, 'speed', day.wind_speed_mph) },
        { name: 'Highest gust', color: (p) => p.ad, value: (day) => converted(units, 'speed', day.wind_gust_max_mph) },
      ],
    },
    {
      key: 'cloud',
      title: 'Cloud cover',
      unit: () => '%',
      series: [{ name: 'Cloud cover', color: (p) => p.inkMuted, value: (day) => day.cloud_cover_pct }],
    },
  ]
}

export function weatherChartOption(panel: WeatherPanel, days: WeatherPanelDay[], units: Units, palette: Palette): EChartsCoreOption {
  const base = baseOption(palette)
  const dates = days.map((day) => day.date)
  const firstForecast = days.find((day) => day.forecast)?.date
  const digits = (value: number | null) => (value === null ? null : Number(value.toFixed(2)))
  const unit = panel.unit(units)

  return {
    animation: base.animation,
    textStyle: base.textStyle,
    legend: panel.series.length > 1 ? { type: 'scroll', top: 0, left: 0, right: 0, textStyle: { color: palette.ink, fontSize: 11 }, itemWidth: 14 } : undefined,
    tooltip: {
      ...base.tooltip,
      valueFormatter: (value: unknown) => (typeof value === 'number' ? `${value.toFixed(1)} ${unit}` : '—'),
    },
    grid: { left: 40, right: 16, top: panel.series.length > 1 ? 32 : 12, bottom: 24 },
    xAxis: { type: 'category', data: dates, axisLabel: { ...base.axisLabel, formatter: (iso: string) => formatDate(iso) }, axisLine: base.axisLine },
    yAxis: { type: 'value', scale: true, axisLabel: base.axisLabel, splitLine: base.splitLine },
    series: panel.series.map((series, i) => ({
      name: series.name,
      type: 'line',
      data: days.map((day) => digits(series.value(day))),
      symbol: 'none',
      lineStyle: { width: 2, color: series.color(palette) },
      itemStyle: { color: series.color(palette) },
      ...(i === 0
        ? {
            markLine: panel.lines?.length
              ? {
                  silent: true,
                  symbol: 'none',
                  data: panel.lines.map((line) => ({
                    yAxis: Number(line.value.toFixed(2)),
                    lineStyle: { color: palette.inkMuted, type: 'dashed', width: 1 },
                    label: { formatter: line.name, position: 'insideEndTop', color: palette.inkMuted, fontSize: 10 },
                  })),
                }
              : undefined,
            markArea: firstForecast
              ? {
                  silent: true,
                  itemStyle: { color: palette.inkMuted, opacity: 0.08 },
                  label: { show: true, position: 'insideTop', color: palette.inkMuted, fontSize: 10, formatter: 'Forecast' },
                  data: [[{ xAxis: firstForecast }, { xAxis: dates[dates.length - 1] }]],
                }
              : undefined,
          }
        : {}),
    })),
  }
}
