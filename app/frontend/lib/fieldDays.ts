import { formatDate } from './dates'
import { parseNumber, type ParseResult, type Units } from './units'

// A day's row in the field page's and the planting page's grids (EditableCell): what a cell's box
// starts with, how what's typed is read, its label, and where its irrigation came from.

export type DayColumn = 'rain_in' | 'irrigation_in' | 'soil_moisture_pct' | 'canopy' | 'notes'

/** The values a row shows; the field page's rows have no soil moisture or canopy */
export type DayRow = {
  date: string
  rain: number | null
  rain_source: string
  irrigation: number | null
  irrigation_source: string
  notes: string | null
  soil_moisture_pct?: number | null
  moisture_source?: string | null
  canopy_entered?: number | null
}

/** What a cell's box starts with: the value entered that day, or nothing (a modeled value isn't edited) */
export function cellText(day: DayRow, column: DayColumn, units: Units): string {
  switch (column) {
    case 'rain_in':
      return day.rain_source === 'entered' ? units.input('depth', day.rain) : ''
    case 'irrigation_in':
      return day.irrigation_source === 'entered' ? units.input('depth', day.irrigation) : ''
    case 'soil_moisture_pct':
      return day.moisture_source === 'entered' ? String(day.soil_moisture_pct) : ''
    case 'canopy':
      return day.canopy_entered == null ? '' : String(day.canopy_entered)
    case 'notes':
      return day.notes ?? ''
  }
}

/** What's typed in a cell as the value to save: depths from the user's units, notes trimmed (blank clears) */
export function cellValue(
  column: DayColumn,
  text: string,
  units: Units,
): ParseResult | { ok: true; value: string | null } {
  if (column === 'notes') return { ok: true, value: text.trim() || null }
  return column === 'rain_in' || column === 'irrigation_in' ? units.parse('depth', text) : parseNumber(text)
}

/** A cell's accessible name: "Rain, Wed, Jul 15" */
export const cellLabel = (day: { date: string }, what: string) => `${what}, ${formatDate(day.date, { weekday: true })}`

/** The depth unit in words, for the grids' notes */
export const depthUnitName = (units: Units) => (units.label('depth') === 'mm' ? 'millimeters' : 'inches')

/** Where a day's irrigation came from, beside it: "from traveler" (its system, by kind), "from field"
 * (a plot's view of its field's), or nothing for one entered there */
export function irrigationFrom(source: string, noun: string): string | null {
  if (source === 'pivot') return `from ${noun}`
  if (source === 'field') return 'from field'
  return null
}
