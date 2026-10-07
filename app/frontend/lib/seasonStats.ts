import type { FieldDay } from '@/types/serializers'

import { daysBetween } from './dates'

// A field's season in numbers, for the season details on its page (PLAN.md Phase 6.6): the rain
// entered and modeled, how the gauge compares with the model day by day, irrigation and deep
// drainage. From the balance's days through today; depths in inches.

/** The least rain counted as a rain day: measurable precipitation, so modeled drizzle doesn't count */
export const RAIN_DAY = 0.01
/** Gauge and model disagree on a day both had rain when they differ by more than this, or by more than DISAGREE_SHARE of the model's */
export const DISAGREE_IN = 0.1
export const DISAGREE_SHARE = 0.25

type Total = { days: number; inches: number }

export type SeasonStats = {
  days: number
  /** Rain readings (the field's or its group's): every reading, and those with rain */
  entered: { readings: number; rainDays: number; inches: number }
  modeled: Total
  /** Modeled rain the balance left out: days without a reading on a field using only entered rain */
  leftOut: Total
  /** Each day the model had a value, by what the gauge said */
  comparison: {
    /** Both had rain */
    both: Total & {
      /** Days the two differ by more than the larger of DISAGREE_IN and DISAGREE_SHARE of the model's */
      disagree: number
      /** Median of entered − modeled, or null without such days */
      typicalAdjustment: number | null
      /** Entered ÷ modeled, summed over these days, or null without modeled rain */
      ratio: number | null
    }
    /** Rain entered where the model had none */
    missed: Total
    /** A dry reading (0) where the model had rain */
    zeroed: Total
    /** Model rain on days without a reading: no rain, or nobody checked the gauge */
    noReading: Total
  }
  irrigation: {
    days: number
    inches: number
    /** Median days between one irrigation and the next, or null with fewer than two */
    typicalInterval: number | null
    /** Median depth applied, or null without any */
    typicalAmount: number | null
  }
  deepDrainage: number
}

export function median(values: number[]): number | null {
  if (!values.length) return null
  const sorted = values.toSorted((a, b) => a - b)
  const middle = Math.floor(sorted.length / 2)
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
}

const round = (inches: number) => Number(inches.toFixed(4))
const total = (values: number[]): Total => ({ days: values.length, inches: round(values.reduce((sum, value) => sum + value, 0)) })

export function seasonStats(days: FieldDay[]): SeasonStats {
  const isReading = (day: FieldDay) => (day.rain_source === 'entered' || day.rain_source === 'group') && day.rain !== null
  const readings = days.filter(isReading)
  const modeledRain = days.flatMap((day) => (day.rain_model !== null && day.rain_model >= RAIN_DAY ? [day.rain_model] : []))

  const both: { entered: number; model: number }[] = []
  const missed: number[] = []
  const zeroed: number[] = []
  const noReading: number[] = []
  for (const day of days) {
    if (day.rain_model === null) continue
    const modelRain = day.rain_model >= RAIN_DAY
    if (!isReading(day)) {
      if (modelRain) noReading.push(day.rain_model)
    } else if (day.rain! >= RAIN_DAY) {
      if (modelRain) both.push({ entered: day.rain!, model: day.rain_model })
      else missed.push(day.rain!)
    } else if (modelRain) {
      zeroed.push(day.rain_model)
    }
  }
  const bothModel = both.reduce((sum, day) => sum + day.model, 0)
  const bothEntered = both.reduce((sum, day) => sum + day.entered, 0)

  const irrigated = days.filter((day) => (day.irrigation ?? 0) > 0)
  const intervals = irrigated.slice(1).map((day, i) => daysBetween(irrigated[i].date, day.date))
  const leftOut = days.flatMap((day) => (day.rain_source === 'none' && day.rain_model !== null && day.rain_model >= RAIN_DAY ? [day.rain_model] : []))

  return {
    days: days.length,
    entered: {
      readings: readings.length,
      rainDays: readings.filter((day) => day.rain! >= RAIN_DAY).length,
      inches: round(readings.reduce((sum, day) => sum + day.rain!, 0)),
    },
    modeled: total(modeledRain),
    leftOut: total(leftOut),
    comparison: {
      both: {
        ...total(both.map((day) => day.entered)),
        disagree: both.filter((day) => Math.abs(day.entered - day.model) > Math.max(DISAGREE_IN, DISAGREE_SHARE * day.model)).length,
        typicalAdjustment: median(both.map((day) => round(day.entered - day.model))),
        ratio: bothModel > 0 ? round(bothEntered / bothModel) : null,
      },
      missed: total(missed),
      zeroed: total(zeroed),
      noReading: total(noReading),
    },
    irrigation: {
      days: irrigated.length,
      inches: round(irrigated.reduce((sum, day) => sum + day.irrigation!, 0)),
      typicalInterval: median(intervals),
      typicalAmount: median(irrigated.map((day) => day.irrigation!)),
    },
    deepDrainage: round(days.reduce((sum, day) => sum + day.deep_drainage, 0)),
  }
}
