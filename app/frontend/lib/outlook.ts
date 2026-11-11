import type { PlantingSummary } from '@/types/serializers'

import { formatDate, relativeDay } from './dates'
import type { Units } from './units'

// What the projection means for a field, in words, for its page and its dashboard card. Time
// travelling on the field page (projection_source 'observed', PLAN.md Phase 8 F), the projection is
// the weather that followed with nothing more entered, and the words say so; the digest's Outlook
// never time travels, so only this side has that case.

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
      headline: summary.target_in === null ? 'At the irrigation point now' : 'Below target now',
      detail: `About ${depth(crossing.refill)} refills the root zone to field capacity.`,
      chance: null,
      dry: null,
    }
  }
  if (crossing) {
    const scenarios = chanceBy(crossing.date)
    return {
      urgent: crossing.days <= LEAD_DAYS,
      headline: `Irrigate by ${formatDate(crossing.date, { weekday: true })}`,
      detail: replay
        ? `Without more irrigation, the weather that followed took it to ${level} ${crossing.days === 1 ? 'the next day' : `${crossing.days} days later`}, when about ${depth(crossing.refill)} would have refilled the root zone to field capacity.`
        : `Projected to reach ${level} ${relativeDay(crossing.date, today)}, when about ${depth(crossing.refill)} would refill the root zone to field capacity.`,
      chance: scenarios && `${scenarios} reach it by then.`,
      dry,
    }
  }
  const last = projection.at(-1)
  if (!last) return null
  const scenarios = chanceBy(last.date)
  return {
    urgent: false,
    headline: `No irrigation needed through ${formatDate(last.date, { weekday: true })}`,
    detail: replay
      ? `It stayed above ${level} through the weather that followed.`
      : `Projected to stay above ${level} through the end of the forecast.`,
    chance: scenarios && !scenarios.startsWith('0 ') ? `${scenarios} reach it by then.` : null,
    dry,
  }
}
