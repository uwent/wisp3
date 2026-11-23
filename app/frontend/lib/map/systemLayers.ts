import type {
  ExpressionSpecification,
  GeoJSONSourceSpecification,
  Map as MapLibreMap,
  PointLike,
  SymbolLayerSpecification,
} from 'maplibre-gl'

import type { Palette } from '@/lib/charts/palette'
import { isPoint, linearOf, type SystemShape } from '@/lib/geo'

import { segmentDistance } from '@/lib/planar'

import { type Glyph, GLYPH_CORNERS, GLYPH_INRADIUS, KIND_GLYPHS } from './glyphs'

// The irrigation systems on the overview map, in the system color (never a
// status: that's the outlined fields' fill and the markers' badges). One threshold, FAR_ZOOM, where
// the markers turn to dots too (OverviewMap's data-far):
// - closer in, a system is its circle and a linear its rectangle at their true size, badges on top
//   (over the edge of a small one); a point kind (traveler, solid set, drip, location) is its kind's
//   glyph, or the area around its outlined fields drawn like a system's circle
// - farther out, every system is its glyph, ringing the one dot its marker becomes
// Glyphs are a fixed size in pixels, never depending on the zoom: MapLibre works out a symbol's
// zoom-dependent size per tile, so it jumped as tiles loaded after a zoom. Layers start and stop at
// the threshold (minzoom, maxzoom) rather than fading.

export const SYSTEM_LAYER = 'systems-fill'
/** A point kind's glyph closer in */
export const GLYPH_LAYER = 'systems-glyph'
/** Every system's glyph farther out */
export const FAR_GLYPH_LAYER = 'systems-glyph-far'
export const FIELD_LAYER = 'fields-fill'

/** The systems' source and layers (addSystemLayers), bottom to top */
export const SYSTEM_IDS = {
  source: 'systems',
  fill: SYSTEM_LAYER,
  casing: 'systems-casing',
  selected: 'systems-selected',
  line: 'systems-line',
  center: 'systems-center',
  glyphSelected: 'systems-glyph-selected',
  glyph: GLYPH_LAYER,
  farGlyphSelected: 'systems-glyph-far-selected',
  farGlyph: FAR_GLYPH_LAYER,
} as const
/** The irrigation groups' source and layers (OverviewMap) */
export const GROUP_IDS = {
  source: 'groups',
  fill: 'groups-fill',
  casing: 'groups-casing',
  line: 'groups-line',
  label: 'groups-label',
} as const
/** The outlined fields' source and layers (OverviewMap) */
export const FIELD_IDS = {
  source: 'fields',
  fill: FIELD_LAYER,
  casing: 'fields-casing',
  line: 'fields-line',
  label: 'fields-label',
} as const
/** The sources of the systems, groups and fields */
export const SYSTEM_SOURCES: string[] = [SYSTEM_IDS.source, GROUP_IDS.source, FIELD_IDS.source]

/** The systems' own layers, which the Irrigation systems layer switch shows and hides */
export const SYSTEM_LAYERS: string[] = Object.values(SYSTEM_IDS).filter((id) => id !== SYSTEM_IDS.source)

/** Below this zoom every system is its glyph and its marker one dot (OverviewMap's data-far) */
export const FAR_ZOOM = 11.5
/** The white backing under the selected glyph, this many times its size */
const SELECTED_BACKING_SCALE = 1.25
/** A point kind's glyph is never smaller than this */
export const MIN_POINT_PX = 16
// The glyph images: 128 px with a 16 px margin for the distance field, at pixel ratio 4, so the
// shape is GLYPH_PX (24) CSS pixels across at icon-size 1 and its edges stay smooth drawn large
const IMAGE_PX = 128
const MARGIN_PX = 16
const PIXEL_RATIO = 4
const GLYPH_PX = (IMAGE_PX - 2 * MARGIN_PX) / PIXEL_RATIO

export type GlyphProperties = {
  glyph: Glyph
  /** A point kind without outlined fields: its glyph closer in too */
  point: boolean
  /** A linear's direction of travel, which its glyph is turned to */
  rotate: number
  /** Pixels across closer in (a point kind's, enclosing its marker's badges) */
  near_px: number
  /** Pixels across farther out, ringing its marker's dot */
  far_px: number
}

// A marker's badges (BadgeRows): 20 px each, 2 px apart, on a backing 2 px wider all round
const BADGE_PX = 20
const BADGE_GAP_PX = 2
const BADGE_PAD_PX = 2

