// The week's rain in words (RainAhead on the dashboard, and the log irrigation dialog).
// A day's chance is the share of the forecast ensemble's members with
// 0.1 in or more (ForecastDays::WET_IN): likely at 50% or more, possible at 20% or more. Without a
// chance (the example farm's stored days, or no ensemble yet) a day with 0.1 in or more is likely.

import { dayName } from './forecast'
import type { Units } from './units'
import type { ForecastDay } from '@/types/serializers'

export const RAIN_LIKELY = 50
export const RAIN_POSSIBLE = 20
const WET_IN = 0.1

export type RainOdds = 'likely' | 'possible'

export const ODDS_WORDS: Record<RainOdds, string> = { likely: 'Rain likely', possible: 'Rain possible' }

type RainDay = Pick<ForecastDay, 'date' | 'precip_in' | 'precip_chance'>

export function rainOdds(day: Pick<RainDay, 'precip_in' | 'precip_chance'>): RainOdds | null {
  if (day.precip_chance === null) return (day.precip_in ?? 0) >= WET_IN ? 'likely' : null
  if (day.precip_chance >= RAIN_LIKELY) return 'likely'
  if (day.precip_chance >= RAIN_POSSIBLE) return 'possible'
  return null
}

/** The first day with rain likely or possible, or null */
export function nextRain<T extends RainDay>(days: T[]): (T & { odds: RainOdds }) | null {
  for (const day of days) {
    const odds = rainOdds(day)
    if (odds) return { ...day, odds }
  }
  return null
}

/** "Tomorrow, 60% chance, 0.2 in"; "Thu, 0.4 in" without a chance */
export function rainWords(day: RainDay, today: string, units: Units): string {
  const parts = [dayName(day.date, today)]
  if (day.precip_chance !== null) parts.push(`${day.precip_chance}% chance`)
  parts.push(units.format('depth', day.precip_in))
  return parts.join(', ')
}

/** "Next rain: Tue, 60% chance, 0.2 in", "No rain expected in the next 7 days", or null without a forecast */
export function nextRainLine(days: RainDay[], today: string, units: Units): string | null {
  if (!days.length) return null
  const day = nextRain(days)
  return day
    ? `Next rain: ${rainWords(day, today, units)}`
    : `No rain expected in the next ${days.length === 1 ? 'day' : `${days.length} days`}`
}

/** "today", "tomorrow" or "on Tue" */
function when(date: string, today: string): string {
  const name = dayName(date, today)
  return name === 'Today' || name === 'Tomorrow' ? name.toLowerCase() : `on ${name}`
}

/** "0.20 in", or "0.10–0.40 in" when the amounts differ as shown (blanks left out) */
export function amountRange(amounts: (number | null)[], units: Units): string {
  const known = amounts.filter((inches): inches is number => inches !== null)
  if (!known.length) return units.format('depth', null)
  const [low, high] = [Math.min(...known), Math.max(...known)].map((inches) => units.format('depth', inches))
  return low === high ? low : `${low.replace(` ${units.label('depth')}`, '')}–${high}`
}

/**
 * The first rain over several weather zones, for the dashboard's closed strip: "Rain likely
 * tomorrow, all fields, 0.20–0.40 in", "Rain possible on Tue, some fields, 0.10 in", "No rain
 * expected in the next 7 days"; with one zone, no "all fields". Likely when any zone's rain is
 * likely that day. Null without a forecast.
 */
export function rainSummary(zones: { days: RainDay[] }[], today: string, units: Units): string | null {
  const withDays = zones.filter((zone) => zone.days.length)
  if (!withDays.length) return null
  const wet = withDays.flatMap((zone) =>
    zone.days.flatMap((day) => {
      const odds = rainOdds(day)
      return odds ? [{ ...day, odds }] : []
    }),
  )
  if (!wet.length) {
    const days = Math.max(...withDays.map((zone) => zone.days.length))
    return `No rain expected in the next ${days === 1 ? 'day' : `${days} days`}`
  }
  const date = wet.map((day) => day.date).toSorted()[0]
  const that = wet.filter((day) => day.date === date)
  const odds = that.some((day) => day.odds === 'likely') ? 'likely' : 'possible'
  const where = withDays.length === 1 ? '' : that.length === withDays.length ? ', all fields' : ', some fields'
  // The amount only when the forecast gives one (a possible day's can be none)
  const amounts = that.map((day) => day.precip_in).filter((inches) => inches !== null && inches >= 0.005)
  return `Rain ${odds} ${when(date, today)}${where}${amounts.length ? `, ${amountRange(amounts, units)}` : ''}`
}

/** A day with no chance of rain (or none known) and none forecast; a day without an amount isn't */
export const noRain = (day: Pick<RainDay, 'precip_in' | 'precip_chance'>): boolean =>
  (day.precip_chance ?? 0) === 0 && day.precip_in !== null && day.precip_in < 0.005
