import { glossaryEntry, type GlossaryEntry } from './glossary'
import type { Units } from './units'

// The info tips on form inputs, one per form and input: `planting.root_zone` says what the
// root zone input is for in the planting form, not what a root zone is. Tips are plain words, at
// most two sentences (fieldInfo.test.ts), for what the input does here and when to change it; a
// hint that must be read before typing stays under the box instead. Where the input's label is a
// glossary term, `term` adds its definition below the tip. When two forms ask the same thing for
// the same reason, both name one shared entry (`fieldCapacity` below), so this
// module lists every tip in the app. Wording from the About page, lib/guidance.ts and the legacy
// user guide; a tip that needs a value in the user's units is a function of them.

type Entry = {
  text: string | ((u: Units) => string)
  /** A glossary id: its definition is shown below the tip */
  term?: string
}

const arc: Entry = {
  text: 'Compass directions from the pivot point: 0 is north, 90 east, 180 south. The arc runs clockwise from its start to its end; dragging its handles on the map fills these in.',
}

const fieldCapacity: Entry = {
  text: "Your own value, from a soil test or sensor readings, in place of the soil type's. Leave it blank unless you've measured this soil.",
  term: 'field_capacity',
}

const wiltingPoint: Entry = {
  text: "Your own value, from a soil test, in place of the soil type's. Leave it blank unless you've measured this soil.",
  term: 'wilting_point',
}