/**
 * Pixels across a glyph must be to enclose a marker's rows of badges: the circle around them (or
 * around the one round badge) inside the glyph's inscribed circle, with a few pixels to spare
 */
export function badgeFit(glyph: Glyph, rows: number[]): number {
  if (!rows.length) return 0
  const columns = Math.max(...rows)
  const across = (n: number) => n * BADGE_PX + (n - 1) * BADGE_GAP_PX + 2 * BADGE_PAD_PX
  const radius =
    rows.length === 1 && columns === 1 ? across(1) / 2 : Math.hypot(across(columns), across(rows.length)) / 2
  return Math.ceil((radius + 3) / GLYPH_INRADIUS[glyph])
}

/**
 * A system's glyph and its sizes. badgeRows: its marker's rows of badges closer in, which a point
 * kind's glyph encloses. outlined: a point kind whose fields have outlines, drawn closer in as the
 * area around them instead.
 */
export function glyphProperties(shape: SystemShape, badgeRows: number[] = [], outlined = false): GlyphProperties {
  const glyph = KIND_GLYPHS[shape.kind]
  return {
    glyph,
    point: isPoint(shape.kind) && !outlined,
    rotate: shape.kind === 'linear' ? linearOf(shape).bearingDeg : 0,
    near_px: Math.max(MIN_POINT_PX, badgeFit(glyph, badgeRows)),
    far_px: badgeFit(glyph, [1]),
  }
}

const POLYGONS: ExpressionSpecification = ['==', ['geometry-type'], 'Polygon']
const POINTS: ExpressionSpecification = ['==', ['geometry-type'], 'Point']
const SELECTED: ExpressionSpecification = ['get', 'selected']

/** A glyph's layout at its size (a property in pixels), the selected one's backing `scale` times that */
const glyphLayout = (sizeProperty: 'near_px' | 'far_px', scale = 1): SymbolLayerSpecification['layout'] => ({
  'icon-image': ['get', 'glyph'],
  'icon-size': ['/', ['*', ['get', sizeProperty], scale], GLYPH_PX],
  'icon-rotate': ['get', 'rotate'],
  'icon-rotation-alignment': 'map',
  'icon-allow-overlap': true,
  'icon-ignore-placement': true,
})

