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

/**
 * Changes the basemap. A new style replaces every source and layer, so ours (the sources isOwn
 * picks, and the layers drawing them, in their order) are copied into it. Resolves once the new
 * style has loaded.
 */
export function setBasemap(map: MapLibreMap, basemap: Basemap, isOwn: (sourceId: string) => boolean): Promise<void> {
  map.setStyle(basemapStyle(basemap), {
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
  return new Promise((resolve) => map.once('idle', () => resolve()))
}
