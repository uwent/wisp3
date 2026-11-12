import type {
  ExpressionSpecification,
  GeoJSONSourceSpecification,
  Map as MapLibreMap,
  MapGeoJSONFeature,
  PointLike,
  SymbolLayerSpecification,
} from 'maplibre-gl'

import type { Palette } from '@/lib/charts/palette'
import { DEFAULT_RADIUS_FT, FEET_PER_METER, isPoint, linearOf, type PivotShape } from '@/lib/geo'

import { type Glyph, GLYPH_CORNERS, GLYPH_INRADIUS, KIND_GLYPHS, segmentDistance } from './glyphs'

// The irrigation systems on the overview map (PLAN.md Phase 8 G.14), in the system color (never a
// status: that's the outlined fields' fill and the markers' badges). A pivot is its circle and a
// linear its rectangle, at their true size; a point kind (traveler, solid set, drip, location) is
// its kind's glyph about 100 ft across on the ground. Zoomed out, where a pivot or linear would be
// under MIN_SHAPE_PX across, it's drawn as its glyph at that size instead, and a point kind's glyph
// keeps MIN_POINT_PX. MapLibre allows the zoom only as the input of a top-level interpolate, so the
// sizes and the switch between shape and glyph are interpolated over stops at each whole zoom, each
// stop's output computed per system from its true size (`k`). A glyph is never smaller than the
// badges its marker shows (`fit`, `fit_far` zoomed out): it encloses them.

export const PIVOT_LAYER = 'pivots-fill'
/** Every system's glyph: point kinds always, pivots and linears when they're small */
export const GLYPH_LAYER = 'pivots-glyph'
export const FIELD_LAYER = 'fields-fill'
/** The systems' own layers, which the Irrigation systems layer switch shows and hides */
export const SYSTEM_LAYERS = [
  PIVOT_LAYER,
  'pivots-casing',
  'pivots-selected',
  'pivots-line',
  'pivots-center',
  'pivots-glyph-selected',
  GLYPH_LAYER,
]

/** Below this many pixels across, a pivot or linear is drawn as its glyph */
export const MIN_SHAPE_PX = 16
/** A point kind's glyph is never smaller than this */
export const MIN_POINT_PX = 10
/** Below this zoom a system's marker is one dot (OverviewMap's data-far) */
export const FAR_ZOOM = 11.5
/** A point kind's glyph on the ground: about 50 ft in radius */
export const POINT_SIZE_M = 100 / FEET_PER_METER
// MapLibre's world is 512 px across at zoom 0
const METERS_PER_PX_AT_ZOOM_0 = 40_075_016.686 / 512
// The glyph images: 128 px with a 16 px margin for the distance field, at pixel ratio 4, so the
// shape is GLYPH_PX (24) CSS pixels across at icon-size 1 and its edges stay smooth drawn large
const IMAGE_PX = 128
const MARGIN_PX = 16
const PIXEL_RATIO = 4
const GLYPH_PX = (IMAGE_PX - 2 * MARGIN_PX) / PIXEL_RATIO
const ZOOMS = Array.from({ length: 23 }, (_, zoom) => zoom)

