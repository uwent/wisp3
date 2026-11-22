import { addDays, formatDate } from '@/lib/dates'
import type { PivotKind } from '@/lib/geo'
import type { Units } from '@/lib/units'

// Daily entry's week view (Phase 9 §6): rain and irrigation for the seven days ending on a date, as
// one grid per farm (props from DailyEntryWeek). A cell fills the fields under its row that day, as
// a parent row does on the day page: rain a group's or system's, irrigation a system's (stored per
// field, D15; the server also sets their plots that had the field's amount). Every cell starts
// from what's saved (the fields' shared amount, blank when they vary); only the cells changed are
// submitted, under each day's names (days[<date>][fields][<id>][rain_in], the day page's within
// it), so a cell left alone can't clear anything.

export type WeekDay = {
  /** A field in season under the row that day */
  active: boolean
  /** The fields' common amount, null when blank or when they differ */
  value: number | null
  varies: boolean
  /** The fields typing here fills, with their amounts as saved (irrigation's with the acres the calculator spreads run hours over) */
  fields: { id: number; name: string; value: number | null; acres?: number | null; plot?: boolean }[]
}
export type WeekRainRow = {
  /** "group-3", "pivot-12" */
  key: string
  name: string
  kind: 'group' | 'system'
  /** A group's systems in season */
  systems?: number
  /** A system's kind ("Pivot") */
  kind_name?: string
  days: WeekDay[]
}
export type WeekIrrigationRow = {
  /** "pivot-12" */
  key: string
  id: number
  name: string
  kind: PivotKind
  kind_name: string
  /** For the irrigation calculator */
  pump_capacity_gpm: number | null
  inches_at_100: number | null
  days: WeekDay[]
}
export type WeekFarm = { id: number; name: string; rain_rows: WeekRainRow[]; irrigation_rows: WeekIrrigationRow[] }

/** "Jul 14–20", "Jun 28–Jul 4", "Dec 29, 2025–Jan 4, 2026" */
export function weekLabel(start: string, end: string): string {
  if (start.slice(0, 4) !== end.slice(0, 4))
    return `${formatDate(start, { year: true })}–${formatDate(end, { year: true })}`
  if (start.slice(0, 7) !== end.slice(0, 7)) return `${formatDate(start)}–${formatDate(end)}`
  return `${formatDate(start)}–${Number(end.slice(8, 10))}`
}

/** The week ending on date: its first day and label */
export const weekOf = (end: string) => ({ start: addDays(end, -6), end, label: weekLabel(addDays(end, -6), end) })

export const rainKey = (row: WeekRainRow, date: string) => `rain:${row.key}:${date}`
export const irrigationKey = (row: WeekIrrigationRow, date: string) => `irrigation:${row.key}:${date}`

/**
 * A depth as a cell shows it, always to the depth's places (units.digits: "1.00" in, "25.4" mm), as
 * the day page's boxes do; blank for none
 */
export const depthText = (value: number | null, units: Units) =>
  value === null ? '' : (units.toDisplay('depth', value) as number).toFixed(units.digits('depth'))

/** A cell's text as saved */
export const cellText = (day: WeekDay, units: Units) => depthText(day.value, units)

/** What's typed, shown to the depth's places once the cell is left; as typed when it can't be read */
export function settledText(text: string, units: Units): string {
  const parsed = units.parse('depth', text)
  return parsed.ok ? depthText(parsed.value, units) : text
}

/** The texts of every cell as saved, by cell key */
export function savedTexts(farms: WeekFarm[], dates: string[], units: Units): Record<string, string> {
  const texts: Record<string, string> = {}
  for (const farm of farms) {
    for (const row of farm.rain_rows)
      dates.forEach((date, i) => (texts[rainKey(row, date)] = cellText(row.days[i], units)))
    for (const row of farm.irrigation_rows)
      dates.forEach((date, i) => (texts[irrigationKey(row, date)] = cellText(row.days[i], units)))
  }
  return texts
}

export type Input = { name: string; value: string }
export type ChangedCell = { key: string; label: string; date: string; varies: boolean }

const stored = (value: number | null) => (value === null ? '' : String(value))

/**
 * The cells changed from what's saved, and the hidden inputs that submit them: the cell's value for
 * each of its fields, as rain_in or irrigation_in. A cell that can't be read is left out (its box
 * stops the form submitting).
 */
