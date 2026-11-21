import { readStored, writeStored } from '@/lib/storage'

// Setup's last choices, for this tab's session (sessionStorage): a new planting starts from the
// crop and dates last saved, for the same season, and a new field from the soil last chosen, so
// setting up a dozen fields doesn't mean choosing the same things a dozen times. Suggestions only:
// the form's own values (an edited record, the next planting's dates, the soil survey) come first.

const PLANTING = 'setup.lastPlanting'
const SOIL = 'setup.lastSoil'

export type LastPlanting = { plant_id: number; season_start: string; emergence_date: string; end_date: string }

const isDate = (value: unknown, year: number): value is string =>
  typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) && value.startsWith(String(year))

export function rememberPlanting(planting: LastPlanting) {
  writeStored(PLANTING, planting, 'session')
}

/** The crop and dates last saved, if they were for this season */
export function lastPlanting(year: number): LastPlanting | null {
  const saved = readStored(PLANTING, 'session') as Partial<LastPlanting> | undefined
  if (typeof saved !== 'object' || saved === null || typeof saved.plant_id !== 'number') return null
  const { plant_id, season_start, emergence_date, end_date } = saved
  // A season can run into the next year
  if (
    !isDate(season_start, year) ||
    !isDate(emergence_date, year) ||
    !(isDate(end_date, year) || isDate(end_date, year + 1))
  )
    return null
  return { plant_id, season_start, emergence_date, end_date }
}

export function rememberSoil(soilTypeId: number) {
  writeStored(SOIL, soilTypeId, 'session')
}

/** The soil type last chosen for a field */
export function lastSoil(): number | null {
  const saved = readStored(SOIL, 'session')
  return typeof saved === 'number' ? saved : null
}