export const FIELD_INFO = {
  'farm.name': {
    text: 'A farm groups the irrigation systems you view and manage together, usually one place. The dashboard, Setup and Daily entry list systems under their farm.',
  },
  'farm.rainfall': {
    text: "Where the water balance gets each day's rain on this farm's systems. Modeled rain needs no gauge but can miss a storm's edge; only the rain you enter is exact, but needs a reading every day it rains.",
  },

  'irrigation_group.name': {
    text: 'Group systems that share a rain gauge, usually ones close together. On Daily entry, rain typed for the group fills in every field of its systems.',
  },
  'irrigation_group.rainfall': {
    text: "Where the balance gets each day's rain for the fields on these systems. Leave it on the farm's setting unless this group's gauge is read differently from the rest of the farm.",
    term: 'entered_rain_only',
  },

  'system.farm': {
    text: 'The farm this system is listed under. Moving it to another farm takes its fields along and takes it out of its group.',
  },
  'system.kind': {
    text: 'How this system waters. A center pivot or linear is drawn to its size on the map; the others are a single point, their area the total of their fields.',
    term: 'irrigation_system',
  },
  'system.coordinates': {
    text: "Where the system sits (a center pivot's pivot point, the middle of a linear or a block), which is where WISP gets its weather; placing it on the map fills this in. You can paste them from Google Maps (right-click the spot) or two spreadsheet cells, or type the latitude then the longitude, in decimal degrees or degrees, minutes and seconds.",
  },
  'system.radius': {
    text: "From the pivot point to the edge of the area it waters, including an end gun's reach. It draws the circle on the map; each field's area is set on the field.",
  },
  'system.sweep': {
    text: 'Partial circle for a pivot that waters only part of a circle, such as one stopped by a road, a building or trees.',
  },
  'system.arc_start': arc,
  'system.arc_end': arc,
  'system.length': {
    text: "The machine's length from end to end: the width of the strip it waters as it travels.",
  },
  'system.travel': {
    text: "How far the machine travels from one end of its run to the other. With the machine's length, it draws the rectangle on the map.",
  },
  'system.bearing': {
    text: 'The compass direction the machine travels, as a whole number from 0 to 179: 0 means it travels north and south, 90 east and west. Turning it by its handle on the map fills this in.',
  },
  'system.pump_capacity': {
    text: "The water the system delivers while it runs. With it, the irrigation calculator works out the inches from the hours it ran, over the fields' areas.",
  },
  'system.inches_at_100': {
    text: "What a circle (or a linear's pass) puts on with the panel's percent timer at 100%, its fastest, from the sprinkler chart. With it, the irrigation calculator works out the inches from the percent you ran at: depth at 100% × 100 ÷ percent.",
  },
  'system.equipment': {
    text: "The machine's make, model or setup, for your records. For a traveler, use the same name at each field it waters.",
  },
  'field.system': {
    text: "The system that waters this field. Its location gives the field its weather, and irrigation typed on the system's row fills in the field's.",
  },
  'field.area': {
    text: "The irrigation calculator uses it to turn a system's hours run into inches of water over its fields, and reports show it. The water balance itself doesn't depend on it.",
  },
  'field.shape': {
    text: "The field's outline, for the map, drawn or read from a file. It offers its acreage and the soil survey's main soil, but never changes them for you.",
  },
  'field.soil': {
    text: "The soil sets how much water the crop's roots can hold onto between rains. Pick the main soil where the crop grows; the soil survey suggests one.",
  },
  'field.shape_names': {
    text: "Which attribute from the file to assign as the field's name.",
  },
  'field.field_capacity': fieldCapacity,
  'field.wilting_point': wiltingPoint,

  'quick_setup.area': {
    text: "The irrigation calculator uses it to turn a system's hours run into inches of water over its fields, and reports show it. You can draw the field's shape later to check it.",
  },

  'planting.crop': {
    text: 'The crop sets how its canopy grows, how deep its roots go and when WISP suggests the harvest. Changing it later recalculates the whole season.',
  },
  'planting.variety': {
    text: 'For your records: WISP models every variety of a crop the same way.',
  },
  'planting.season_start': {
    text: "The day this planting's water balance begins, with the soil holding all the water it can unless you set a starting soil moisture. Usually the planting date.",
  },
  'planting.emergence': {
    text: 'The day the crop comes up. Its canopy, and with it its water use, grows from this date; before it, WISP counts only evaporation from bare soil.',
  },
  'planting.end': {
    text: "The last day of this planting's water balance, suggested from the crop's typical season until you type a date. After it, WISP stops asking for its readings and leaves it out of the morning email.",
  },
  'planting.season_length': {
    text: "Days from emergence to harvest, if your variety or region runs longer or shorter than the crop's typical season. WISP stretches or shortens the crop's canopy curve, its growth and late-season decline, to fit, and suggests the harvest date from it.",
  },
  'planting.vine_kill': {
    text: 'The day the vines are killed before harvest. From it the canopy ramps down to nothing over two weeks, while WISP keeps the water balance going until harvest so you can keep the soil moist through skin set.',
  },
  'planting.size': {
    text: "Whole field for one crop on all of it; part of the field for a plot or bed, so several plantings can grow side by side. A part has its own irrigation and soil moisture readings, and shares the field's rain.",
  },
  'planting.field_capacity': fieldCapacity,
  'planting.wilting_point': wiltingPoint,
  'planting.root_zone': {
    text: "How deep the roots draw water once the crop is grown, which sets how much water it can reach. It starts at the crop's typical depth; change it if you've dug and measured, or a hard layer stops the roots shallower.",
    term: 'root_zone',
  },
  'planting.mad': {
    text: 'How much of the water within the root zone the crop can use before it becomes water-stressed. 50% suits most crops; set it lower for more sensitive crops.',
    term: 'mad',
  },
  'planting.et_method': {
    text: "What you'll measure to keep WISP's picture of the canopy, and so the crop's water use, on track. Percent cover suits every crop; leaf area index is for field corn and corn silage, if you measure it.",
  },
  'planting.canopy_curve': {
    text: "The shape WISP assumes for the canopy's growth until your readings correct it. Pick the one closest to how this crop fills in, or readings only if none fits.",
    term: 'canopy_curve',
  },
  'planting.interpolation': {
    text: "How WISP draws the canopy between your readings. The curve keeps the crop's usual shape, including its decline late in the season; straight lines join the readings and hold the last one.",
  },
  'planting.rainfed': {
    text: 'Whether this crop is irrigated. For a rainfed crop WISP follows the soil moisture the same way, but shows when the crop runs short of water and how stressed it is, in place of when to irrigate, and keeps it out of the fields to irrigate.',
    term: 'rainfed',
  },
  'planting.target_ad': {
    text: 'WISP warns you, and projects the day to irrigate, when the water left falls to this share of its most, instead of when it runs out. Set it to irrigate early, leaving a margin for a hot spell or a slow system.',
    term: 'ad',
  },
  'planting.initial_moisture': {
    text: "The soil moisture on the season's first day, if you know the soil is drier than full. Most seasons start after spring rain with the soil full, so leave it blank.",
  },

  'membership.role': {
    text: 'Members can enter readings and set up farms, systems and fields, but not delete them. Owners can also delete, rename the operation and add or remove people.',
  },
} as const satisfies Record<string, Entry>

export type FieldInfoKey = keyof typeof FIELD_INFO

export type Tip = { text: string; term?: GlossaryEntry }

export function fieldInfo(key: FieldInfoKey, u: Units): Tip {
  const entry: Entry = FIELD_INFO[key]
  const text = typeof entry.text === 'function' ? entry.text(u) : entry.text
  return { text, term: entry.term ? glossaryEntry(entry.term) : undefined }
}