/** The systems' layers, from a source of their outlines and glyph points (systemFeatures) */
export function addSystemLayers(map: MapLibreMap, data: GeoJSONSourceSpecification['data'], palette: Palette) {
  addGlyphImages(map)
  map.addSource(SYSTEM_IDS.source, { type: 'geojson', data })
  const near = { minzoom: FAR_ZOOM }
  map.addLayer({
    id: SYSTEM_LAYER,
    type: 'fill',
    source: SYSTEM_IDS.source,
    filter: POLYGONS,
    ...near,
    paint: {
      'fill-color': palette.system,
      // A system whose fields have outlines leaves the area to them
      'fill-opacity': ['case', ['get', 'outlined'], 0, ['get', 'dimmed'], 0.04, SELECTED, 0.3, 0.15],
    },
  })
  // A dark casing under the line keeps it visible on the light streets map; on imagery the light
  // cyan carries it. The selected system's line sits on a thin white band with a thin dark edge, as
  // the selected glyph does, so it stands out on either basemap without swamping a small system.
  map.addLayer({
    id: SYSTEM_IDS.casing,
    type: 'line',
    source: SYSTEM_IDS.source,
    filter: POLYGONS,
    ...near,
    paint: {
      'line-color': palette.systemCasing,
      'line-width': ['case', SELECTED, 7, 4],
      'line-opacity': ['case', ['get', 'dimmed'], 0.25, SELECTED, 0.9, 0.7],
    },
  })
  map.addLayer({
    id: SYSTEM_IDS.selected,
    type: 'line',
    source: SYSTEM_IDS.source,
    filter: ['all', POLYGONS, SELECTED],
    ...near,
    paint: { 'line-color': '#ffffff', 'line-width': 5 },
  })
  map.addLayer({
    id: SYSTEM_IDS.line,
    type: 'line',
    source: SYSTEM_IDS.source,
    filter: POLYGONS,
    ...near,
    paint: {
      'line-color': palette.system,
      'line-width': ['case', SELECTED, 2.5, 2],
      'line-opacity': ['case', ['get', 'dimmed'], 0.35, 1],
    },
  })
  // A system's or linear's center, where its machine turns or the middle of its run
  map.addLayer({
    id: SYSTEM_IDS.center,
    type: 'circle',
    source: SYSTEM_IDS.source,
    filter: ['all', POINTS, ['!', ['get', 'point']]],
    ...near,
    paint: {
      'circle-color': palette.system,
      'circle-radius': ['case', SELECTED, 4.5, 3],
      'circle-stroke-color': ['case', SELECTED, '#ffffff', palette.systemCasing],
      'circle-stroke-width': ['case', SELECTED, 2, 1.5],
      'circle-opacity': ['case', ['get', 'dimmed'], 0.35, 1],
      'circle-stroke-opacity': ['case', ['get', 'dimmed'], 0.35, 1],
    },
  })
  // Glyphs: a point kind's closer in, every system's farther out. The selected one sits on a slightly
  // larger white copy of itself, each with a thin dark edge.
  const glyphs: {
    id: string
    selected: string
    filter: ExpressionSpecification
    size: 'near_px' | 'far_px'
    zooms: { minzoom?: number; maxzoom?: number }
  }[] = [
    {
      id: GLYPH_LAYER,
      selected: SYSTEM_IDS.glyphSelected,
      filter: ['all', POINTS, ['get', 'point']],
      size: 'near_px',
      zooms: near,
    },
    {
      id: FAR_GLYPH_LAYER,
      selected: SYSTEM_IDS.farGlyphSelected,
      filter: POINTS,
      size: 'far_px',
      zooms: { maxzoom: FAR_ZOOM },
    },
  ]
  for (const { id, selected, filter, size, zooms } of glyphs) {
    map.addLayer({
      id: selected,
      type: 'symbol',
      source: SYSTEM_IDS.source,
      filter: ['all', filter, SELECTED],
      ...zooms,
      layout: glyphLayout(size, SELECTED_BACKING_SCALE),
      paint: { 'icon-color': '#ffffff', 'icon-halo-color': palette.systemCasing, 'icon-halo-width': 1 },
    })
    map.addLayer({
      id,
      type: 'symbol',
      source: SYSTEM_IDS.source,
      filter,
      ...zooms,
      layout: glyphLayout(size),
      paint: {
        'icon-color': palette.system,
        'icon-opacity': ['case', ['get', 'dimmed'], 0.3, SELECTED, 1, 0.85],
        'icon-halo-color': palette.systemCasing,
        'icon-halo-width': 1.5,
      },
    })
  }
}

/** The system color after a theme change */
export function setSystemColors(map: MapLibreMap, palette: Palette) {
  if (!map.getLayer(SYSTEM_LAYER)) return
  map.setPaintProperty(SYSTEM_LAYER, 'fill-color', palette.system)
  map.setPaintProperty(SYSTEM_IDS.casing, 'line-color', palette.systemCasing)
  map.setPaintProperty(SYSTEM_IDS.line, 'line-color', palette.system)
  for (const layer of [GLYPH_LAYER, FAR_GLYPH_LAYER]) {
    map.setPaintProperty(layer, 'icon-color', palette.system)
    map.setPaintProperty(layer, 'icon-halo-color', palette.systemCasing)
  }
  for (const layer of [SYSTEM_IDS.glyphSelected, SYSTEM_IDS.farGlyphSelected])
    map.setPaintProperty(layer, 'icon-halo-color', palette.systemCasing)
  map.setPaintProperty(SYSTEM_IDS.center, 'circle-color', palette.system)
  map.setPaintProperty(SYSTEM_IDS.center, 'circle-stroke-color', ['case', SELECTED, '#ffffff', palette.systemCasing])
  if (map.getLayer(GROUP_IDS.line)) {
    map.setPaintProperty(GROUP_IDS.line, 'line-color', palette.system)
    map.setPaintProperty(GROUP_IDS.casing, 'line-color', palette.systemCasing)
    map.setPaintProperty(GROUP_IDS.label, 'text-color', palette.system)
    map.setPaintProperty(GROUP_IDS.label, 'text-halo-color', palette.systemCasing)
  }
}

/** The outlined fields' color after a theme change */
export function setFieldColors(map: MapLibreMap, palette: Palette) {
  if (!map.getLayer(FIELD_IDS.fill)) return
  map.setPaintProperty(FIELD_IDS.fill, 'fill-color', palette.field)
  map.setPaintProperty(FIELD_IDS.casing, 'line-color', palette.fieldCasing)
  map.setPaintProperty(FIELD_IDS.line, 'line-color', palette.field)
}

