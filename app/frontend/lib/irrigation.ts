// Irrigation is stored in inches, per field and per plot (D15). A system's row fills its fields'
// boxes; the calculator works the inches out from run hours or the percent timer.

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

/** 1 acre-inch of water, in gallons */
export const GALLONS_PER_ACRE_INCH = 27_154

/** The kinds with a percent timer (Pivot::TIMER_KINDS) */
export const hasTimer = (kind: string): boolean => kind === 'center' || kind === 'linear'

/** "circle" for a center pivot, "pass" for a linear */
export const circleNoun = (kind: string) => (kind === 'linear' ? 'pass' : 'circle')

/** What the calculator needs to know about a system */
export type CalculatorSystem = { kind: string; pump_capacity_gpm: number | null; inches_at_100: number | null }

/**
 * How the calculator works out inches for a system: run hours for any, and the percent timer for a
 * pivot or linear (the pump capacity and depth at 100% can be typed there when the system has none)
 */
export type CalculatorMethod = 'hours' | 'percent'

export const calculatorMethods = (system: { kind: string }): CalculatorMethod[] =>
  hasTimer(system.kind) ? ['hours', 'percent'] : ['hours']

/**
 * What the calculator takes (stored units), past which a value is a typo or another unit: a pump
 * of more than 5,000 gpm; more than a day's hours; a depth at 100% over Pivot::MAX_INCHES_AT_100; a
 * timer outside 1–100%; more than 5 circles (a circle at 100% takes most systems 12 hours or more);
 * and more than 5 inches put on in a day (a heavy irrigation is 1–2 inches)
 */
export const CALCULATOR_LIMITS = {
  gpm: { max: 5000 },
  hours: { max: 24 },
  inchesAt100: { max: 3 },
  percent: { min: 1, max: 100 },
  circles: { max: 5 },
  inches: { max: 5 },
} as const

/** Whether a typed value is out of its range: 'low' (0 or less, or under min) or 'high'; null when it's fine or blank */
export function outOfRange(value: number | null, limit: { min?: number; max: number }): 'low' | 'high' | null {
  if (value === null) return null
  if (limit.min === undefined ? !(value > 0) : value < limit.min) return 'low'
  return value > limit.max ? 'high' : null
}

/**
 * The depth a percent timer setting puts on: at 100% the end tower never stops and a circle puts
 * on the depth at 100%; at 40% it moves 40% of each minute, so the circle takes 2.5 times as long
 * and puts on 2.5 times the depth. null for no percent or one out of range.
 */
export function percentInches(inchesAt100: number | null, percent: number | null, circles: number | null = 1) {
  if (inchesAt100 === null || percent === null || !(percent > 0) || percent > 100) return null
  if (circles !== null && !(circles > 0)) return null
  return ((inchesAt100 * 100) / percent) * (circles ?? 1)
}

/**
 * The depth run hours put on: the pump's gallons a minute for that long, spread over the acres
 * watered. null without hours, or without an area for each field watered.
 */
export function hoursInches(gpm: number | null, hours: number | null, acres: (number | null)[]): number | null {
  if (gpm === null || hours === null || hours < 0 || !acres.length || acres.some((a) => a === null)) return null
  const total = (acres as number[]).reduce((sum, a) => sum + a, 0)
  if (!(total > 0)) return null
  return (gpm * hours * 60) / (GALLONS_PER_ACRE_INCH * total)
}

/**
 * A parent row's amount, as a view of the boxes it fills: their value when all agree (null when all
 * are blank), or varies when they don't
 */
export function common(values: (number | null)[]): { value: number | null; varies: boolean } {
  const first = values[0] ?? null
  return values.every((value) => value === first) ? { value: first, varies: false } : { value: null, varies: true }
}