export function changes(
  farms: WeekFarm[],
  dates: string[],
  texts: Record<string, string>,
  units: Units,
): { cells: ChangedCell[]; inputs: Input[] } {
  const cells: ChangedCell[] = []
  const inputs: Input[] = []
  const collect = (key: string, label: string, date: string, day: WeekDay, attribute: string) => {
    // Left as shown (a saved 0.177 shows 0.18): nothing to send
    const text = (texts[key] ?? '').trim()
    if (text === cellText(day, units)) return
    const parsed = units.parse('depth', text)
    if (!parsed.ok) return
    // The same amount typed another way ("0.4" for "0.40") isn't a change; nor is a blank on varied amounts
    const rounded = parsed.value === null ? null : units.parse('depth', depthText(parsed.value, units))
    const value = rounded?.ok ? rounded.value : parsed.value
    if (value === day.value) return
    cells.push({ key, label, date, varies: day.varies })
    // A field growing only plots is its plots, each saved as the plot's own (DailyEntryWeek)
    for (const field of day.fields)
      inputs.push({
        name: `days[${date}][${field.plot ? 'plantings' : 'fields'}][${field.id}][${attribute}]`,
        value: stored(value),
      })
  }
  for (const farm of farms) {
    for (const row of farm.rain_rows)
      dates.forEach((date, i) => collect(rainKey(row, date), row.name, date, row.days[i], 'rain_in'))
    for (const row of farm.irrigation_rows)
      dates.forEach((date, i) =>
        collect(irrigationKey(row, date), `${row.name} irrigation`, date, row.days[i], 'irrigation_in'),
      )
  }
  return { cells, inputs }
}

/** "East group, Thu Jul 17" for each changed cell whose fields had different amounts */
export const variedOverwrites = (cells: ChangedCell[]) =>
  cells.filter((cell) => cell.varies).map((cell) => `${cell.label}, ${formatDate(cell.date, { weekday: true })}`)

/** Save's confirm before replacing different amounts on each field, or null when nothing would be */
export function overwriteMessage(cells: ChangedCell[]): string | null {
  const list = variedOverwrites(cells)
  if (!list.length) return null
  return `This replaces different amounts on each field for: ${list.join('; ')}. Save anyway?`
}

/** A cell's fields and their amounts, for its tooltip: "North 0.4 in, South 0.6 in" */
export const fieldAmounts = (day: WeekDay, units: Units) =>
  day.fields.map((field) => `${field.name} ${units.format('depth', field.value)}`).join(', ')

export type Cell = { row: number; col: number }
export type Move = 'up' | 'down' | 'left' | 'right'

/** The arrow and Enter keys that move between cells: Enter moves down, as in a spreadsheet */
export function keyMove(key: string): Move | null {
  return (
    (
      { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right', Enter: 'down' } as Record<
        string,
        Move
      >
    )[key] ?? null
  )
}

/**
 * Whether an arrow key leaves the box rather than moving the caret: left from its start, right from
 * its end, either when all of it is selected (as it is when a cell is reached by keys); up, down and
 * Enter always
 */
export function leavesBox(move: Move, start: number | null, end: number | null, length: number): boolean {
  if (move === 'up' || move === 'down' || start === null || end === null) return true
  if (start === 0 && end === length) return true
  return move === 'left' ? end === 0 : start === length
}

/** The nearest cell in that direction among those that can take a value, or null at the edge */
export function nextCell(cells: Cell[], from: Cell, move: Move): Cell | null {
  const vertical = move === 'up' || move === 'down'
  const sign = move === 'down' || move === 'right' ? 1 : -1
  const candidates = cells.filter((cell) =>
    vertical
      ? cell.col === from.col && (cell.row - from.row) * sign > 0
      : cell.row === from.row && (cell.col - from.col) * sign > 0,
  )
  const distance = (cell: Cell) => Math.abs(vertical ? cell.row - from.row : cell.col - from.col)
  return candidates.reduce<Cell | null>((best, cell) => (best && distance(best) <= distance(cell) ? best : cell), null)
}

const firstMessage = (message: string | string[] | undefined) => (Array.isArray(message) ? message[0] : message)

/**
 * The save's errors (keyed days.<date>.fields.<id>.rain_in or .irrigation_in) by the cell they
 * belong to, each with its row and day for the list above Save
 */
export function cellErrors(
  farms: WeekFarm[],
  dates: string[],
  errors: Record<string, string | string[]>,
): Record<string, { label: string; date: string; message: string }> {
  const found: Record<string, { label: string; date: string; message: string }> = {}
  if (!Object.keys(errors).length) return found
  const check = (key: string, label: string, date: string, day: WeekDay, attribute: string) => {
    const message = day.fields
      .map((field) =>
        firstMessage(errors[`days.${date}.${field.plot ? 'plantings' : 'fields'}.${field.id}.${attribute}`]),
      )
      .find(Boolean)
    if (message) found[key] = { label, date, message }
  }
  for (const farm of farms) {
    for (const row of farm.rain_rows)
      dates.forEach((date, i) => check(rainKey(row, date), `${row.name} rain`, date, row.days[i], 'rain_in'))
    for (const row of farm.irrigation_rows)
      dates.forEach((date, i) =>
        check(irrigationKey(row, date), `${row.name} irrigation`, date, row.days[i], 'irrigation_in'),
      )
  }
  return found
}
