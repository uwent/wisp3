import { addDays, daysBetween, formatDate } from '@/lib/dates'
import { count } from '@/lib/text'
import type { Units } from '@/lib/units'

// How a planting is named and sized in the interface: a planting covers the
// whole field or part of it (a plot of length × width, or just its acres)

export type Sized = {
  partial: boolean
  area_acres: number | null
  plot_length_ft: number | null
  plot_width_ft: number | null
}

/** An area, with two decimals below 10 (plots are often a fraction of an acre): "0.05 ac", "12.5 ac" */
export const formatArea = (units: Units, acres: number | null) =>
  units.format('area', acres, { digits: (units.toDisplay('area', acres) ?? 0) < 10 ? 2 : 1 })

/** Part of the field's size: "100 × 20 ft (0.05 ac)", "0.25 ac"; null for the whole field */
export function plotSize(planting: Sized, units: Units): string | null {
  if (!planting.partial) return null
  const area = formatArea(units, planting.area_acres)
  if (planting.plot_length_ft === null || planting.plot_width_ft === null) return area
  const length = units.format('distance', planting.plot_length_ft, { unit: false })
  const width = units.format('distance', planting.plot_width_ft, { unit: false })
  return `${length} × ${width} ${units.label('distance')} (${area})`
}

/** "Soybean (Pioneer)" */
export const cropName = (planting: { plant_name: string; variety: string | null }) =>
  planting.variety ? `${planting.plant_name} (${planting.variety})` : planting.plant_name

/** "Apr 1 – Sep 30" */
export const seasonDates = (planting: { season_start: string; end_date: string }) =>
  `${formatDate(planting.season_start)} – ${formatDate(planting.end_date)}`

/**
 * When a planting is, the way plantings are named: in season, its start and the days since
 * ("May 15, 65 days"); otherwise its season ("Apr 1 – Sep 15")
 */
export function plantingWhen(planting: { season_start: string; end_date: string }, today: string): string {
  const growing = planting.season_start <= today && today <= planting.end_date
  return growing
    ? `${formatDate(planting.season_start)}, ${daysBetween(planting.season_start, today)} days`
    : seasonDates(planting)
}

/**
 * When a planting is, on a status card: as plantingWhen, with an ended season's length
 * ("May 20 – Sep 15 (118 days)")
 */
export function cardWhen(planting: { season_start: string; end_date: string }, today: string): string {
  if (today <= planting.end_date) return plantingWhen(planting, today)
  return `${seasonDates(planting)} (${daysBetween(planting.season_start, planting.end_date)} days)`
}

/** An ended season's totals as PlantingStatus counts them */
type SeasonTotals = {
  rain: number | null
  irrigation: number
  deep_drainage: number
  irrigation_days: number
  rain_days: number
  drainage_days: number
  stress_days: number
}

const times = (n: number) => (n === 1 ? 'once' : `${n} times`)

/**
 * An ended season in four stats, for its card: irrigation (left out for a rainfed crop never watered), rain, deep
 * drainage, and the days spent below the irrigation point (rainfed: short of water)
 */
export function endedSeasonStats(
  totals: SeasonTotals,
  units: Units,
  rainfed = false,
): { label: string; value: string }[] {
  const depth = (inches: number) => units.format('depth', inches)
  return [
    rainfed && !totals.irrigation_days
      ? null
      : {
          label: 'Irrigated',
          value: totals.irrigation_days ? `${times(totals.irrigation_days)}, ${depth(totals.irrigation)}` : 'Never',
        },
    {
      label: 'Rain',
      value:
        totals.rain === null
          ? 'No data'
          : totals.rain_days
            ? `${count(totals.rain_days, 'day')}, ${depth(totals.rain)}`
            : 'None',
    },
    {
      label: 'Deep drainage',
      value: totals.drainage_days ? `${count(totals.drainage_days, 'day')}, ${depth(totals.deep_drainage)}` : 'None',
    },
    {
      label: rainfed ? 'Short of water' : 'Below the irrigation point',
      value: totals.stress_days ? count(totals.stress_days, 'day') : 'Never',
    },
  ].filter((stat) => stat !== null)
}

/** An ended season in a line, for a compact card: "Irrigated 7.20 in · rain 11.80 in · 3 days below the irrigation point" */
export function seasonLine(totals: SeasonTotals, units: Units, rainfed = false): string {
  const depth = (inches: number) => units.format('depth', inches)
  const below = rainfed ? 'short of water' : 'below the irrigation point'
  return [
    totals.irrigation_days ? `Irrigated ${depth(totals.irrigation)}` : rainfed ? 'Rainfed' : 'No irrigation',
    totals.rain === null ? null : `rain ${depth(totals.rain)}`,
    totals.stress_days ? `${count(totals.stress_days, 'day')} ${below}` : `never ${below}`,
  ]
    .filter(Boolean)
    .join(' · ')
}

/** A planting in a line: its crop, with its variety and when in one pair of brackets: "Potato (Russet Burbank, Apr 1 – Sep 15)" */
export const plantingLabel = (
  planting: { plant_name: string; variety: string | null; season_start: string; end_date: string },
  today: string,
) => `${planting.plant_name} (${[planting.variety, plantingWhen(planting, today)].filter(Boolean).join(', ')})`

/** Square feet in an acre (Planting::SQUARE_FEET_PER_ACRE) */
export const SQUARE_FEET_PER_ACRE = 43_560

/** A plot's acres from its length and width in feet, as the server computes them */
export const plotAcres = (lengthFt: number, widthFt: number) => (lengthFt * widthFt) / SQUARE_FEET_PER_ACRE

