// The fields a system's irrigation can apply to on a date (G.14 part 7), mirroring Pivot#fields_on:
// a field whose season that day ran on the system, or one of its fields with nothing planted then.
// A season keeps the system it ran on, so a field moved away is still on it for its earlier
// seasons, and a field moved here isn't for seasons that ran elsewhere.

export type FieldSeasons = {
  id: number
  name: string
  // On the system now
  here: boolean
  // Its plantings, the one Field#planting_on picks first; dates as ISO strings
  seasons: { from: string; to: string; here: boolean }[]
}

export function fieldsOn<T extends FieldSeasons>(fields: T[], date: string): T[] {
  return fields.filter((field) => {
    const season = field.seasons.find((s) => s.from <= date && date <= s.to)
    return season ? season.here : field.here
  })
}

type HoursSystem = { pump_capacity_gpm: number | null; fields: { area_acres: number | null }[] }
type Amounts = { inches: number | null; run_hours: number | null }

// Run hours convert to inches through the pump capacity and the irrigated area
// (PivotIrrigation#irrigated_acres), so they can be entered only when the system has both
export const canUseHours = (pivot: HoursSystem): boolean =>
  pivot.pump_capacity_gpm !== null && pivot.fields.every((field) => field.area_acres !== null)

/** Whether a saved irrigation was entered as run hours (it has no inches of its own) */
export const enteredAsHours = (irrigation: Amounts | null | undefined): boolean =>
  irrigation != null && irrigation.inches === null

/** A saved irrigation's amount in the box for inches or for run hours; null for none */
export const savedAmount = (irrigation: Amounts | null | undefined, byHours: boolean): number | null =>
  (byHours ? irrigation?.run_hours : irrigation?.inches) ?? null
