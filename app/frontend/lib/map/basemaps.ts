import type { LayerSpecification, Map as MapLibreMap, StyleSpecification } from 'maplibre-gl'

// The two basemaps: USGS National Map imagery with roads, boundaries and place names (public
// domain), or OpenFreeMap streets

export type Basemap = 'imagery' | 'streets'

export const BASEMAPS: { key: Basemap; name: string }[] = [
  { key: 'imagery', name: 'Satellite' },
  { key: 'streets', name: 'Map' },
]

const IMAGERY: StyleSpecification = {
  version: 8,
  glyphs: 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
  sources: {
    imagery: {
      type: 'raster',
      tiles: ['https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryTopo/MapServer/tile/{z}/{y}/{x}'],
      tileSize: 256,
      maxzoom: 16,
      attribution: 'Imagery: <a href="https://www.usgs.gov/programs/national-geospatial-program/national-map">USGS</a>',
    },
  },
  layers: [{ id: 'imagery', type: 'raster', source: 'imagery' }],
}
const STREETS = 'https://tiles.openfreemap.org/styles/liberty'

/** The font our labels use; both basemaps serve it */
export const LABEL_FONT = ['Noto Sans Regular']

export const basemapStyle = (basemap: Basemap): StyleSpecification | string =>
  basemap === 'imagery' ? IMAGERY : STREETS

// Each map's switches run one at a time (a fast second click would otherwise start a style while the
// last is loading, and the two resolve out of order): what each map was last asked for, what it shows,
// and the switch in progress
const wanted = new WeakMap<MapLibreMap, Basemap>()
const shown = new WeakMap<MapLibreMap, Basemap>()
const running = new WeakMap<MapLibreMap, Promise<unknown>>()

/**
 * Changes the basemap. A new style replaces every source and layer, so ours (the sources isOwn
 * picks, and the layers drawing them, in their order) are copied into it. `before` and `after` run
 * around the switch itself (terra-draw stops and starts there). Switches on one map run in turn, and
 * one a later call has replaced is skipped (resolving false). Resolves true once the new style is
 * in place, before its tiles load.
 */
export function setBasemap(
  map: MapLibreMap,
  basemap: Basemap,
  isOwn: (sourceId: string) => boolean,
  { before, after }: { before?: () => void; after?: () => void } = {},
): Promise<boolean> {
  wanted.set(map, basemap)
  const run = (running.get(map) ?? Promise.resolve()).then(async () => {
    if (wanted.get(map) !== basemap || shown.get(map) === basemap) return false
    before?.()
    const loaded = new Promise<void>((resolve) => map.once('style.load', () => resolve()))
    // Rebuilt rather than diffed, so 'style.load' fires (a diff applies silently)
    map.setStyle(basemapStyle(basemap), {
      diff: false,
      transformStyle: (previous, next) => {
        if (!previous) return next
        const own = Object.keys(previous.sources).filter(isOwn)
        return {
          ...next,
          sources: { ...next.sources, ...Object.fromEntries(own.map((id) => [id, previous.sources[id]])) },
          layers: [
            ...next.layers,
            ...previous.layers.filter(
              (layer: LayerSpecification) => 'source' in layer && own.includes(layer.source as string),
            ),
          ],
        }
      },
    })
    await loaded
    shown.set(map, basemap)
    after?.()
    return true
  })
  running.set(map, run)
  return run
}
