import type { PlantingSummary } from '@/types/serializers'

import { formatDate, relativeDay } from './dates'
import type { Units } from './units'

// What the projection means for a field, in words, for its page and its dashboard card. Time
// travelling on the field page (projection_source 'observed', PLAN.md Phase 8 F), the projection is
// what happened next (the weather and what was entered), so the words look back at it; the
// digest's Outlook never time travels, so only this side has that case.

export type Outlook = {
  /** Needs attention: at or below the threshold now, or projected to be within the lead days */
  urgent: boolean
  headline: string
  detail: string
  /** "4 of 31 forecast scenarios…", or null without an ensemble */
  chance: string | null
  /**
   * For a field using only entered rain, when it needs water if no rain falls, where that's sooner
   * than the forecast case (Q7); otherwise null
   */
  dry: string | null
}

/** Matches PlantingStatus::LEAD_DAYS */
export const LEAD_DAYS = 3

export function outlook(summary: PlantingSummary, units: Units): Outlook | null {
  if (summary.phase !== 'active' || !summary.date) return null
  // No curve and no reading (PLAN.md Phase 8 G.3): the balance can't say when to irrigate
  if (summary.status === 'needs_canopy') {
    return {
      urgent: false,
      headline: 'No canopy data',
      detail: `WISP can't estimate ${summary.plant_name.toLowerCase()} water use until you enter a percent cover reading.`,
      chance: null,
      dry: null,
    }
  }
  const today = summary.date
  const level = summary.target_in === null ? 'the irrigation point' : 'its target'
  const depth = (inches: number) => units.format('depth', inches)
  const { crossing, projection, ensemble_size: members } = summary
  const replay = summary.projection_source === 'observed'
  const chanceBy = (date: string) => {
    const chance = projection.find((day) => day.date === date)?.chance
    return chance == null || !members ? null : `${Math.round(chance * members)} of ${members} forecast scenarios`
  }

  const dryCrossing = summary.dry_crossing ?? null
  const dry =
    !replay && dryCrossing && (!crossing || dryCrossing.date < crossing.date)
      ? `If no rain falls, irrigate by ${formatDate(dryCrossing.date, { weekday: true })} (${relativeDay(dryCrossing.date, today)}).`
      : null

  if (crossing && crossing.days === 0) {
    return {
      urgent: true,
      headline: `${summary.target_in === null ? 'Irrigate now' : 'Below target now'} · about ${depth(crossing.refill)} refills it`,
      detail: `${summary.target_in === null ? 'At or below the irrigation point' : 'Below its target'} today; that amount refills the root zone to field capacity.`,
      chance: null,
      dry: null,
    }
  }
  if (crossing) {
    const scenarios = chanceBy(crossing.date)
    return {
      urgent: crossing.days <= LEAD_DAYS,
      headline: replay
        ? `Reached ${level} ${formatDate(crossing.date, { weekday: true })}`
        : `Irrigate by ${formatDate(crossing.date, { weekday: true })} · about ${depth(crossing.refill)} refills it`,
      detail: replay
        ? `With the weather that followed and what was entered for those days, it reached ${level} ${crossing.days === 1 ? 'the next day' : `${crossing.days} days later`}, when about ${depth(crossing.refill)} would have refilled the root zone to field capacity.`
        : `Projected to reach ${level} ${relativeDay(crossing.date, today)}; that amount then refills the root zone to field capacity.`,
      chance: scenarios && `${scenarios} reach it by then.`,
      dry,
    }
  }
  const last = projection.at(-1)
  if (!last) return null
  const scenarios = chanceBy(last.date)
  return {
    urgent: false,
    headline: replay
      ? `Stayed above ${level} through ${formatDate(last.date, { weekday: true })}`
      : `No irrigation needed through ${formatDate(last.date, { weekday: true })}`,
    detail: replay
      ? `With the weather that followed and what was entered for those days, it stayed above ${level}.`
      : `Projected to stay above ${level} through the end of the forecast.`,
    chance: scenarios && !scenarios.startsWith('0 ') ? `${scenarios} reach it by then.` : null,
    dry,
  }
}
