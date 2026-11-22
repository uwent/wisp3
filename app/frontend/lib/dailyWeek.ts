import { addDays, formatDate } from '@/lib/dates'
import type { PivotKind } from '@/lib/geo'
import { enteredAs, type IrrigationUnit, savedAmount } from '@/lib/irrigation'
import { parseNumber, type ParseResult, type Units } from '@/lib/units'

// Daily entry's week view (Phase 9 §6): rain and irrigation for the seven days ending on a date, as
// one grid per farm (props from DailyEntryWeek). Every cell starts from what's saved; only the cells
// changed are submitted, under each day's names (days[<date>][fields][<id>][rain_in], the day page's
// within it), so a cell left alone can't clear anything.

export type WeekRainDay = {
  /** A field in season under the row that day */
  active: boolean
  /** The fields' common rain, null when blank or when they differ */
  value: number | null
  varies: boolean
  /** The fields typing here fills, with their rain as saved */
  fields: { id: number; name: string; rain_in: number | null }[]
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
  days: WeekRainDay[]
}
export type WeekIrrigation = {
  inches: number | null
  run_hours: number | null
  percent_timer: number | null
  circles: number | null
  field_ids: number[] | null
}
export type WeekIrrigationDay = {
  active: boolean
  irrigation: WeekIrrigation | null
  /** The fields it was applied to, when only some of those on the system that day */
  some_fields: string[] | null
}
export type WeekIrrigationRow = {
  id: number
  name: string
  kind: PivotKind
  kind_name: string
  /** Run hours can be entered (a pump capacity and the fields' areas) */
  hours: boolean
  /** The percent timer's depth at 100%, null when a percent can't be entered */
  inches_at_100: number | null
  days: WeekIrrigationDay[]
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
export const irrigationKey = (row: WeekIrrigationRow, date: string) => `irrigation:${row.id}:${date}`

/** The units a system's irrigation can be entered in (unitsFor in lib/irrigation.ts) */
export const rowUnits = (row: WeekIrrigationRow): IrrigationUnit[] => [
  'inches',
  ...(row.hours ? (['hours'] as const) : []),
  ...(row.inches_at_100 !== null ? (['percent'] as const) : []),
]

/** A system's irrigation unit for the week: the way its latest entry that week was entered, else inches */
export function defaultUnit(row: WeekIrrigationRow): IrrigationUnit {
  const latest = row.days.findLast((day) => day.irrigation !== null)
  const unit = enteredAs(latest?.irrigation)
  return rowUnits(row).includes(unit) ? unit : 'inches'
}

/** A rain cell's text as saved */
export const rainText = (day: WeekRainDay, units: Units) => units.input('depth', day.value)

/** An irrigation cell's text as saved, in inches (the user's depth unit), run hours or percent */
export function irrigationText(day: WeekIrrigationDay, unit: IrrigationUnit, units: Units): string {
  const amount = savedAmount(day.irrigation, unit)
  if (amount === null) return ''
  return unit === 'inches' ? units.input('depth', amount) : String(amount)
}

/** A cell's saved irrigation entered in another unit, as its placeholder: "0.8 in", "10 h", "40%" */
export function otherText(day: WeekIrrigationDay, unit: IrrigationUnit, units: Units): string {
  const entered = enteredAs(day.irrigation)
  const amount = savedAmount(day.irrigation, entered)
  if (entered === unit || amount === null) return ''
  return entered === 'inches' ? units.format('depth', amount) : entered === 'hours' ? `${amount} h` : `${amount}%`
}

/** What's typed in a cell, read: stored inches for depths, hours and percents as typed */
export const parseCell = (text: string, unit: IrrigationUnit, units: Units): ParseResult =>
  unit === 'inches' ? units.parse('depth', text) : parseNumber(text)

/** The texts of every cell as saved, by cell key */
export function savedTexts(
  farms: WeekFarm[],
  dates: string[],
  unit: Record<number, IrrigationUnit>,
  units: Units,
): Record<string, string> {
  const texts: Record<string, string> = {}
  for (const farm of farms) {
    for (const row of farm.rain_rows)
      dates.forEach((date, i) => (texts[rainKey(row, date)] = rainText(row.days[i], units)))
    for (const row of farm.irrigation_rows)
      dates.forEach(
        (date, i) => (texts[irrigationKey(row, date)] = irrigationText(row.days[i], unit[row.id] ?? 'inches', units)),
      )
  }
  return texts
}

export type Input = { name: string; value: string }
export type ChangedCell = { key: string; label: string; date: string; varies: boolean }

const stored = (value: number | null) => (value === null ? '' : String(value))

/**
 * The cells changed from what's saved, and the hidden inputs that submit them: a rain cell's value
 * for each of its fields; an irrigation cell's inches, run hours or percent (one circle; the others
 * blank, so saving one way clears another, and all blank removes it), with the fields a saved
 * irrigation applies to
 * (not sent means all, PivotIrrigation.normalize_field_ids). A cell that can't be read is left out
 * (its box stops the form submitting).
 */
export function changes(
  farms: WeekFarm[],
  dates: string[],
  texts: Record<string, string>,
  unit: Record<number, IrrigationUnit>,
  units: Units,
): { cells: ChangedCell[]; inputs: Input[] } {
  const cells: ChangedCell[] = []
  const inputs: Input[] = []
  for (const farm of farms) {
    for (const row of farm.rain_rows) {
      dates.forEach((date, i) => {
        const day = row.days[i]
        const key = rainKey(row, date)
        const text = (texts[key] ?? '').trim()
        if (text === rainText(day, units)) return
        const parsed = parseCell(text, 'inches', units)
        if (!parsed.ok) return
        cells.push({ key, label: row.name, date, varies: day.varies })
        for (const field of day.fields)
          inputs.push({ name: `days[${date}][fields][${field.id}][rain_in]`, value: stored(parsed.value) })
      })
    }
    for (const row of farm.irrigation_rows) {
      const as = unit[row.id] ?? 'inches'
      dates.forEach((date, i) => {
        const day = row.days[i]
        const key = irrigationKey(row, date)
        const text = (texts[key] ?? '').trim()
        if (text === irrigationText(day, as, units)) return
        const parsed = parseCell(text, as, units)
        if (!parsed.ok) return
        cells.push({ key, label: row.name, date, varies: false })
        const name = `days[${date}][pivots][${row.id}]`
        const amount = (u: IrrigationUnit) => (as === u ? stored(parsed.value) : '')
        inputs.push({ name: `${name}[inches]`, value: amount('inches') })
        inputs.push({ name: `${name}[run_hours]`, value: amount('hours') })
        inputs.push({ name: `${name}[percent_timer]`, value: amount('percent') })
        inputs.push({ name: `${name}[circles]`, value: '' })
        const fieldIds = day.irrigation?.field_ids
        if (fieldIds && parsed.value !== null) {
          // The blank first entry keeps the list a list (Rails can't tell an empty one from none sent)
          inputs.push({ name: `${name}[field_ids][]`, value: '' })
          for (const id of fieldIds) inputs.push({ name: `${name}[field_ids][]`, value: String(id) })
        }
      })
    }
  }
  return { cells, inputs }
}

/** "East group, Thu Jul 17" for each changed rain cell whose fields had different amounts */
export const variedOverwrites = (cells: ChangedCell[]) =>
  cells.filter((cell) => cell.varies).map((cell) => `${cell.label}, ${formatDate(cell.date, { weekday: true })}`)

/** Save's confirm before replacing different amounts on each field, or null when nothing would be */
export function overwriteMessage(cells: ChangedCell[]): string | null {
  const list = variedOverwrites(cells)
  if (!list.length) return null
  return `This replaces different amounts on each field for: ${list.join('; ')}. Save anyway?`
}

/** A rain cell's fields and their amounts, for its tooltip: "North 0.4 in, South 0.6 in" */
export const fieldAmounts = (day: WeekRainDay, units: Units) =>
  day.fields.map((field) => `${field.name} ${units.format('depth', field.rain_in)}`).join(', ')

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
 * The save's errors (keyed days.<date>.fields.<id>.rain_in, days.<date>.pivots.<id>.inches) by the
 * cell they belong to, each with its row and day for the list above Save
 */
export function cellErrors(
  farms: WeekFarm[],
  dates: string[],
  errors: Record<string, string | string[]>,
): Record<string, { label: string; date: string; message: string }> {
  const found: Record<string, { label: string; date: string; message: string }> = {}
  if (!Object.keys(errors).length) return found
  for (const farm of farms) {
    for (const row of farm.rain_rows) {
      dates.forEach((date, i) => {
        const message = row.days[i].fields
          .map((field) => firstMessage(errors[`days.${date}.fields.${field.id}.rain_in`]))
          .find(Boolean)
        if (message) found[rainKey(row, date)] = { label: `${row.name} rain`, date, message }
      })
    }
    for (const row of farm.irrigation_rows) {
      dates.forEach((date) => {
        const message = ['inches', 'run_hours', 'percent_timer', 'circles', 'field_ids']
          .map((attribute) => firstMessage(errors[`days.${date}.pivots.${row.id}.${attribute}`]))
          .find(Boolean)
        if (message) found[irrigationKey(row, date)] = { label: `${row.name} irrigation`, date, message }
      })
    }
  }
  return found
}