export type GlyphProperties = {
  glyph: Glyph
  /** A point kind: always its glyph */
  point: boolean
  /** The glyph's icon-size at zoom 0 for its true size; doubling with each zoom */
  k: number
  /** A linear's direction of travel, which its rectangle is turned to */
  rotate: number
  /** Pixels across the glyph needs to enclose its marker's badges (0: none), and zoomed out */
  fit: number
  fit_far: number
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

/** The icon-size at zoom 0 that draws something sizeM across at its true size at a latitude */
export const glyphScale = (sizeM: number, latitude: number) =>
  sizeM / (METERS_PER_PX_AT_ZOOM_0 * Math.cos((latitude * Math.PI) / 180) * GLYPH_PX)

/** Pixels across a system's true size is at a zoom */
export const truePixels = (k: number, zoom: number) => k * GLYPH_PX * 2 ** zoom

/**
 * A system's glyph, its scale and turn. badgeRows: its marker's rows of badges, which the glyph
 * encloses. outlineM: for a point kind whose fields have outlines, the size of the area drawn
 * around them (systemOutline), which it then has like a pivot's circle.
 */
export function glyphProperties(
  shape: PivotShape,
  badgeRows: number[] = [],
  outlineM: number | null = null,
): GlyphProperties {
  const linear = shape.kind === 'linear' ? linearOf(shape) : null
  const point = isPoint(shape.kind) && outlineM === null
  const sizeM =
    outlineM ??
    (point
      ? POINT_SIZE_M
      : (linear ? Math.max(linear.lengthFt, linear.travelFt) : 2 * (shape.radius_ft ?? DEFAULT_RADIUS_FT)) /
        FEET_PER_METER)
  const glyph = KIND_GLYPHS[shape.kind]
  return {
    glyph,
    point,
    k: glyphScale(sizeM, shape.latitude),
    rotate: linear?.bearingDeg ?? 0,
    fit: badgeFit(glyph, badgeRows),
    fit_far: badgeRows.length ? badgeFit(glyph, [1]) : 0,
  }
}

/** The pixels a glyph must enclose at a zoom (its badges', or one dot's zoomed out) */
const fitAt = (properties: Pick<GlyphProperties, 'fit' | 'fit_far'>, zoom: number) =>
  zoom < FAR_ZOOM ? properties.fit_far : properties.fit

/**
 * Whether a system is drawn as its glyph at a zoom: a point kind, or a pivot or linear (or a point
 * kind's outline) too small to see or to hold its badges
 */
export const drawnAsGlyph = (properties: Pick<GlyphProperties, 'point' | 'k' | 'fit' | 'fit_far'>, zoom: number) =>
  properties.point || truePixels(properties.k, zoom) < Math.max(MIN_SHAPE_PX, fitAt(properties, zoom))

const fitExpression = (zoom: number): ExpressionSpecification => ['get', zoom < FAR_ZOOM ? 'fit_far' : 'fit']

// The same test as an expression at one whole zoom
const asGlyph = (zoom: number): ExpressionSpecification => [
  'any',
  ['get', 'point'],
  ['<', ['*', ['get', 'k'], GLYPH_PX * 2 ** zoom], ['max', MIN_SHAPE_PX, fitExpression(zoom)]],
]

/** A property interpolated over the whole zooms, its value at each from output(zoom) */
function byZoom(output: (zoom: number) => ExpressionSpecification | number, exponential = false) {
  return [
    'interpolate',
    exponential ? ['exponential', 2] : ['linear'],
    ['zoom'],
    ...ZOOMS.flatMap((zoom) => [zoom, output(zoom)]),
  ] as unknown as ExpressionSpecification
}

/** A value for the shape (pivot or linear outline) that's 0 where the system is a glyph instead */
const shapeOnly = (value: ExpressionSpecification | number) =>
  byZoom((zoom) => ['case', asGlyph(zoom), 0, value] as ExpressionSpecification)

const POLYGONS: ExpressionSpecification = ['==', ['geometry-type'], 'Polygon']
const POINTS: ExpressionSpecification = ['==', ['geometry-type'], 'Point']
const SELECTED: ExpressionSpecification = ['get', 'selected']

/**
 * A glyph's icon-size: its true size, or the minimum or what encloses its badges if that's more,
 * the selected one `selectedScale` times that
 */
const glyphSize = (selectedScale: number) =>
  byZoom(
    (zoom) => [
      '*',
      ['case', SELECTED, selectedScale, 1],
      [
        'max',
        ['case', ['get', 'point'], MIN_POINT_PX / GLYPH_PX, MIN_SHAPE_PX / GLYPH_PX],
        ['/', fitExpression(zoom), GLYPH_PX],
        ['*', ['get', 'k'], 2 ** zoom],
      ],
    ],
    true,
  )
const glyphLayout = (selectedScale: number): SymbolLayerSpecification['layout'] => ({
  'icon-image': ['get', 'glyph'],
  'icon-size': glyphSize(selectedScale),
  'icon-rotate': ['get', 'rotate'],
  'icon-rotation-alignment': 'map',
  'icon-allow-overlap': true,
  'icon-ignore-placement': true,
})

/** The systems' layers, from a source of their outlines and glyph points (pivotFeatures) */
export function addSystemLayers(map: MapLibreMap, data: GeoJSONSourceSpecification['data'], palette: Palette) {
  addGlyphImages(map)
  map.addSource('pivots', { type: 'geojson', data })
  map.addLayer({
    id: PIVOT_LAYER,
    type: 'fill',
    source: 'pivots',
    filter: POLYGONS,
    paint: {
      'fill-color': palette.system,
      // A system whose fields have outlines leaves the area to them
      'fill-opacity': shapeOnly([
        'case',
        ['get', 'outlined'],
        0,
        ['get', 'dimmed'],
        0.04,
        ['get', 'selected'],
        0.3,
        0.15,
      ]),
    },
  })
  // A dark casing under the line keeps it visible on the light streets map; on imagery the light
  // cyan carries it. The selected system's line is thicker, on a white band inside a wider casing,
  // so it stands out on either basemap.
  map.addLayer({
    id: 'pivots-casing',
    type: 'line',
    source: 'pivots',
    filter: POLYGONS,
    paint: {
      'line-color': palette.systemCasing,
      'line-width': ['case', SELECTED, 11, 4],
      'line-opacity': shapeOnly(['case', ['get', 'dimmed'], 0.25, SELECTED, 0.9, 0.7]),
    },
  })
  map.addLayer({
    id: 'pivots-selected',
    type: 'line',
    source: 'pivots',
    filter: ['all', POLYGONS, SELECTED],
    paint: { 'line-color': '#ffffff', 'line-width': 7.5, 'line-opacity': shapeOnly(1) },
  })
  map.addLayer({
    id: 'pivots-line',
    type: 'line',
    source: 'pivots',
    filter: POLYGONS,
    paint: {
      'line-color': palette.system,
      'line-width': ['case', SELECTED, 4, 2],
      'line-opacity': shapeOnly(['case', ['get', 'dimmed'], 0.35, 1]),
    },
  })
  // A pivot's or linear's center, where its machine turns or the middle of its run
  map.addLayer({
    id: 'pivots-center',
    type: 'circle',
    source: 'pivots',
    filter: ['all', POINTS, ['!', ['get', 'point']]],
    paint: {
      'circle-color': palette.system,
      'circle-radius': ['case', SELECTED, 4.5, 3],
      'circle-stroke-color': ['case', SELECTED, '#ffffff', palette.systemCasing],
      'circle-stroke-width': ['case', SELECTED, 2, 1.5],
      'circle-opacity': shapeOnly(['case', ['get', 'dimmed'], 0.35, 1]),
      'circle-stroke-opacity': shapeOnly(['case', ['get', 'dimmed'], 0.35, 1]),
    },
  })
  // The selected glyph is half as large again, on a white copy of itself with a dark edge
  map.addLayer({
    id: 'pivots-glyph-selected',
    type: 'symbol',
    source: 'pivots',
    filter: ['all', POINTS, SELECTED],
    layout: glyphLayout(2.1),
    paint: {
      'icon-color': '#ffffff',
      'icon-opacity': byZoom((zoom) => ['case', asGlyph(zoom), 1, 0]),
      'icon-halo-color': palette.systemCasing,
      'icon-halo-width': 2,
    },
  })
  map.addLayer({
    id: GLYPH_LAYER,
    type: 'symbol',
    source: 'pivots',
    filter: POINTS,
    layout: glyphLayout(1.5),
    paint: {
      'icon-color': palette.system,
      'icon-opacity': byZoom((zoom) => ['case', asGlyph(zoom), ['case', ['get', 'dimmed'], 0.3, SELECTED, 1, 0.85], 0]),
      'icon-halo-color': palette.systemCasing,
      'icon-halo-width': ['case', SELECTED, 0, 1.5],
    },
  })
}

/** The system color after a theme change */
export function setSystemColors(map: MapLibreMap, palette: Palette) {
  if (!map.getLayer(PIVOT_LAYER)) return
  map.setPaintProperty(PIVOT_LAYER, 'fill-color', palette.system)
  map.setPaintProperty('pivots-casing', 'line-color', palette.systemCasing)
  map.setPaintProperty('pivots-line', 'line-color', palette.system)
  map.setPaintProperty(GLYPH_LAYER, 'icon-color', palette.system)
  map.setPaintProperty(GLYPH_LAYER, 'icon-halo-color', palette.systemCasing)
  map.setPaintProperty('pivots-glyph-selected', 'icon-halo-color', palette.systemCasing)
  map.setPaintProperty('pivots-center', 'circle-color', palette.system)
  map.setPaintProperty('pivots-center', 'circle-stroke-color', ['case', SELECTED, '#ffffff', palette.systemCasing])
  if (map.getLayer('groups-line')) {
    map.setPaintProperty('groups-line', 'line-color', palette.system)
    map.setPaintProperty('groups-casing', 'line-color', palette.systemCasing)
    map.setPaintProperty('groups-label', 'text-color', palette.system)
    map.setPaintProperty('groups-label', 'text-halo-color', palette.systemCasing)
  }
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
export type SystemHit = { kind: 'field'; pivotId: number; fieldId: number } | { kind: 'system'; pivotId: number }

/**
 * What a click at a point selects, asking each layer in priority order (a field's outline, a
 * system's glyph, a system's shape) rather than taking the top-most rendered feature, which would
 * be a system's fill drawn over its fields even where it's transparent. Glyphs and shapes count
 * only at zooms they're drawn at. Null for none.
 */
export function systemHit(map: MapLibreMap, point: PointLike): SystemHit | null {
  const zoom = map.getZoom()
  const shown = (layer: string) => map.getLayer(layer) && map.getLayoutProperty(layer, 'visibility') !== 'none'
  const at = (layer: string, keep: (feature: MapGeoJSONFeature) => boolean = () => true) =>
    shown(layer) ? map.queryRenderedFeatures(point, { layers: [layer] }).find(keep) : undefined
  const glyph = (feature: MapGeoJSONFeature) => drawnAsGlyph(glyphOf(feature), zoom)

  const field = at(FIELD_LAYER)
  if (field) {
    return { kind: 'field', pivotId: Number(field.properties.pivot_id), fieldId: Number(field.properties.id) }
  }
  const system = at(GLYPH_LAYER, glyph) ?? at(PIVOT_LAYER, (feature) => !glyph(feature))
  return system ? { kind: 'system', pivotId: Number(system.properties.id) } : null
}

const glyphOf = ({ properties }: MapGeoJSONFeature) => ({
  point: !!properties.point,
  k: Number(properties.k),
  fit: Number(properties.fit),
  fit_far: Number(properties.fit_far),
})

/**
 * What's under the pointer, down the stack (G.14): the irrigation group, the system and the field,
 * each a line ("System: Home pivot", "Field: North potatoes"), whichever are there
 */
export function hoverLines(map: MapLibreMap, point: PointLike): string[] {
  const zoom = map.getZoom()
  const shown = (layer: string) => map.getLayer(layer) && map.getLayoutProperty(layer, 'visibility') !== 'none'
  const at = (layer: string, keep: (feature: MapGeoJSONFeature) => boolean = () => true) =>
    shown(layer) ? map.queryRenderedFeatures(point, { layers: [layer] }).find(keep) : undefined
  const glyph = (feature: MapGeoJSONFeature) => drawnAsGlyph(glyphOf(feature), zoom)
  const group = at('groups-fill')
  const system = at(GLYPH_LAYER, glyph) ?? at(PIVOT_LAYER, (feature) => !glyph(feature))
  const field = at(FIELD_LAYER)
  return [
    ...(group ? [`Group: ${group.properties.name}`] : []),
    ...(system ? [`System: ${system.properties.label}`] : []),
    ...(field ? [`Field: ${field.properties.name}`] : []),
  ]
}
