import type { PivotKind } from '@/lib/geo'
import type { PivotIrrigation } from '@/types/serializers'

// Daily entry's rows (PLAN.md Phase 8 G.4): one table per farm, its levels as indented rows
// (irrigation group, irrigation system ("pivot" in code), field, plot). Rain fills down from a group or pivot row into its fields; irrigation
// is inherited (the pivot's, then the field's, shown muted); readings belong to one planting.

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
  irrigation: PivotIrrigation | null
  fields: DayField[]
}
export type DayFarm = {
  id: number
  name: string
  pivot_groups: { id: number; name: string }[]
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

export const pivotHasEntry = (pivot: DayPivot) => pivot.irrigation !== null || pivot.fields.some(fieldHasEntry)

export type FarmRows = {
  /** Pivot groups with a pivot in season, and those pivots */
  groups: { id: number; name: string; pivots: DayPivot[] }[]
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

/** The fields a pivot's or group's rain fills: those in season */
export const rainFields = (pivots: DayPivot[]) => pivots.flatMap((pivot) => pivot.fields.filter(inSeason))

/**
 * A parent row's rain, as a view of its fields': their value when all agree (null when all are
 * blank), or varies when they don't
 */
export function common(values: (number | null)[]): { value: number | null; varies: boolean } {
  const first = values[0] ?? null
  return values.every((value) => value === first) ? { value: first, varies: false } : { value: null, varies: true }
}

/** Whether a pivot's irrigation reaches a field, given the fields it's applied to (null: all) */
export const applies = (fieldIds: number[] | null, field: DayField) => fieldIds === null || fieldIds.includes(field.id)

/** "5 of 6 fields", "All 6 fields" */
export function appliedLabel(fieldIds: number[] | null, total: number): string {
  const count = fieldIds === null ? total : fieldIds.length
  if (count === total) return total === 1 ? 'Its field' : `All ${total} fields`
  return `${count} of ${total} ${total === 1 ? 'field' : 'fields'}`
}

/** "3 fields", "1 field" */
export const count = (n: number, one: string, many = `${one}s`) => `${n} ${n === 1 ? one : many}`
