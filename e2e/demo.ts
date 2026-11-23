import names from './demo.json' with { type: 'json' }

// The demo farms' names the browser tests find things by (db/demo/farms.yml, seeded by e2e/seed.rb),
// each for the part it plays. Renaming the demo means changing them here; e2e/seed.rb reads the
// first field from the same file.
//
// firstField: a field with one planting (firstCrop) that the seed keeps in season past today
// (firstPlantingPath), its system in the irrigation group firstFieldGroup. researchField: plots side by side on researchSystem, one of them namedPlot
// (named by its variety). hayField: alfalfa with cuttings, on traveler. gauge: an irrigation group,
// its fields including hayField (on its own traveler, also named hayField) and gaugeField (on
// gaugeFieldSystem). splitPivot: a pivot split into two outlined
// halves, splitWest and splitEast. shapeField: a field whose shape the tests replace, away from
// the KML and shapefile fixtures (near Arlington). awayField: a field on a traveler more than a
// kilometer from the KML fixture's field.
export const DEMO = names

/** A name as it reads inside a RegExp */
export const literal = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
