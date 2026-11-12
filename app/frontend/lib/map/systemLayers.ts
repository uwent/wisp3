import type {
  ExpressionSpecification,
  GeoJSONSourceSpecification,
  Map as MapLibreMap,
  MapGeoJSONFeature,
  PointLike,
} from 'maplibre-gl'

import type { Palette } from '@/lib/charts/palette'
import { DEFAULT_RADIUS_FT, FEET_PER_METER, isPoint, linearOf, type PivotShape } from '@/lib/geo'

import { type Glyph, GLYPH_PATHS, KIND_GLYPHS } from './glyphs'

// The irrigation systems on the overview map (PLAN.md Phase 8 G.14), in the system color (never a
// status: that's the outlined fields' fill and the markers' badges). A pivot is its circle and a
// linear its rectangle, at their true size; a point kind (traveler, solid set, drip, location) is
// its kind's glyph about 100 ft across on the ground. Zoomed out, where a pivot or linear would be
// under MIN_SHAPE_PX across, it's drawn as its glyph at that size instead, and a point kind's glyph
// keeps MIN_POINT_PX. MapLibre allows the zoom only as the input of a top-level interpolate, so the
// sizes and the switch between shape and glyph are interpolated over stops at each whole zoom, each
// stop's output computed per system from its true size (`k`).

export const PIVOT_LAYER = 'pivots-fill'
/** Every system's glyph: point kinds always, pivots and linears when they're small */
export const GLYPH_LAYER = 'pivots-glyph'
export const FIELD_LAYER = 'fields-fill'
export const PIN_LAYER = 'pins'
/** The systems' own layers, which the Irrigation systems layer switch shows and hides */
export const SYSTEM_LAYERS = [PIVOT_LAYER, 'pivots-casing', 'pivots-line', GLYPH_LAYER]

/** Below this many pixels across, a pivot or linear is drawn as its glyph */
export const MIN_SHAPE_PX = 16
/** A point kind's glyph is never smaller than this */
export const MIN_POINT_PX = 10
/** A point kind's glyph on the ground: about 50 ft in radius */
export const POINT_SIZE_M = 100 / FEET_PER_METER
// MapLibre's world is 512 px across at zoom 0
const METERS_PER_PX_AT_ZOOM_0 = 40_075_016.686 / 512
// The glyph images: 64 px with an 8 px margin for the distance field, at pixel ratio 2, so the
// shape is GLYPH_PX (24) CSS pixels across at icon-size 1
const IMAGE_PX = 64
const MARGIN_PX = 8
const PIXEL_RATIO = 2
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
}

/** The icon-size at zoom 0 that draws something sizeM across at its true size at a latitude */
export const glyphScale = (sizeM: number, latitude: number) =>
  sizeM / (METERS_PER_PX_AT_ZOOM_0 * Math.cos((latitude * Math.PI) / 180) * GLYPH_PX)

/** Pixels across a system's true size is at a zoom */
export const truePixels = (k: number, zoom: number) => k * GLYPH_PX * 2 ** zoom

/** A system's glyph, its scale and turn */
export function glyphProperties(shape: PivotShape): GlyphProperties {
  const point = isPoint(shape.kind)
  const linear = shape.kind === 'linear' ? linearOf(shape) : null
  const sizeFt = point
    ? null
    : linear
      ? Math.max(linear.lengthFt, linear.travelFt)
      : 2 * (shape.radius_ft ?? DEFAULT_RADIUS_FT)
  return {
    glyph: KIND_GLYPHS[shape.kind],
    point,
    k: glyphScale(sizeFt === null ? POINT_SIZE_M : sizeFt / FEET_PER_METER, shape.latitude),
    rotate: linear?.bearingDeg ?? 0,
  }
}

/** Whether a system is drawn as its glyph at a zoom: a point kind, or a pivot or linear too small to see */
export const drawnAsGlyph = (properties: Pick<GlyphProperties, 'point' | 'k'>, zoom: number) =>
  properties.point || truePixels(properties.k, zoom) < MIN_SHAPE_PX

