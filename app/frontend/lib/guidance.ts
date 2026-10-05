import type { FieldDay, Planting } from '@/types/serializers'

import { daysBetween, formatDate, relativeDay } from './dates'
import type { Units } from './units'

// How a planting's water use is modeled, and which readings keep it on track, in words for its
// field page. The advice follows the legacy WISP user guide (rev. 8/26/14): soil moisture weekly,
// percent cover from emergence until about 80%, sensors at 25% and 75% of the root zone. The
// model's behavior is Canopy and CanopyModel's (PLAN.md §5.3); change them together.

/** How often a reading should be entered, in days */
export const READING_EVERY = 7
/** Percent cover readings can stop once the canopy covers this much of the ground */
export const FULL_COVER_PCT = 80

export type Reading = {
  label: string
  /** "Sep 28 (7 days ago)", or "None this season" */
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
}

/** Notes for single crops, added after the method's paragraph */
const CROP_NOTES: Record<string, string> = {
  potato: 'For potatoes, measure root zone depth and place sensors from the top of the hill.',
}

export function guidance(
  planting: Pick<Planting, 'plant_name' | 'plant_key' | 'et_method' | 'canopy_curve' | 'max_root_zone_depth'>,
  days: Pick<FieldDay, 'date' | 'moisture_source' | 'canopy_entered'>[],
  units: Units,
  /** Today, while the season is on; null before or after it */
  today: string | null,
): Guidance {
  const crop = planting.plant_name
  const paragraphs = [methodText(planting)]
  if (CROP_NOTES[planting.plant_key]) paragraphs.push(CROP_NOTES[planting.plant_key])

  const depth = planting.max_root_zone_depth
  paragraphs.push(
    'A measured soil moisture resets the balance to it from that day on, which corrects any drift in the ' +
      `model. Enter one about once a week, from sensors at about 25% and 75% of the root zone ` +
      `(${units.format('rootDepth', depth * 0.25)} and ${units.format('rootDepth', depth * 0.75)} deep).`,
  )

  return { title: `How ${crop.toLowerCase()} is modeled`, paragraphs, readings: today ? readings(planting, days, today) : [] }
}

function methodText(planting: Pick<Planting, 'plant_name' | 'et_method' | 'canopy_curve'>): string {
  const crop = planting.plant_name
  if (planting.et_method === 'pct_cover') {
    return (
      `${crop} water use is modeled from percent canopy cover, the share of the ground shaded by the crop: the ` +
      "day's reference ET is scaled by it. Between readings WISP draws a straight line, and after the last one it " +
      `holds that value. Enter percent cover about weekly from emergence until the canopy covers about ` +
      `${FULL_COVER_PCT}% of the ground. For row crops, divide the average canopy width by the row spacing: 18 in ` +
      'wide on 36 in rows is 50%.'
    )
  }
  const lai =
    `${crop} water use is modeled from leaf area index (LAI), the leaf area of the crop per unit of ground ` +
    "beneath it: the day's reference ET is scaled by how much of the light the leaves intercept."
  if (planting.canopy_curve) {
    return (
      `${lai} Without readings, WISP projects LAI from the emergence date on a field corn growth curve, which ` +
      'peaks at about 4 around 80 days after emergence. LAI you enter (from a ceptometer, say) replaces the curve ' +
      'for the season, and after your last reading WISP holds that value, so once you start, keep entering them.'
    )
  }
  return (
    `${lai} There's no LAI growth curve for ${crop.toLowerCase()}, so WISP uses only the LAI you enter, and until the ` +
    'first reading the crop uses no water in the model. Enter LAI readings regularly, or switch this planting to ' +
    'percent cover in setup.'
  )
}

function readings(
  planting: Pick<Planting, 'et_method' | 'canopy_curve'>,
  days: Pick<FieldDay, 'date' | 'moisture_source' | 'canopy_entered'>[],
  today: string,
): Reading[] {
  const last = (entered: (day: (typeof days)[number]) => boolean) => days.findLast(entered)
  const reading = (label: string, day: (typeof days)[number] | undefined): Reading => {
    const due = !day || daysBetween(day.date, today) > READING_EVERY
    const last = day ? `${formatDate(day.date)} (${relativeDay(day.date, today)})` : 'None this season'
    return { label, last, due, note: due ? 'due' : null }
  }

  const list = [reading('Soil moisture', last((day) => day.moisture_source !== null))]
  const canopy = last((day) => day.canopy_entered !== null)
  if (planting.et_method === 'pct_cover') {
    const cover = reading('Percent cover', canopy)
    // Done once the canopy is nearly closed: WISP holds the last reading
    list.push(canopy && canopy.canopy_entered! >= FULL_COVER_PCT ? { ...cover, due: false, note: 'canopy closed' } : cover)
  } else if (!planting.canopy_curve || canopy) {
    list.push(reading('LAI', canopy))
  }
  return list
}