type Dated = { id?: number; season_start: string; end_date: string; partial: boolean }

/** Whether two seasons share a day */
export const overlaps = (
  a: { season_start: string; end_date: string },
  b: { season_start: string; end_date: string },
) => a.season_start <= b.end_date && a.end_date >= b.season_start

/**
 * The plantings a new or edited one would clash with: other whole-field ones, for a whole-field
 * planting; none, for part of the field (Planting#no_overlap, D19)
 */
export function clashes<T extends Dated>(planting: Dated, others: T[]): T[] {
  return others.filter(
    (other) => other.id !== planting.id && !planting.partial && !other.partial && overlaps(planting, other),
  )
}

/**
 * The plantings a new or edited one would grow alongside, allowed but worth a warning: the
 * whole-field ones its season overlaps, for a plot; the plots, for a whole-field planting
 */
export function alongside<T extends Dated>(planting: Dated, others: T[]): T[] {
  return others.filter(
    (other) => other.id !== planting.id && planting.partial !== other.partial && overlaps(planting, other),
  )
}

/**
 * The fields a new whole-field planting could also go on for these dates ("Also plant
 * this on"): those with no whole-field planting sharing a day of its season, as
 * Planting#no_overlap holds it (plots may be there). Fields in the order given.
 */
export function freeFields<F extends { plantings: Dated[] }>(
  season: { season_start: string; end_date: string },
  fields: F[],
): F[] {
  if (!season.season_start || !season.end_date) return []
  return fields.filter((field) => clashes({ ...season, partial: false }, field.plantings).length === 0)
}

/**
 * The next planting's dates after one ends: it starts the day after, emerges a week later and runs to
 * Nov 30 (or a month, when it starts in November or later)
 */
export function nextSeason(previous: { end_date: string }): {
  season_start: string
  emergence_date: string
  end_date: string
} {
  const start = addDays(previous.end_date, 1)
  const novemberEnd = `${start.slice(0, 4)}-11-30`
  return {
    season_start: start,
    emergence_date: addDays(start, 7),
    end_date: addDays(start, 30) > novemberEnd ? addDays(start, 30) : novemberEnd,
  }
}

/**
 * The suggested harvest date for a crop emerging on emergence: its season's length later (the
 * planting's own, else PlantSerializer's season_days), no later than Nov 30; Nov 30 without one
 * (Planting.typical_end)
 */
export function typicalEnd(seasonDays: number | null | undefined, emergence: string): string {
  const latest = `${emergence.slice(0, 4)}-11-30`
  if (!seasonDays) return latest
  const end = addDays(emergence, seasonDays)
  return end < latest ? end : latest
}

/**
 * Whether "Replace" can end other the day before a planting starting on start: that day must still
 * be after its season start and emergence (a season is at least a day long). PlantingsController's
 * replace_overlapping checks the same.
 */
export function canReplace(other: { season_start: string; emergence_date: string }, start: string): boolean {
  const lastDay = addDays(start, -1)
  return other.season_start < lastDay && other.emergence_date < lastDay
}

/**
 * The longest a season runs, season start to harvest, and how far before the start a crop can have
 * emerged: a year, with room for a leap day (Planting::MAX_SEASON_DAYS). A year's typo would
 * otherwise backfill years of weather and run a balance that long.
 */
export const MAX_SEASON_DAYS = 366

export type SeasonDates = { seasonStart: string; emergence: string; end: string; vineKill?: string | null }

/**
 * What's out of order in a planting's dates, by the date to fix, checked as they're typed:
 * harvest after the season start and after emergence (a season is at least a day long)
 * and within a year of the start (MAX_SEASON_DAYS), and vine kill from emergence to harvest.
 * Emergence may be on or up to a year before the season start (a transplant; a perennial, or a crop
 * already up when tracking starts). Planting#dates_in_order
 * checks the same on save. Blank dates aren't checked (the inputs are required). loose: a saved
 * planting whose dates aren't changing, held to the older rules (harvest on or after the
 * season start and emergence), as the server holds it, so it stays editable.
 */
export function dateProblems(
  { seasonStart, emergence, end, vineKill }: SeasonDates,
  endLabel = 'Harvest',
  { loose = false } = {},
): { emergence?: string; end?: string; vineKill?: string } {
  const problems: { emergence?: string; end?: string; vineKill?: string } = {}
  const after = loose ? 'on or after' : 'after'
  const early = (other: string) => (loose ? end < other : end <= other)
  const startWithYear = seasonStart && formatDate(seasonStart, { year: true })
  if (end && emergence && early(emergence)) {
    problems.end = `${endLabel} must be ${after} emergence (${formatDate(emergence)}).`
  } else if (end && seasonStart && early(seasonStart)) {
    problems.end = `${endLabel} must be ${after} the season start (${formatDate(seasonStart)}).`
  } else if (!loose && end && seasonStart && daysBetween(seasonStart, end) > MAX_SEASON_DAYS) {
    problems.end = `${endLabel} must be within a year of the season start (${startWithYear}).`
  }
  if (!loose && emergence && seasonStart && daysBetween(emergence, seasonStart) > MAX_SEASON_DAYS) {
    problems.emergence = `Emergence must be no more than a year before the season start (${startWithYear}).`
  }
  if (vineKill && emergence && vineKill < emergence) {
    problems.vineKill = `Vine kill can't be before emergence (${formatDate(emergence)}).`
  } else if (vineKill && end && vineKill > end) {
    problems.vineKill = `Vine kill can't be after ${endLabel.toLowerCase()} (${formatDate(end)}).`
  }
  return problems
}