// The same test as an expression at one whole zoom
const asGlyph = (zoom: number): ExpressionSpecification => [
  'any',
  ['get', 'point'],
  ['<', ['*', ['get', 'k'], GLYPH_PX * 2 ** zoom], MIN_SHAPE_PX],
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
  // cyan carries it
  map.addLayer({
    id: 'pivots-casing',
    type: 'line',
    source: 'pivots',
    filter: POLYGONS,
    paint: {
      'line-color': palette.systemCasing,
      'line-width': ['case', ['get', 'selected'], 6.5, 4],
      'line-opacity': shapeOnly(['case', ['get', 'dimmed'], 0.25, 0.7]),
    },
  })
  map.addLayer({
    id: 'pivots-line',
    type: 'line',
    source: 'pivots',
    filter: POLYGONS,
    paint: {
      'line-color': palette.system,
      'line-width': ['case', ['get', 'selected'], 3.5, 2],
      'line-opacity': shapeOnly(['case', ['get', 'dimmed'], 0.35, 1]),
    },
  })
  map.addLayer({
    id: GLYPH_LAYER,
    type: 'symbol',
    source: 'pivots',
    filter: ['==', ['geometry-type'], 'Point'],
    layout: {
      'icon-image': ['get', 'glyph'],
      'icon-size': byZoom(
        (zoom) => [
          'max',
          ['case', ['get', 'point'], MIN_POINT_PX / GLYPH_PX, MIN_SHAPE_PX / GLYPH_PX],
          ['*', ['get', 'k'], 2 ** zoom],
        ],
        true,
      ),
      'icon-rotate': ['get', 'rotate'],
      'icon-rotation-alignment': 'map',
      'icon-allow-overlap': true,
      'icon-ignore-placement': true,
    },
    paint: {
      'icon-color': palette.system,
      'icon-opacity': byZoom((zoom) => [
        'case',
        asGlyph(zoom),
        ['case', ['get', 'dimmed'], 0.3, ['get', 'selected'], 1, 0.85],
        0,
      ]),
      'icon-halo-color': palette.systemCasing,
      'icon-halo-width': ['case', ['get', 'selected'], 2.5, 1.5],
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
}

/**
 * The glyphs as signed distance field icons, so they take the system color and a halo: drawn on a
 * canvas, then each pixel's alpha set from its distance to the shape's edge (MapLibre's SDF edge is
 * alpha 0.75, falling off over the margin). Added once per style; a basemap change drops them, and
 * styleimagemissing adds them back.
 */
export function addGlyphImages(map: MapLibreMap) {
  for (const glyph of Object.keys(GLYPH_PATHS) as Glyph[]) {
    if (!map.hasImage(glyph)) map.addImage(glyph, glyphImage(glyph), { sdf: true, pixelRatio: PIXEL_RATIO })
  }
}

const images = new Map<Glyph, { width: number; height: number; data: Uint8Array }>()

function glyphImage(glyph: Glyph) {
  const cached = images.get(glyph)
  if (cached) return cached
  const canvas = document.createElement('canvas')
  canvas.width = canvas.height = IMAGE_PX
  const context = canvas.getContext('2d')!
  context.translate(MARGIN_PX, MARGIN_PX)
  context.scale((IMAGE_PX - 2 * MARGIN_PX) / 24, (IMAGE_PX - 2 * MARGIN_PX) / 24)
  context.fill(new Path2D(GLYPH_PATHS[glyph]))
  const pixels = context.getImageData(0, 0, IMAGE_PX, IMAGE_PX).data
  const inside = (x: number, y: number) => pixels[(y * IMAGE_PX + x) * 4 + 3] > 127
  // The edge: pixels whose neighbor across is on the other side
  const edge: [number, number][] = []
  for (let y = 0; y < IMAGE_PX; y++)
    for (let x = 0; x < IMAGE_PX; x++) {
      const here = inside(x, y)
      if ((x + 1 < IMAGE_PX && inside(x + 1, y) !== here) || (y + 1 < IMAGE_PX && inside(x, y + 1) !== here))
        edge.push([x + 0.5, y + 0.5])
    }
  const data = new Uint8Array(IMAGE_PX * IMAGE_PX * 4)
  for (let y = 0; y < IMAGE_PX; y++)
    for (let x = 0; x < IMAGE_PX; x++) {
      let nearest = Infinity
      for (const [ex, ey] of edge) nearest = Math.min(nearest, (ex - x) ** 2 + (ey - y) ** 2)
      const outside = Math.sqrt(nearest) * (inside(x, y) ? -1 : 1)
      data[(y * IMAGE_PX + x) * 4 + 3] = Math.max(0, Math.min(255, Math.round(255 * (0.75 - outside / MARGIN_PX))))
    }
  const image = { width: IMAGE_PX, height: IMAGE_PX, data }
  images.set(glyph, image)
  return image
}

export type SystemHit =
  | { kind: 'pin'; pivotId: number; fieldId: number }
  | { kind: 'field'; pivotId: number; fieldId: number }
  | { kind: 'system'; pivotId: number }

/**
 * What a click at a point selects, asking each layer in priority order (a pin, a field's outline, a
 * system's glyph, a system's shape) rather than taking the top-most rendered feature, which would
 * be a system's fill drawn over its fields even where it's transparent. Glyphs and shapes count
 * only at zooms they're drawn at. Null for none.
 */
export function systemHit(map: MapLibreMap, point: PointLike): SystemHit | null {
  const zoom = map.getZoom()
  const shown = (layer: string) => map.getLayer(layer) && map.getLayoutProperty(layer, 'visibility') !== 'none'
  const at = (layer: string, keep: (feature: MapGeoJSONFeature) => boolean = () => true) =>
    shown(layer) ? map.queryRenderedFeatures(point, { layers: [layer] }).find(keep) : undefined
  const glyph = (feature: MapGeoJSONFeature) =>
    drawnAsGlyph({ point: !!feature.properties.point, k: Number(feature.properties.k) }, zoom)

  const pin = at(PIN_LAYER)
  if (pin) return { kind: 'pin', pivotId: Number(pin.properties.pivot_id), fieldId: Number(pin.properties.field_id) }
  const field = at(FIELD_LAYER)
  if (field) return { kind: 'field', pivotId: Number(field.properties.pivot_id), fieldId: Number(field.properties.id) }
  const system = at(GLYPH_LAYER, glyph) ?? at(PIVOT_LAYER, (feature) => !glyph(feature))
  return system ? { kind: 'system', pivotId: Number(system.properties.id) } : null
}

/** The layers a click can select something on, for the pointer cursor */
export const CLICKABLE_LAYERS = [PIN_LAYER, FIELD_LAYER, GLYPH_LAYER, PIVOT_LAYER]
