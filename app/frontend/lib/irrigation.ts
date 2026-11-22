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
type TimerSystem = { kind: string; inches_at_100: number | null }
type Amounts = {
  inches: number | null
  run_hours: number | null
  percent_timer?: number | null
  circles?: number | null
}

/**
 * How an irrigation's amount is entered: inches (the user's depth unit), the hours the system ran,
 * or a center pivot's or linear's percent timer (docs/plans/phase-9.md §8)
 */
export type IrrigationUnit = 'inches' | 'hours' | 'percent'

// Run hours convert to inches through the pump capacity and the irrigated area
// (PivotIrrigation#irrigated_acres), so they can be entered only when the system has both
export const canUseHours = (pivot: HoursSystem): boolean =>
  pivot.pump_capacity_gpm !== null && pivot.fields.every((field) => field.area_acres !== null)

/** The kinds with a percent timer (Pivot::TIMER_KINDS) */
export const hasTimer = (kind: string): boolean => kind === 'center' || kind === 'linear'

// The percent timer converts through the system's depth at 100% (Pivot#percent_timer?)
export const canUsePercent = (pivot: TimerSystem): boolean => hasTimer(pivot.kind) && pivot.inches_at_100 !== null

/** The units a system's irrigation can be entered in, inches first */
export const unitsFor = (pivot: HoursSystem & TimerSystem): IrrigationUnit[] => [
  'inches',
  ...(canUseHours(pivot) ? (['hours'] as const) : []),
  ...(canUsePercent(pivot) ? (['percent'] as const) : []),
]

/**
 * The depth a percent timer setting puts on (Pivot#inches_at_percent): at 100% the end tower never
 * stops and a circle puts on the depth at 100%; at 40% it moves 40% of each minute, so the circle
 * takes 2.5 times as long and puts on 2.5 times the depth. null for no percent or one out of range.
 */
export function percentInches(inchesAt100: number | null, percent: number | null, circles: number | null = 1) {
  if (inchesAt100 === null || percent === null || !(percent > 0) || percent > 100) return null
  return ((inchesAt100 * 100) / percent) * (circles ?? 1)
}

/** "circle" for a center pivot, "pass" for a linear */
export const circleNoun = (kind: string) => (kind === 'linear' ? 'pass' : 'circle')

/** How a saved irrigation was entered: inches, else the percent timer, else run hours; inches for none */
export function enteredAs(irrigation: Amounts | null | undefined): IrrigationUnit {
  if (irrigation == null || irrigation.inches !== null) return 'inches'
  return irrigation.percent_timer != null ? 'percent' : irrigation.run_hours != null ? 'hours' : 'inches'
}

/** A saved irrigation's amount in the box for its unit; null for none */
export function savedAmount(irrigation: Amounts | null | undefined, unit: IrrigationUnit): number | null {
  if (unit === 'hours') return irrigation?.run_hours ?? null
  if (unit === 'percent') return irrigation?.percent_timer ?? null
  return irrigation?.inches ?? null
}

/**
 * "Same as yesterday" on daily entry: the day before's irrigation as it was entered (inches, run
 * hours or percent, with its circles) and the fields it applied to, still on the system; null when
 * there's nothing to offer (a unit the system can no longer convert)
 */
export function sameAsBefore(
  before: (Amounts & { field_ids: number[] | null }) | null | undefined,
  pivot: TimerSystem & { pump_capacity_gpm: number | null; fields: { id: number; area_acres: number | null }[] },
): { unit: IrrigationUnit; value: number; circles: number | null; fieldIds: number[] } | null {
  if (!before) return null
  const unit = enteredAs(before)
  const value = savedAmount(before, unit)
  if (value === null || !unitsFor(pivot).includes(unit)) return null
  const here = pivot.fields.map((field) => field.id)
  const fieldIds = before.field_ids?.filter((id) => here.includes(id)) ?? []
  return {
    unit,
    value,
    circles: unit === 'percent' ? (before.circles ?? null) : null,
    fieldIds: fieldIds.length ? fieldIds : here,
  }
}

/** A field's own irrigation on a day (FieldEntry): inches, and the percent they came from */
export type FieldAmount = { irrigation_in: number | null; irrigation_pct: number | null }

/**
 * How a field's own amount is entered beside its system's, and its value: as it was saved (a percent,
 * or inches), else the percent its sector ran at when the system's is a percent (sector speed
 * control), else inches. A percent needs the system's depth at 100%.
 */
export function fieldOverride(
  amount: FieldAmount | null | undefined,
  unit: IrrigationUnit,
  percentOk: boolean,
): { unit: 'inches' | 'percent'; value: number | null } {
  if (amount?.irrigation_pct != null && percentOk) return { unit: 'percent', value: amount.irrigation_pct }
  if (amount?.irrigation_in != null) return { unit: 'inches', value: amount.irrigation_in }
  return { unit: unit === 'percent' && percentOk ? 'percent' : 'inches', value: null }
}
