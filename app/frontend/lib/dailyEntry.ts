import type { PivotKind } from '@/lib/geo'
import { common } from '@/lib/irrigation'

// Daily entry's rows: one table per farm, its levels as indented rows
// (irrigation group, irrigation system ("pivot" in code), field, plot). Rain is entered on group and
// system rows and fills their fields in season (stored per field). Irrigation is each field's and
// plot's own (D15): a system's row fills its fields and their plots, a field's row its plots, and a
// parent shows their shared amount or "varies". Readings belong to one planting.

export type DayEntry = {
  rain_in: number | null
  irrigation_in: number | null
  soil_moisture_pct: number | null
}
export type DayCover = {
  kind: 'pct_cover' | 'lai'
  value: number | null
  due: boolean
  /** The reading before this day */
  last_date: string | null
}
export type DayPlanting = {
  id: number
  plant_name: string
  variety: string | null
  partial: boolean
  area_acres: number | null
  plot_length_ft: number | null
  plot_width_ft: number | null
  /** A part-field planting's own irrigation and soil moisture that day */
  entry: { irrigation_in: number | null; soil_moisture_pct: number | null } | null
  /** Null when no canopy reading is wanted that day */
  cover: DayCover | null
}
export type DayField = {
  id: number
  name: string
  area_acres: number | null
  rain_model: number | null
  entry: DayEntry | null
  /** In season that day, whole field first */
  plantings: DayPlanting[]
}
export type DayPivot = {
  id: number
  name: string
  kind: PivotKind
  /** "Pivot", "Traveler" */
  kind_name: string
  pivot_group_id: number | null
  pump_capacity_gpm: number | null
  /** The percent timer's depth at 100%, for the calculator */
  inches_at_100: number | null
  /** The day before's irrigation on its fields and plots, while there's none this day, for "Same as yesterday" */
  yesterday: { fields: Record<string, number>; plantings: Record<string, number> } | null
  fields: DayField[]
}
export type DayFarm = {
  id: number
  name: string
  /** The farm's rainfall setting, which its groups follow unless they have their own (Q7) */
  use_model_precip: boolean
  /** use_model_precip: the group's own rainfall setting, null following the farm's (Q7) */
  pivot_groups: { id: number; name: string; use_model_precip: boolean | null }[]
  pivots: DayPivot[]
}

/** A field with something growing on it that day */
export const inSeason = (field: DayField) => field.plantings.length > 0

/** The planting covering the whole field that day, if any */
export const wholeField = (field: DayField) => field.plantings.find((planting) => !planting.partial)

export const plots = (field: DayField) => field.plantings.filter((planting) => planting.partial)

/** Anything saved that day on the field or its plots */
export const fieldHasEntry = (field: DayField) =>
  field.entry !== null || field.plantings.some((planting) => planting.entry !== null || planting.cover?.value != null)

export const pivotHasEntry = (pivot: DayPivot) => pivot.fields.some(fieldHasEntry)

export type FarmRows = {
  /** Pivot groups with a pivot in season, and those pivots */
  groups: { id: number; name: string; use_model_precip: boolean | null; pivots: DayPivot[] }[]
  /** Pivots in season and in no group */
  pivots: DayPivot[]
  /** Pivots with no field in season that day, at the end of the farm */
  idle: DayPivot[]
}

/** A farm's pivots in the order daily entry lists them */
export function farmRows(farm: DayFarm): FarmRows {
  const active = (pivot: DayPivot) => pivot.fields.some(inSeason)
  const groups = farm.pivot_groups
    .map((group) => ({ ...group, pivots: farm.pivots.filter((p) => p.pivot_group_id === group.id && active(p)) }))
    .filter((group) => group.pivots.length > 0)
  const grouped = new Set(groups.flatMap((group) => group.pivots.map((p) => p.id)))
  return {
    groups,
    pivots: farm.pivots.filter((p) => active(p) && !grouped.has(p.id)),
    idle: farm.pivots.filter((p) => !active(p)),
  }
}

/** A group's rainfall setting when it isn't its farm's (the farm's is by its name), for its row */
export function rainNote(group: { use_model_precip: boolean | null }, farm: DayFarm): string {
  if (group.use_model_precip === null || group.use_model_precip === farm.use_model_precip) return ''
  return group.use_model_precip ? ' · modeled rain counts' : ' · only entered rain counts'
}

/** The fields a pivot's or group's rain fills: those in season */
export const rainFields = (pivots: DayPivot[]) => pivots.flatMap((pivot) => pivot.fields.filter(inSeason))

/**
 * A group's or system's rain: the fields' entered amount when all have the same, and for the
 * placeholder their shared amount entered or modeled (modeled: none entered), or varies
 */
export function rainView(
  fields: DayField[],
  rain: Record<number, number | null>,
): { value: number | null; shown: number | null; modeled: boolean; varies: boolean } {
  const entered = common(fields.map((field) => rain[field.id] ?? null))
  const effective = common(fields.map((field) => rain[field.id] ?? field.rain_model))
  return {
    value: entered.value,
    shown: effective.value,
    modeled: fields.every((field) => rain[field.id] == null),
    varies: effective.varies,
  }
}

// Irrigation boxes, by key: a field's ("field-3") and a plot's ("plot-12")
export const fieldBox = (id: number) => `field-${id}`
export const plotBox = (id: number) => `plot-${id}`

/** The boxes a field's row fills: the field's and its plots' */
export const fieldBoxes = (field: DayField) => [fieldBox(field.id), ...plots(field).map((plot) => plotBox(plot.id))]

/** The boxes a system's row fills: its fields in season and their plots */
export const systemBoxes = (pivot: DayPivot) => pivot.fields.filter(inSeason).flatMap(fieldBoxes)

/** Irrigation as saved, by box, for every field and plot */
export function savedIrrigation(pivots: DayPivot[]): Record<string, number | null> {
  const boxes: Record<string, number | null> = {}
  for (const field of pivots.flatMap((pivot) => pivot.fields)) {
    boxes[fieldBox(field.id)] = field.entry?.irrigation_in ?? null
    for (const plot of plots(field)) boxes[plotBox(plot.id)] = plot.entry?.irrigation_in ?? null
  }
  return boxes
}

/**
 * What a row's irrigation box shows of the boxes it fills: a system's, their shared amount or
 * varies; a field's, its own amount, or for a field growing only plots (nothing of its own to
 * water), its plots' shared amount
 */
export function rowAmount(
  boxes: string[],
  values: Record<string, number | null>,
): { value: number | null; varies: boolean } {
  return common(boxes.map((box) => values[box] ?? null))
}

export const fieldRowBoxes = (field: DayField) =>
  wholeField(field) || !plots(field).length ? [fieldBox(field.id)] : plots(field).map((plot) => plotBox(plot.id))

/** "Same as yesterday": the day before's amounts for a system's fields in season and their plots, by box */
export function yesterdayBoxes(pivot: DayPivot): Record<string, number | null> | null {
  if (!pivot.yesterday) return null
  const before = pivot.yesterday
  const boxes: Record<string, number | null> = {}
  for (const field of pivot.fields.filter(inSeason)) {
    boxes[fieldBox(field.id)] = before.fields[field.id] ?? null
    for (const plot of plots(field)) boxes[plotBox(plot.id)] = before.plantings[plot.id] ?? null
  }
  return boxes
}