/**
 * The glyphs as signed distance field icons, so they take the system color and a halo: each pixel's
 * alpha from its exact distance to the glyph's edges (MapLibre's SDF edge is alpha 0.75, falling off
 * over the margin), so edges stay straight and smooth however large a glyph is drawn. Added once per
 * style; a basemap change drops them, and styleimagemissing adds them back.
 */
export function addGlyphImages(map: MapLibreMap) {
  for (const glyph of Object.keys(GLYPH_CORNERS) as Glyph[]) {
    if (!map.hasImage(glyph)) map.addImage(glyph, glyphImage(glyph), { sdf: true, pixelRatio: PIXEL_RATIO })
  }
}

const images = new Map<Glyph, { width: number; height: number; data: Uint8Array }>()

function glyphImage(glyph: Glyph) {
  const cached = images.get(glyph)
  if (cached) return cached
  // The corners in image pixels
  const scale = (IMAGE_PX - 2 * MARGIN_PX) / 24
  const corners = GLYPH_CORNERS[glyph].map(
    ([x, y]) => [MARGIN_PX + x * scale, MARGIN_PX + y * scale] as [number, number],
  )
  const inside = ([x, y]: [number, number]) => {
    let odd = false
    for (let i = 0, j = corners.length - 1; i < corners.length; j = i++) {
      const [xi, yi] = corners[i]
      const [xj, yj] = corners[j]
      if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) odd = !odd
    }
    return odd
  }
  const data = new Uint8Array(IMAGE_PX * IMAGE_PX * 4)
  for (let y = 0; y < IMAGE_PX; y++)
    for (let x = 0; x < IMAGE_PX; x++) {
      const at: [number, number] = [x + 0.5, y + 0.5]
      let nearest = Infinity
      for (let i = 0; i < corners.length; i++)
        nearest = Math.min(nearest, segmentDistance(at, corners[i], corners[(i + 1) % corners.length]))
      const outside = inside(at) ? -nearest : nearest
      data[(y * IMAGE_PX + x) * 4 + 3] = Math.max(0, Math.min(255, Math.round(255 * (0.75 - outside / MARGIN_PX))))
    }
  const image = { width: IMAGE_PX, height: IMAGE_PX, data }
  images.set(glyph, image)
  return image
}

/** What a click selects */
export type SystemHit = { kind: 'field'; systemId: number; fieldId: number } | { kind: 'system'; systemId: number }

/** The features of these layers at a point, among those shown (each layer draws only at its zooms) */
function featuresAt(map: MapLibreMap, point: PointLike, layers: string[]) {
  const shown = layers.filter((layer) => map.getLayer(layer) && map.getLayoutProperty(layer, 'visibility') !== 'none')
  return shown.length ? map.queryRenderedFeatures(point, { layers: shown }) : []
}

const SYSTEM_HIT_LAYERS = [GLYPH_LAYER, FAR_GLYPH_LAYER, SYSTEM_LAYER]

/**
 * What a click at a point selects, asking each kind of layer in priority order (a field's outline,
 * then a system's glyph or shape) rather than taking the top-most rendered feature, which would be
 * a system's fill drawn over its fields even where it's transparent. Null for none.
 */
export function systemHit(map: MapLibreMap, point: PointLike): SystemHit | null {
  const [field] = featuresAt(map, point, [FIELD_LAYER])
  if (field) {
    return { kind: 'field', systemId: Number(field.properties.system_id), fieldId: Number(field.properties.id) }
  }
  const [system] = featuresAt(map, point, SYSTEM_HIT_LAYERS)
  return system ? { kind: 'system', systemId: Number(system.properties.id) } : null
}

/**
 * What's under the pointer, down the stack: the irrigation groups, the systems and the
 * fields, each a line ("System: Home pivot", "Field: North potatoes"), all that are there: glyphs
 * drawn larger than their systems overlap where the systems don't
 */
export function hoverLines(map: MapLibreMap, point: PointLike): string[] {
  const lines = (prefix: string, layers: string[], key: string) =>
    featuresAt(map, point, layers).map((feature) => `${prefix}: ${feature.properties[key]}`)
  return [
    ...new Set([
      ...lines('Group', [GROUP_IDS.fill], 'name'),
      ...lines('System', SYSTEM_HIT_LAYERS, 'label'),
      ...lines('Field', [FIELD_LAYER], 'name'),
    ]),
  ]
}
