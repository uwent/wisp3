import type { PlantingSummary } from '@/types/serializers'

import { formatDate, relativeDay } from './dates'
import type { Units } from './units'

// What the projection means for a field, in words, for its page and its dashboard card

export type Outlook = {
  /** Needs attention: at or below the threshold now, or projected to be within the lead days */
  urgent: boolean
  headline: string
  detail: string
  /** "4 of 31 forecast scenarios…", or null without an ensemble */
  chance: string | null
}

/** Matches PlantingStatus::LEAD_DAYS */
export const LEAD_DAYS = 3

export function outlook(summary: PlantingSummary, units: Units): Outlook | null {
  if (summary.phase !== 'active' || !summary.date) return null
  const today = summary.date
  const level = summary.target_in === null ? 'the irrigation point' : 'its target'
  const depth = (inches: number) => units.format('depth', inches)
  const { crossing, projection, ensemble_size: members } = summary
  const chanceBy = (date: string) => {
    const chance = projection.find((day) => day.date === date)?.chance
    return chance == null || !members ? null : `${Math.round(chance * members)} of ${members} forecast scenarios`
  }

  if (crossing && crossing.days === 0) {
    return {
      urgent: true,
      headline: summary.target_in === null ? 'At the irrigation point now' : 'Below target now',
      detail: `About ${depth(crossing.refill)} refills the root zone to field capacity.`,
      chance: null,
    }
  }
  if (crossing) {
    const scenarios = chanceBy(crossing.date)
    return {
      urgent: crossing.days <= LEAD_DAYS,
      headline: `Irrigate by ${formatDate(crossing.date, { weekday: true })}`,
      detail: `Projected to reach ${level} ${relativeDay(crossing.date, today)}; about ${depth(crossing.refill)} would refill it to field capacity then.`,
      chance: scenarios && `${scenarios} reach it by then.`,
    }
  }
  const last = projection.at(-1)
  if (!last) return null
  const scenarios = chanceBy(last.date)
  return {
    urgent: false,
    headline: `No irrigation needed through ${formatDate(last.date, { weekday: true })}`,
    detail: `Projected to stay above ${level} through the forecast.`,
    chance: scenarios && !scenarios.startsWith('0 ') ? `${scenarios} reach it by then.` : null,
  }
}
