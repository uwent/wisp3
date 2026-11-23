import type { ExpressionSpecification, Map as MapLibreMap } from 'maplibre-gl'

import type { Palette } from '@/lib/charts/palette'
import type { Boundary } from '@/lib/boundary'

// The symbology the setup maps share (Setup's import, the irrigation system map): what's from an
// outline file is filled, in the color of where it goes; what's saved in WISP is only outlined,
// fields in the map's field color (dashed where a shape will update one) and systems in their cyan
// (references.ts), the only blue but the system being placed on the system picker. Each map adds its layers bottom to top by what matters most:
// skipped or not yet imported shapes, saved fields, shapes updating a field, new fields, systems,
// names. MapLibre has no z-index: layers draw in the order they're added.

/** Where a file's shape goes: nowhere (or not yet), an existing field, or a new one */
export type ShapeState = 'skip' | 'field' | 'new'

/** Line widths in pixels: where a shape goes heavier than what's skipped or already saved */
export const WIDTHS = { skip: 1.25, saved: 1.5, field: 3, new: 3, selected: 4.5, system: 2 }
/** Fill opacity: a skipped shape fainter; the selected one stronger */
export const FILLS = { skip: 0.15, field: 0.3, new: 0.3, selected: 0.5 }

export const shapeColors = (palette: Palette): Record<ShapeState, string> => ({
  new: palette.shapeNew,
  field: palette.shapeUpdate,
  skip: palette.shapeSkip,
})

/** The fill and line layers' ids of one tier of a source's shapes */
export const shapeTierLayers = (source: string, state: ShapeState) => [
  `${source}-${state}-fill`,
  `${source}-${state}-line`,
]

/**
 * One tier of a source of file shapes (features with `state`, and `selected` for the one picked):
 * a fill and a line in its color, its polygons only (label points are drawn by the map)
 */
export function addShapeTier(map: MapLibreMap, palette: Palette, source: string, state: ShapeState, visible = true) {
  const color = shapeColors(palette)[state]
  const filter: ExpressionSpecification = ['all', ['!=', ['geometry-type'], 'Point'], ['==', ['get', 'state'], state]]
  const [fillId, lineId] = shapeTierLayers(source, state)
  const layout = { visibility: visible ? ('visible' as const) : ('none' as const) }
  map.addLayer({
    id: fillId,
    type: 'fill',
    source,
    filter,
    layout,
    paint: {
      'fill-color': color,
      'fill-opacity': ['case', ['==', ['get', 'selected'], true], FILLS.selected, FILLS[state]],
    },
  })
  map.addLayer({
    id: lineId,
    type: 'line',
    source,
    filter,
    layout,
    paint: {
      'line-color': color,
      'line-width': ['case', ['==', ['get', 'selected'], true], WIDTHS.selected, WIDTHS[state]],
    },
  })
}

/** A saved field's outline; updatedBy names the shape that will replace it */
export type SavedField = { name?: string; boundary: Boundary; updatedBy?: string | null }

export const SAVED_FIELD_SOURCE = 'saved-fields'
export const SAVED_FIELD_LAYERS = [
  'saved-fields-hit',
  'saved-fields-casing',
  'saved-fields-line',
  'saved-fields-updated',
]

/** The saved fields as GeoJSON, with a hover line for each */
export const savedFieldData = (fields: SavedField[]) => ({
  type: 'FeatureCollection' as const,
  features: fields.map((field) => ({
    type: 'Feature' as const,
    properties: {
      updated: Boolean(field.updatedBy),
      hover: `Field: ${field.name ?? ''}${field.updatedBy ? ` · updated from ${field.updatedBy}` : ''}`,
    },
    geometry: field.boundary,
  })),
})

/**
 * The saved fields' source and layers: an outline on a thin dark casing (for the street map), dashed
 * where a shape will replace it, and an unseen fill so hovering inside one names it
 */
export function addSavedFieldLayers(map: MapLibreMap, palette: Palette, fields: SavedField[], visible = true) {
  const layout = { visibility: visible ? ('visible' as const) : ('none' as const) }
  const isUpdated: ExpressionSpecification = ['get', 'updated']
  const source = SAVED_FIELD_SOURCE
  map.addSource(source, { type: 'geojson', data: savedFieldData(fields) as never })
  map.addLayer({ id: 'saved-fields-hit', type: 'fill', source, layout, paint: { 'fill-opacity': 0 } })
  map.addLayer({
    id: 'saved-fields-casing',
    type: 'line',
    source,
    filter: ['!', isUpdated],
    layout,
    paint: { 'line-color': palette.fieldCasing, 'line-width': WIDTHS.saved + 1.5, 'line-opacity': 0.35 },
  })
  map.addLayer({
    id: 'saved-fields-line',
    type: 'line',
    source,
    filter: ['!', isUpdated],
    layout,
    paint: { 'line-color': palette.field, 'line-width': WIDTHS.saved, 'line-opacity': 0.85 },
  })
  map.addLayer({
    id: 'saved-fields-updated',
    type: 'line',
    source,
    filter: isUpdated,
    layout,
    paint: { 'line-color': palette.field, 'line-width': WIDTHS.saved, 'line-dasharray': [2, 1.5] },
  })
}

/** A legend entry (MapLegend), drawn as the map draws it */
export type Swatch = {
  label: string
  color: string
  width: number
  filled?: boolean
  dashed?: boolean
  /** A system: a ring, on its dark casing */
  round?: boolean
}

/** The legend's entries for the shared symbology */
export const swatches = (palette: Palette) => {
  const colors = shapeColors(palette)
  return {
    skip: { label: 'Skip', color: colors.skip, width: WIDTHS.skip, filled: true },
    new: { label: 'New field', color: colors.new, width: WIDTHS.new, filled: true },
    field: { label: 'Update field', color: colors.field, width: WIDTHS.field, filled: true },
    saved: { label: 'Saved field', color: palette.field, width: WIDTHS.saved },
    updated: { label: 'Field to update', color: palette.field, width: WIDTHS.saved, dashed: true },
    system: { label: 'Irrigation system', color: palette.system, width: WIDTHS.system, round: true },
  } satisfies Record<string, Swatch>
}
