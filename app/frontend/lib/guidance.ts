import type { Planting, PlantingSummary } from '@/types/serializers'

import { formatDate, relativeDay } from './dates'
import type { Units } from './units'

// How a planting's water use is modeled, and which readings keep it on track, in words for its
// field page. The advice follows the legacy WISP user guide (rev. 8/26/14): soil moisture weekly,
// percent cover from emergence until about 80%, sensors at 25% and 75% of the root zone. The
// model's behavior is Canopy, CanopyCurve and CanopyModel's (PLAN.md §5.3, Phase 6.7); change them
// together. Which readings are due, and the canopy check, come from PlantingTasks (summary.tasks).

/** How often a reading should be entered, in days (PlantingTasks::READING_EVERY) */
export const READING_EVERY = 7
/** Percent cover readings can stop once the canopy covers this much of the ground (PlantingTasks::FULL_COVER_PCT) */
export const FULL_COVER_PCT = 80

type Task = PlantingSummary['tasks'][number]

export type Reading = {
  label: string
  /** "Sep 28 (7 days ago)", or "None entered this season" */
  last: string
  /** Due for another one: none yet, or older than READING_EVERY days */
  due: boolean
  /** "due", "canopy closed", or null */
  note: string | null
}

export type Guidance = {
  title: string
  paragraphs: string[]
  /** Only while the season is on */
  readings: Reading[]
  /** When canopy readings disagree with the crop's curve (the canopy_check task) */
  warning: string | null
}

type GuidedPlanting = Pick<
  Planting,
  | 'plant_name'
  | 'plant_key'
  | 'et_method'
  | 'max_root_zone_depth'
  | 'canopy_curve'
  | 'effective_canopy_interpolation'
  | 'emergence_date'
>

/** Notes for single crops, added after the method's paragraph */
const CROP_NOTES: Record<string, string> = {
  potato: 'For potatoes, measure root zone depth and place sensors from the top of the hill.',
}

export function guidance(
  planting: GuidedPlanting,
  units: Units,
  /** The planting's tasks (summary.tasks): empty outside the season */
  tasks: Task[],
  /** Today, while the season is on; null before or after it */
  today: string | null,
): Guidance {
  const crop = planting.plant_name
  const paragraphs = [methodText(planting)]
  if (CROP_NOTES[planting.plant_key]) paragraphs.push(CROP_NOTES[planting.plant_key])

  const depth = planting.max_root_zone_depth
  paragraphs.push(
    'A soil moisture reading resets the balance to the measured value from that day on, which corrects any ' +
      `drift in the model. Enter a reading about once a week, from sensors at about 25% and 75% of the root zone depth ` +
      `(${units.format('rootDepth', depth * 0.25)} and ${units.format('rootDepth', depth * 0.75)} deep).`,
  )

  return {
    title: `How ${crop.toLowerCase()} is modeled`,
    paragraphs,
    readings: today ? tasks.filter((task) => task.kind !== 'canopy_check').map((task) => reading(task, today)) : [],
    warning: tasks.find((task) => task.kind === 'canopy_check')?.message ?? null,
  }
}

/** How readings combine with the crop's curve, in a sentence */
function interpolationText(planting: GuidedPlanting): string {
  if (!planting.canopy_curve) {
    return 'Between readings WISP draws a straight line, and after the last one it holds that value.'
  }
  if (planting.effective_canopy_interpolation === 'curve') {
    return (
      'Your readings adjust the curve so that it passes through each one, and it keeps its shape between and ' +
      'after them, including its decline late in the season.'
    )
  }
  return (
    'This planting draws straight lines between your readings instead, and holds the last one, as you chose in ' +
    'Setup.'
  )
}

function methodText(planting: GuidedPlanting): string {
  const crop = planting.plant_name
  if (planting.et_method === 'pct_cover') {
    const curve = planting.canopy_curve
      ? `Without readings, WISP follows a ${crop.toLowerCase()} canopy curve from the emergence date (its source is ` +
        'on the About page). '
      : `There's no canopy curve for ${crop.toLowerCase()}, so until you enter your first reading, the model ` +
        'treats the field as bare soil and counts only evaporation from the soil. '
    return (
      `${crop} water use is modeled from percent canopy cover, the share of the ground shaded by the crop: the ` +
      `day's reference ET is adjusted for the cover to estimate the crop's water use. ${curve}${interpolationText(planting)} Enter percent cover about ` +
      `weekly from emergence until the canopy covers about ${FULL_COVER_PCT}% of the ground. For row crops, divide ` +
      'the average canopy width by the row spacing: 18 in wide on 36 in rows is 50%.'
    )
  }
  const lai =
    `${crop} water use is modeled from leaf area index (LAI), the leaf area of the crop per unit of ground ` +
    "beneath it: the day's reference ET is adjusted for how much of the light the leaves intercept."
  // LAI is offered only for crops with a growth curve (Planting#lai_needs_curve), so far field corn's
  return (
    `${lai} Without readings, WISP estimates LAI from the emergence date using a field corn growth curve, ` +
    'which peaks at about 4 around 80 days after emergence. LAI readings you enter (from a ceptometer, for ' +
    'example) adjust the curve. ' +
    interpolationText(planting)
  )
}

function reading(task: Task, today: string): Reading {
  const last = task.last_date
    ? `${formatDate(task.last_date)} (${relativeDay(task.last_date, today)})`
    : 'None entered this season'
  return { label: task.label, last, due: task.due, note: task.note }
}
