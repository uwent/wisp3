import { addDays, daysBetween, parseDate } from '@/lib/dates'

// A field's season timeline (PLAN.md Phase 8 G.11): its plantings as bars across the season, like a
// Gantt chart. Plantings in season together (plots side by side) get rows of their own; one after
// another (successions) share a row.

export type TimelineInput = { id: number; season_start: string; end_date: string; partial: boolean }

export type TimelineBar<T> = {
  planting: T
  row: number
  /** Where the bar starts and how wide it is, as percentages of the axis */
  left: number
  width: number
}

export type Timeline<T> = {
  /** The axis: Apr 1 to Nov 30 of the year, widened to whole months to take in every planting */
  from: string
  to: string
  months: { label: string; left: number; width: number }[]
  rows: number
  bars: TimelineBar<T>[]
  /** Where today falls on the axis, as a percentage, or null outside it */
  today: number | null
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

const iso = (year: number, month: number, day: number) =>
  `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`

const monthStart = (date: string) => date.slice(0, 8) + '01'

/**
 * Lays out the plantings of one year: the earliest start first, each in the first row free by then
 * (whole-field plantings never overlap, so a field without plots stays one row)
 */
export function timeline<T extends TimelineInput>(plantings: T[], year: number, today: string): Timeline<T> {
  const starts = [iso(year, 3, 1), ...plantings.map((p) => p.season_start)].sort()
  const ends = [iso(year, 10, 30), ...plantings.map((p) => p.end_date)].sort()
  const from = monthStart(starts[0])
  const to = lastDayOfMonth(ends[ends.length - 1])
  const span = daysBetween(from, to) + 1
  const at = (date: string) => (Math.min(Math.max(daysBetween(from, date), 0), span) / span) * 100

  const rowEnds: string[] = []
  const bars = plantings
    .toSorted((a, b) => a.season_start.localeCompare(b.season_start) || a.id - b.id)
    .map((planting) => {
      let row = rowEnds.findIndex((end) => end < planting.season_start)
      if (row === -1) row = rowEnds.length
      rowEnds[row] = planting.end_date
      const left = at(planting.season_start)
      return { planting, row, left, width: at(addDays(planting.end_date, 1)) - left }
    })

  const months = []
  for (let month = from; month <= to; month = nextMonth(month)) {
    const left = at(month)
    months.push({ label: MONTHS[parseDate(month).getUTCMonth()], left, width: at(nextMonth(month)) - left })
  }

  return {
    from,
    to,
    months,
    rows: Math.max(rowEnds.length, 1),
    bars,
    today: today >= from && today <= to ? at(today) : null,
  }
}

function lastDayOfMonth(date: string) {
  const d = parseDate(date)
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).toISOString().slice(0, 10)
}

function nextMonth(date: string) {
  const d = parseDate(date)
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1)).toISOString().slice(0, 10)
}
