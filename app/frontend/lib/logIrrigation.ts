// The dashboard's log irrigation dialog (LogIrrigationDialog): which of a
// system's fields are in season on a day, its last irrigation, and the amounts saving would replace.

import { formatDate, relativeDay } from './dates'
import type { FieldSeasons } from './irrigation'
import type { FieldCard } from './overview'
import { amountRange } from './rain'
import type { Units } from './units'

/**
 * A system's field now, with its seasons, each saying whether it ran on this system
 * (DashboardController#log_props): fieldsOn (lib/irrigation.ts) gives the ones on it on a day
 */
export type LogField = FieldSeasons & { acres: number | null }

/** What the dialog needs of a system beyond the dashboard's: the calculator's and the recent irrigation */
export type LogSystemProps = {
  kind: string
  pump_capacity_gpm: number | null
  inches_at_100: number | null
  log_fields: LogField[]
  /** {date => {field id => inches}} over the days the dialog offers */
  recent_irrigation: Record<string, Record<string, number>>
}

/** Whether the field has a crop on this system that day */
export const inSeason = (field: LogField, date: string): boolean =>
  field.seasons.some((season) => season.here && season.from <= date && date <= season.to)

/**
 * The latest irrigation on the system's fields (their plantings' last, up to today): "Last
 * irrigated yesterday, 0.80 in", "Last irrigated Fri, Jul 17, 0.50–0.80 in", or that there's none
 */
export function lastIrrigationLine(cards: FieldCard[], today: string, units: Units): string {
  const last = cards.flatMap((card) => card.plantings.flatMap((summary) => summary.last_irrigation ?? []))
  if (!last.length) return 'No irrigation entered this season'
  const date = last
    .map((irrigation) => irrigation.date)
    .toSorted()
    .at(-1)!
  const days = relativeDay(date, today)
  const when = days === 'today' || days === 'yesterday' ? days : formatDate(date, { weekday: true })
  const amounts = last.filter((irrigation) => irrigation.date === date).map((irrigation) => irrigation.inches)
  return `Last irrigated ${when}, ${amountRange(amounts, units)}`
}

/**
 * The irrigation already entered on a day for the fields chosen, which saving replaces: "Already
 * 0.80 in on North that day", "Already irrigation that day on North (0.80 in) and South (0.50 in)";
 * null for none
 */
export function replacing(
  recent: LogSystemProps['recent_irrigation'],
  date: string,
  fields: { id: number; name: string }[],
  units: Units,
): string | null {
  const day = recent[date] ?? {}
  const there = fields.filter((field) => day[field.id] !== undefined)
  if (!there.length) return null
  if (there.length === 1) return `Already ${units.format('depth', day[there[0].id])} on ${there[0].name} that day`
  const names = there.map((field) => `${field.name} (${units.format('depth', day[field.id])})`)
  return `Already irrigation that day on ${names.slice(0, -1).join(', ')} and ${names.at(-1)}`
}
