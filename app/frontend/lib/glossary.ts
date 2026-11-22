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
      "The water left in the root zone that the crop can use without stress. It's at its highest when the soil is at field capacity and 0 at the irrigation point. Below 0 the crop is increasingly stressed, down to the wilting point.",
  },
  {
    id: 'mad',
    term: 'MAD (allowable depletion fraction)',
    matches: ['MAD'],
    definition:
      "The share of the root zone's available water (between field capacity and the wilting point) that the crop can use before stress begins. 50% suits most crops; use a lower value for crops that are very sensitive to water stress.",
  },
  {
    id: 'field_capacity',
    term: 'Field capacity',
    matches: ['field capacity'],
    definition:
      'The water a soil holds once it has drained after being soaked, about a day after heavy rain or irrigation. Water above that level drains below the root zone.',
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
      'The depth of soil the crop draws water from, which WISP balances as one layer. It is best measured in the field at full canopy.',
  },
  {
    id: 'reference_et',
    term: 'Reference ET',
    matches: ['reference ET', 'ET0'],
    definition:
      "The water a well-watered reference grass would use in a day, calculated from the weather (FAO-56 Penman-Monteith). WISP works it out each hour from corrected solar radiation and humidity. Crop ET is this amount adjusted for the crop's canopy.",
  },
  {
    id: 'solar_radiation',
    term: 'Solar radiation',
    matches: ['solar radiation', 'shortwave radiation'],
    definition:
      "The sunshine reaching the ground, measured as energy per area (MJ/m² over a day). It drives most of a day's reference ET. Weather models tend to overestimate it, so WISP corrects it against weather stations.",
  },
  {
    id: 'crop_et',
    term: 'Crop ET',
    matches: ['crop ET', 'adjusted ET'],
    definition:
      "The water the crop and its soil use in a day: reference ET multiplied by a crop coefficient, from the crop's canopy and how wet the soil's surface is.",
  },
  {
    id: 'et',
    term: 'Evapotranspiration (ET)',
    matches: ['evapotranspiration', 'ET'],
    definition: "Water leaving the field by evaporation from the soil and transpiration through the crop's leaves.",
  },
  {
    id: 'kc',
    term: 'Crop coefficient (Kc)',
    matches: ['crop coefficient', 'Kc'],
    definition:
      "The fraction of reference ET the field uses, in two parts (FAO-56's dual crop coefficient). The crop's own share rises with the canopy to its full-cover value from FAO-56 (1.05 for potato, 1.15 for field corn), adjusted for the day's wind and humidity, and eases toward its harvest value late in the season. The soil's share is evaporation from the wet surface between the plants: high just after rain or irrigation, falling as the surface dries, and small under a closed canopy. WISP calculates it from percent cover or LAI.",
  },
  {
    id: 'percent_cover',
    term: 'Percent cover',
    matches: ['percent canopy cover', 'percent cover'],
    definition:
      "The share of the ground shaded by the crop's canopy. For row crops, divide the average canopy width by the row spacing: 18 in wide on 36 in rows is 50%.",
  },
  {
    id: 'lai',
    term: 'Leaf area index (LAI)',
    matches: ['leaf area index', 'LAI'],
    definition:
      'The leaf area of a crop per unit of ground beneath it: an LAI of 3 means three square feet of leaves over each square foot of soil. It can be measured with a ceptometer.',
  },
  {
    id: 'canopy_curve',
    term: 'Canopy curve',
    matches: ['canopy curve', 'crop curve'],
    definition:
      "A crop's typical percent cover (or LAI) as it grows from emergence. Curves run by days after emergence, except potato's, which runs by growing degree days, so its canopy grows faster in warm weather and slower in cool weather. WISP follows the curve until you enter readings, then adjusts it to pass through them. Each crop's curve and its source are on the About page.",
  },
  {
    id: 'fao56',
    term: 'FAO-56',
    matches: ['FAO-56'],
    definition:
      "The UN Food and Agriculture Organization's Irrigation and Drainage Paper 56, Crop Evapotranspiration, the standard guide to estimating crop water use worldwide (first edition 1998, Allen, Pereira, Raes and Smith; second edition 2025, Pereira, Allen and colleagues). WISP takes its reference ET equation, crop coefficients and soil evaporation from the 2025 edition. See Sources on the About page.",
  },
  {
    id: 'aquacrop',
    term: 'AquaCrop',
    matches: ['AquaCrop'],
    definition:
      "FAO's crop growth model, which simulates how a crop's canopy grows and declines and how its yield responds to water. WISP's canopy curves use its canopy cover equations, and start from its crop files where it has one. See Sources on the About page.",
  },
  {
    id: 'deep_drainage',
    term: 'Deep drainage',
    matches: ['deep drainage'],
    definition:
      'Water that drains below the root zone when rain or irrigation fills it past field capacity. It carries nutrients toward groundwater, so keeping it low saves water and fertilizer.',
  },
  {
    id: 'entered_rain_only',
    term: 'Entered rain only',
    matches: ['only the rain you enter', 'only the rain we enter'],
    definition:
      "A rainfall setting for a farm or one of its irrigation groups. Instead of the modeled rain, the balance counts only the rain you enter and treats days with no entry as dry. The days ahead still use the forecast's rain, and the outlook also says when the field would need water if no rain fell. Use it if you read a gauge every day it rains. Nothing is deleted, so you can switch back at any time.",
  },
  {
    id: 'planting',
    term: 'Planting',
    matches: ['planting', 'plantings'],
    definition:
      "A crop growing on a field for one season, from season start to harvest, with its own water balance. A planting covers the whole field or part of it (a plot, sized by length and width or by area), so a field can grow one crop after another, or several side by side. Rain is the field's; a plot can have its own irrigation and soil moisture readings.",
  },
  {
    id: 'irrigation_system',
    term: 'Irrigation system',
    matches: ['irrigation system', 'irrigation systems'],
    definition:
      'A place watered one way: a center pivot, a linear, a traveler, a solid set or drip block, or just a location. Its location sets the weather for its fields, and irrigation typed for it in Daily entry fills in their amounts. A traveler moved between fields is set up at each field it waters.',
  },
  {
    id: 'irrigation_group',
    term: 'Irrigation group',
    matches: ['irrigation group', 'irrigation groups'],
    definition:
      'Irrigation systems on one farm kept together, such as those near one rain gauge. Rain typed for the group on Daily entry fills in every field of its systems.',
  },
  {
    id: 'weather_zone',
    term: 'Weather zone',
    matches: ['weather zone', 'weather zones'],
    definition:
      "One cell of the weather model's grid, about 6 miles (9 km) across. Irrigation systems in the same cell share its weather; the Weather tab has each zone's forecast and season.",
  },
  {
    id: 'percent_timer',
    term: 'Percent timer',
    matches: ['percent timer'],
    definition:
      "How a center pivot's or linear's panel sets its speed: the share of each minute the end tower moves. At 100% a circle (or pass) is fastest and puts on the least water, the depth at 100% from its sprinkler chart; at 40% it takes 2.5 times as long and puts on 2.5 times the depth. WISP's irrigation calculator works out the inches from the depth at 100%, once that's set on the system. It's the speed setting, not a VRI zone's nozzle rate, which puts on less water at a lower percent.",
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
