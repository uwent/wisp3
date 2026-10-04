import type { WeatherPanelDay } from '@/types/serializers'

import { formatDate } from '../dates'
import type { Quantity, Units } from '../units'
import type { ChartView, EChartsCoreOption } from './echarts'
import { DEFAULT_WINDOW_DAYS } from './fieldChart'
import { baseOption, type Palette } from './palette'

// The weather panels on a field's page: small multiples, one measure each, sharing the date axis,
// with the forecast days shaded

type Series = {
  name: string
  color: (palette: Palette) => string
  value: (day: WeatherPanelDay) => number | null
  /** Drawn as a line on a bar chart (or unstacked bars beside a stack): snow on the precipitation chart */
  style?: 'line' | 'bar'
  /** Zero means none (snow): left off the chart when no day has any, and out of the tooltip on days without */
  sparse?: boolean
}

export type WeatherPanel = {
  key: string
  title: string
  /** Unit label for the y axis */
  unit: (units: Units) => string
  /** What the chart's measures are and why they matter, for the card's (i) tooltip */
  info: string
  series: Series[]
  /** Draw the series as daily bars, stacked (parts of a whole) or side by side, instead of lines */
  bars?: 'stack' | 'group'
  /** Running totals over the days in view, drawn in a second grid below the daily values */
  totals?: Series[]
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

/** Precipitation not reported as rain: the water in snow and sleet, and showers. All of it when rain is missing. */
function otherPrecip(day: WeatherPanelDay): number | null {
  if (day.precip_in === null) return null
  return Math.max(0, day.precip_in - (day.rain_in ?? 0))
}

/**
 * The panels for a field's page, or a pivot's (no field):
 * - field: its capacity and wilting point, as reference lines on the modeled soil moisture
 * - cropEt: the field's crop-adjusted ET by date (the balance's adjusted ET), which runs through
 *   today, not into the forecast; without it the ET chart shows reference ET only
 * - gddSince: what growing degree days count from ('emergence', or a date's label)
 */
export function weatherPanels(
  units: Units,
  {
    field,
    cropEt,
    gddSince = 'emergence',
  }: { field?: { fieldCapacity: number; wiltingPoint: number }; cropEt?: Record<string, number | null>; gddSince?: string } = {},
): WeatherPanel[] {
  const depthName = (label: string) =>
    units.system === 'metric' ? label.replace(/(\d+)/g, (n) => String(Math.round(Number(n) * 2.54))).replace('in', 'cm') : label
  const temp = (f: number) => units.format('temperature', f)
  const depth = (value: number | null) => converted(units, 'depth', value)
  return [
    {
      key: 'precipitation',
      title: 'Precipitation',
      unit: (u) => u.label('depth'),
      info:
        'Precipitation is all the water that fell: rain plus the water in snow, sleet and showers ("snow and other" ' +
        "is the part not reported as rain). The field's balance uses this unless you enter a rain gauge reading. " +
        'The lower panel adds it up from the first day in view, so zooming changes the total. When there is snow, ' +
        'the gray bars are snowfall (the depth of new snow) and the gray line is the snow on the ground, both ' +
        'measured as snow, not water: 10 inches of snow holds roughly an inch of water, less when it is light and dry.',
      bars: 'stack',
      series: [
        { name: 'Rain', color: (p) => p.rain, value: (day) => depth(day.rain_in === null ? null : Math.min(day.rain_in, day.precip_in ?? Infinity)) },
        { name: 'Snow and other', color: (p) => p.depths[0], value: (day) => depth(otherPrecip(day)) },
        { name: 'Snowfall', color: (p) => p.snow, value: (day) => depth(day.snowfall_in), style: 'bar', sparse: true },
        { name: 'Snow depth', color: (p) => p.snow, value: (day) => depth(day.snow_depth_in), style: 'line', sparse: true },
      ],
      totals: [{ name: 'Precipitation total', color: (p) => p.rain, value: (day) => depth(day.precip_in) }],
    },
    {
      key: 'et',
      title: 'Evapotranspiration',
      unit: (u) => u.label('depth'),
      info:
        'Reference ET is the water a well-watered grass would use, from the FAO-56 Penman–Monteith equation on the ' +
        "model's temperature, humidity, wind and sunshine. " +
        (cropEt
          ? "Crop ET is this field's estimate: reference ET adjusted for the crop's canopy, which is what the balance " +
            "takes out of the soil. It's lower than reference ET while the canopy is small, and runs through today only. " +
            'The lower panel adds both up from the first day in view.'
          : "Each field's crop ET (reference ET adjusted for its canopy) is on the field's page. The lower panel adds " +
            'reference ET up from the first day in view.'),
      bars: 'group',
      series: [
        { name: 'Reference ET', color: (p) => p.warm, value: (day) => depth(day.et0_in) },
        ...(cropEt ? [{ name: 'Crop ET', color: (p: Palette) => p.irrigation, value: (day: WeatherPanelDay) => depth(cropEt[day.date] ?? null) }] : []),
      ],
      totals: [
        { name: 'Reference ET total', color: (p) => p.warm, value: (day) => depth(day.et0_in) },
        ...(cropEt
          ? [{ name: 'Crop ET total', color: (p: Palette) => p.irrigation, value: (day: WeatherPanelDay) => depth(cropEt[day.date] ?? null) }]
          : []),
      ],
    },
    {
      key: 'soil_moisture',
      title: 'Modeled soil moisture',
      unit: () => '% by volume',
      info:
        "The weather model's own estimate of the water in the soil at four depths, as a percent of the soil's " +
        "volume (ECMWF IFS). It isn't a field's balance and doesn't know about irrigation" +
        (field
          ? "; the dashed lines are the field's capacity and wilting point for comparison, and the model's soil may hold water differently."
          : ', and its soil may hold water differently from your fields.'),
      series: DEPTHS.map(([key, label], i) => ({
        name: depthName(label),
        color: (p) => p.depths[i],
        value: (day) => {
          const value = day[`soil_moisture_${key}` as keyof WeatherPanelDay] as number | null
          return value === null ? null : value * 100
        },
      })),
      lines: field && [
        { name: 'Field capacity', value: field.fieldCapacity * 100 },
        { name: 'Wilting point', value: field.wiltingPoint * 100 },
      ],
    },
    {
      key: 'soil_temperature',
      title: 'Soil temperature',
      unit: (u) => u.label('temperature'),
      info:
        `Modeled soil temperature at four depths, averaged over the day. Around ${temp(50)} at seed depth is a ` +
        'common threshold for planting and germination. Deeper soil warms and cools slowly and evens out the swings of the air.',
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
      info:
        `The day's high and low air temperature, 2 m above the ground. Highs above about ${temp(86)} stress many ` +
        `crops and raise water use; lows near ${temp(32)} risk frost.`,
      series: [
        { name: 'High', color: (p) => p.warm, value: (day) => converted(units, 'temperature', day.tmax_f) },
        { name: 'Low', color: (p) => p.rain, value: (day) => converted(units, 'temperature', day.tmin_f) },
      ],
    },
    {
      key: 'gdd',
      title: `Growing degree days since ${gddSince}`,
      unit: (u) => u.label('degreeDays'),
      info:
        `Growing degree days add up the heat a crop can use. Each day counts the mean of its high and low, each held ` +
        `between ${temp(50)} and ${temp(86)}, minus ${temp(50)} (the 50/86 method used for corn and many other crops). ` +
        `Counted from ${gddSince}; crop stages are often predicted from this total.`,
      series: [{ name: 'GDD (50/86)', color: (p) => p.warm, value: (day) => converted(units, 'degreeDays', day.gdd_since_emergence) }],
    },
    {
      key: 'humidity',
      title: 'Relative humidity',
      unit: () => '%',
      info:
        'How close the air is to saturation, as the daily mean and the daily low (usually mid-afternoon). Dry ' +
        'afternoons raise crop water use; long humid spells favor leaf diseases such as late blight and white mold.',
      series: [
        { name: 'Daily mean', color: (p) => p.rain, value: (day) => day.rh_mean_pct },
        { name: 'Daily low', color: (p) => p.irrigation, value: (day) => day.rh_min_pct },
      ],
    },
    {
      key: 'vpd',
      title: 'Vapor pressure deficit (daily high)',
      unit: () => 'kPa',
      info:
        "How much more water vapor the air could hold: the air's drying power, and a driver of transpiration. About " +
        '0.4–1.5 kPa suits most crops. Above 1.5 kPa plants close their stomata to save water, which slows growth; ' +
        "below 0.4 kPa transpiration and nutrient uptake slow. This is the day's highest value, usually mid-afternoon.",
      series: [{ name: 'VPD', color: (p) => p.warm, value: (day) => day.vpd_max_kpa }],
      lines: [
        { name: '0.4 kPa', value: 0.4 },
        { name: '1.5 kPa', value: 1.5 },
      ],
    },
    {
      key: 'wind',
      title: 'Wind',
      unit: (u) => u.label('speed'),
      info:
        `Mean wind speed over the day and the highest gust, 10 m above the ground. Wind raises ET, blows sprinkler ` +
        `water off target, and makes application less even; many pesticide labels restrict spraying above ${units.format('speed', 10)}.`,
      series: [
        { name: 'Mean', color: (p) => p.rain, value: (day) => converted(units, 'speed', day.wind_speed_mph) },
        { name: 'Highest gust', color: (p) => p.ad, value: (day) => converted(units, 'speed', day.wind_gust_max_mph) },
      ],
    },
    {
      key: 'cloud',
      title: 'Cloud cover',
      unit: () => '%',
      info: 'The share of the sky covered by cloud, averaged over the day. Cloudy days cut sunlight, which lowers ET and slows growth.',
      series: [{ name: 'Cloud cover', color: (p) => p.inkMuted, value: (day) => day.cloud_cover_pct }],
    },
  ]
}

/** A day's value, with a sparse series' zero as none */
const valueOn = (series: Series, day: WeatherPanelDay) => {
  const value = series.value(day)
  return series.sparse && value === 0 ? null : value
}

/** The panel's series with something to show: sparse ones (snow) only when some day has some */
export const shownSeries = (panel: WeatherPanel, days: WeatherPanelDay[]) =>
  panel.series.filter((series) => !series.sparse || days.some((day) => (series.value(day) ?? 0) > 0))

/** The days in view when a chart opens: the last observed days, then the forecast (as the soil-water chart) */
export function defaultView(days: WeatherPanelDay[]): ChartView {
  const observed = days.filter((day) => !day.forecast).length
  return { start: Math.max(0, observed - DEFAULT_WINDOW_DAYS), end: days.length - 1 }
}

/** A running total of value over the days in view, null outside them and on days without a value */
export function runningTotal(days: WeatherPanelDay[], value: Series['value'], view: ChartView): (number | null)[] {
  let total = 0
  return days.map((day, i) => {
    if (i < view.start || i > view.end) return null
    const amount = value(day)
    if (amount === null) return null
    total += amount
    return Number(total.toFixed(2))
  })
}

export function weatherChartOption(
  panel: WeatherPanel,
  days: WeatherPanelDay[],
  units: Units,
  palette: Palette,
  view: ChartView = defaultView(days),
): EChartsCoreOption {
  const base = baseOption(palette)
  const dates = days.map((day) => day.date)
  const firstForecast = days.find((day) => day.forecast)?.date
  const startValue = dates[defaultView(days).start]
  const digits = (value: number | null) => (value === null ? null : Number(value.toFixed(2)))
  const unit = panel.unit(units)
  const series = shownSeries(panel, days)
  const totals = panel.totals ?? []
  const legendShown = series.length + totals.length > 1
  const top = legendShown ? 32 : 12
  const axisLabel = { ...base.axisLabel, formatter: (iso: string) => formatDate(iso) }

  const forecastArea = firstForecast
    ? {
        silent: true,
        itemStyle: { color: palette.inkMuted, opacity: 0.08 },
        label: { show: true, position: 'insideTop', color: palette.inkMuted, fontSize: 10, formatter: 'Forecast' },
        data: [[{ xAxis: firstForecast }, { xAxis: dates[dates.length - 1] }]],
      }
    : undefined

  // Light gray snow bars get an outline so they show on a light background
  const outline = (s: Series) => (palette.dark || s.style !== 'bar' ? {} : { borderColor: palette.inkMuted, borderWidth: 0.5 })
  const sparse = new Set(series.filter((s) => s.sparse).map((s) => s.name))
  const daily = series.map((s, i) => ({
    name: s.name,
    xAxisIndex: 0,
    yAxisIndex: 0,
    data: days.map((day) => digits(valueOn(s, day))),
    itemStyle: { color: s.color(palette), ...outline(s) },
    ...(panel.bars && s.style !== 'line'
      ? { type: 'bar', barMaxWidth: 10, ...(panel.bars === 'stack' && !s.style ? { stack: panel.key } : {}) }
      : // A sparse line's lone days (a dusting of snow) need a dot to show
        { type: 'line', symbol: s.sparse ? 'circle' : 'none', symbolSize: 3, lineStyle: { width: 2, color: s.color(palette) } }),
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
          markArea: forecastArea,
        }
      : {}),
  }))

  const running = totals.map((s, i) => ({
    name: s.name,
    type: 'line',
    xAxisIndex: 1,
    yAxisIndex: 1,
    data: runningTotal(days, s.value, view),
    symbol: 'none',
    lineStyle: { width: 2, color: s.color(palette), type: i === 0 ? 'solid' : 'dashed' },
    itemStyle: { color: s.color(palette) },
    ...(i === 0 ? { markArea: forecastArea } : {}),
  }))

  const grids = totals.length
    ? [
        { left: 40, right: 16, top, height: '42%' },
        { left: 40, right: 16, top: '70%', bottom: 24 },
      ]
    : [{ left: 40, right: 16, top, bottom: 24 }]

  return {
    animation: base.animation,
    textStyle: base.textStyle,
    legend: legendShown ? { type: 'scroll', top: 0, left: 0, right: 0, textStyle: { color: palette.ink, fontSize: 11 }, itemWidth: 14 } : undefined,
    tooltip: { ...base.tooltip, formatter: (params: unknown) => tooltip(params, unit, panel.bars || totals.length ? 2 : 1, sparse) },
    axisPointer: totals.length ? { link: [{ xAxisIndex: 'all' }] } : undefined,
    grid: grids,
    xAxis: totals.length
      ? [
          { type: 'category', data: dates, gridIndex: 0, axisLabel: { show: false }, axisLine: base.axisLine, axisTick: { show: false } },
          { type: 'category', data: dates, gridIndex: 1, axisLabel, axisLine: base.axisLine },
        ]
      : [{ type: 'category', data: dates, axisLabel, axisLine: base.axisLine }],
    yAxis: totals.length
      ? [
          { type: 'value', gridIndex: 0, min: 0, splitNumber: 3, axisLabel: base.axisLabel, splitLine: base.splitLine },
          {
            type: 'value',
            gridIndex: 1,
            min: 0,
            splitNumber: 2,
            name: 'Total in view',
            nameTextStyle: { color: palette.inkMuted, fontSize: 10, align: 'left' },
            nameGap: 6,
            axisLabel: base.axisLabel,
            splitLine: base.splitLine,
          },
        ]
      : [{ type: 'value', scale: !panel.bars, axisLabel: base.axisLabel, splitLine: base.splitLine }],
    dataZoom: [{ type: 'inside', xAxisIndex: totals.length ? [0, 1] : [0], startValue }],
    series: [...daily, ...running],
  }
}

type TooltipParam = { axisValue: string; seriesIndex: number; seriesName: string; marker: string; value: unknown }

/** The day, then each series in order (daily values before running totals); sparse series only on days they have a value */
function tooltip(params: unknown, unit: string, digits: number, sparse: Set<string>): string {
  const all = ((Array.isArray(params) ? params : [params]) as TooltipParam[]).toSorted((a, b) => a.seriesIndex - b.seriesIndex)
  if (!all.length) return ''
  const list = all.filter((param) => typeof param.value === 'number' || !sparse.has(param.seriesName))
  const rows = list.map((param) => {
    const value = typeof param.value === 'number' ? `${param.value.toFixed(digits)} ${unit}` : '—'
    return `<tr><td style="padding-right:12px">${param.marker}${param.seriesName}</td><td style="text-align:right"><strong>${value}</strong></td></tr>`
  })
  return `<strong>${formatDate(all[0].axisValue, { weekday: true })}</strong><table>${rows.join('')}</table>`
}
