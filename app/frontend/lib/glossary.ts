// Terms WISP uses, explained where they appear (Term.svelte, GlossaryText.svelte) and, later, on
// the reference page. Definitions follow the water balance (PLAN.md §5) and the legacy user guide.

export type GlossaryEntry = {
  id: string
  term: string
  /**
   * Wordings that mark this term in text, matched as whole words. One in capitals (an
   * abbreviation) matches only in capitals; the rest match in any case.
   */
  matches: string[]
  definition: string
}

export const GLOSSARY: GlossaryEntry[] = [
  {
    id: 'ad',
    term: 'Allowable depletion (AD)',
    matches: ['allowable depletion', 'AD'],
    definition:
      'The water left in the root zone that the crop can use without stress. It is highest at field capacity ' +
      'and 0 at the irrigation point; below 0 the crop is increasingly stressed, down to the wilting point.',
  },
  {
    id: 'mad',
    term: 'MAD (allowable depletion fraction)',
    matches: ['MAD'],
    definition:
      'The share of the root zone’s available water (between field capacity and the wilting point) the crop can ' +
      'use before stress begins. 50% suits most crops; use less for crops very sensitive to water stress.',
  },
  {
    id: 'field_capacity',
    term: 'Field capacity',
    matches: ['field capacity'],
    definition:
      'The soil moisture once a soaked soil has drained, about a day after heavy rain or irrigation. Water ' +
      'above it drains below the root zone.',
  },
  {
    id: 'wilting_point',
    term: 'Wilting point',
    matches: ['permanent wilting point', 'wilting point'],
    definition: 'The soil moisture below which plants can no longer draw water from the soil.',
  },
  {
    id: 'root_zone',
    term: 'Root zone',
    matches: ['root zone'],
    definition:
      'The depth of soil the crop draws water from, which WISP balances as one layer. It is best measured in ' +
      'the field at full canopy.',
  },
  {
    id: 'reference_et',
    term: 'Reference ET',
    matches: ['reference ET', 'ET0'],
    definition:
      'The water a well-watered reference grass would use in a day, calculated from the weather (FAO-56 ' +
      'Penman-Monteith). Crop ET scales it by the crop’s canopy.',
  },
  {
    id: 'crop_et',
    term: 'Crop ET',
    matches: ['crop ET', 'adjusted ET'],
    definition: 'The water the crop uses in a day: reference ET times a crop coefficient from its canopy.',
  },
  {
    id: 'et',
    term: 'Evapotranspiration (ET)',
    matches: ['evapotranspiration', 'ET'],
    definition: 'Water leaving the field by evaporation from the soil and transpiration through the crop’s leaves.',
  },
  {
    id: 'kc',
    term: 'Crop coefficient (Kc)',
    matches: ['crop coefficient', 'Kc'],
    definition:
      'The fraction of reference ET the crop uses, from 0 for bare soil to about 1.1 at full canopy. WISP ' +
      'works it out from percent cover or LAI.',
  },
  {
    id: 'percent_cover',
    term: 'Percent cover',
    matches: ['percent canopy cover', 'percent cover'],
    definition:
      'The share of the ground shaded by the crop’s canopy. For row crops, divide the average canopy width by ' +
      'the row spacing: 18 in wide on 36 in rows is 50%.',
  },
  {
    id: 'lai',
    term: 'Leaf area index (LAI)',
    matches: ['leaf area index', 'LAI'],
    definition:
      'The leaf area of a crop per unit of ground beneath it: an LAI of 3 means three square feet of leaves ' +
      'over each square foot of soil. It can be measured with a ceptometer.',
  },
  {
    id: 'deep_drainage',
    term: 'Deep drainage',
    matches: ['deep drainage'],
    definition:
      'Water that drains below the root zone when rain or irrigation fills it past field capacity. It carries ' +
      'nutrients toward groundwater, so keeping it low saves water and fertilizer.',
  },
  {
    id: 'entered_rain_only',
    term: 'Entered rain only',
    matches: ['only the rain you enter', 'only the rain we enter'],
    definition:
      'A rainfall setting for an operation or a single field: the balance counts only the rain you enter, and ' +
      'days without a reading as dry, instead of the modeled rain. The days ahead still use the forecast’s rain, ' +
      'and the outlook also says when the field would need water if none fell. For a gauge you read every day it ' +
      'rains; nothing is deleted, so you can switch back.',
  },
]

const byId = new Map(GLOSSARY.map((entry) => [entry.id, entry]))

export function glossaryEntry(id: string): GlossaryEntry {
  const entry = byId.get(id)
  if (!entry) throw new Error(`No glossary entry "${id}"`)
  return entry
}

export type Segment = { text: string; entry?: GlossaryEntry }

// Every wording, longest first so "reference ET" wins over "ET"
const wordings = GLOSSARY.flatMap((entry) => entry.matches.map((match) => ({ match, entry }))).sort(
  (a, b) => b.match.length - a.match.length,
)
const escape = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
const pattern = new RegExp(`\\b(?:${wordings.map(({ match }) => escape(match)).join('|')})\\b`, 'gi')
const abbreviation = (match: string) => match === match.toUpperCase()

/**
 * Splits text into plain runs and glossary terms, marking only each term's first appearance.
 * Pass the same `seen` set for every paragraph in a block, so a term is marked once per block.
 */
export function markTerms(text: string, seen: Set<string> = new Set()): Segment[] {
  const segments: Segment[] = []
  let last = 0
  for (const found of text.matchAll(pattern)) {
    const wording = wordings.find(({ match }) =>
      abbreviation(match) ? match === found[0] : match.toLowerCase() === found[0].toLowerCase(),
    )
    if (!wording || seen.has(wording.entry.id)) continue
    seen.add(wording.entry.id)
    if (found.index > last) segments.push({ text: text.slice(last, found.index) })
    segments.push({ text: found[0], entry: wording.entry })
    last = found.index + found[0].length
  }
  if (last < text.length) segments.push({ text: text.slice(last) })
  return segments
}
