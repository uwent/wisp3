import { addDays, daysBetween, formatDate } from '@/lib/dates'
import type { Units } from '@/lib/units'

// How a planting is named and sized in the interface (PLAN.md Phase 8 G.11): a planting covers the
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
 * When a planting is, the way plantings are named (G.14): in season, its start and the days since
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
 * ("May 20 – Sep 15 (118 days)", G.6)
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
const dayCount = (n: number) => (n === 1 ? '1 day' : `${n} days`)

/**
 * An ended season in four stats, for its card (G.6): irrigation, rain, deep drainage, and the days
 * spent below the irrigation point
 */
export function seasonStats(totals: SeasonTotals, units: Units): { label: string; value: string }[] {
  const depth = (inches: number) => units.format('depth', inches)
  return [
    {
      label: 'Irrigated',
      value: totals.irrigation_days ? `${times(totals.irrigation_days)}, ${depth(totals.irrigation)}` : 'Never',
    },
    {
      label: 'Rain',
      value:
        totals.rain === null
          ? 'No data'
          : totals.rain_days
            ? `${dayCount(totals.rain_days)}, ${depth(totals.rain)}`
            : 'None',
    },
    {
      label: 'Deep drainage',
      value: totals.drainage_days ? `${dayCount(totals.drainage_days)}, ${depth(totals.deep_drainage)}` : 'None',
    },
    { label: 'Below the irrigation point', value: totals.stress_days ? dayCount(totals.stress_days) : 'Never' },
  ]
}

/** An ended season in a line, for a compact card: "Irrigated 7.20 in · rain 11.80 in · 3 days below the irrigation point" */
export function seasonLine(totals: SeasonTotals, units: Units): string {
  const depth = (inches: number) => units.format('depth', inches)
  return [
    totals.irrigation_days ? `Irrigated ${depth(totals.irrigation)}` : 'No irrigation',
    totals.rain === null ? null : `rain ${depth(totals.rain)}`,
    totals.stress_days
      ? `${dayCount(totals.stress_days)} below the irrigation point`
      : 'never below the irrigation point',
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
 * The plantings a new or edited one would clash with: any, for a whole-field planting; whole-field
 * ones, for part of the field (Planting#no_overlap)
 */
export function clashes<T extends Dated>(planting: Dated, others: T[]): T[] {
  return others.filter(
    (other) => other.id !== planting.id && overlaps(planting, other) && !(planting.partial && other.partial),
  )
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
 * The suggested harvest date for a crop emerging on emergence: its typical season's length later
 * (PlantSerializer's season_days), no later than Nov 30; Nov 30 without one (Planting.typical_end)
 */
export function typicalEnd(seasonDays: number | null | undefined, emergence: string): string {
  const latest = `${emergence.slice(0, 4)}-11-30`
  if (!seasonDays) return latest
  const end = addDays(emergence, seasonDays)
  return end < latest ? end : latest
}
