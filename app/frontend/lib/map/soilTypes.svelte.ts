import type { GeoJSONSource, Map as MapLibreMap } from 'maplibre-gl'

import { LABEL_FONT } from '@/lib/map/basemaps'
import { type Bounds, fetchSoilAreas, SOIL_COLORS, type SoilAreas } from '@/lib/soils'

// The Soil types layer (PLAN.md Phase 7 F; the pivot picker and the field shape page): the soil
// survey's map units colored and labeled by the WISP soil type their surface texture suggests,
// loaded for an area the map gives (around its pivot, or the view zoomed in) and again when the area
// moves out of what's loaded. Its source is 'soil-types' (keep it across basemap switches).

export const SOIL_SOURCE = 'soil-types'
const LAYERS = ['soil-types-label', 'soil-types-line', 'soil-types-fill']
/** Below this zoom the view is too large to ask the survey for */
export const SOIL_ZOOM = 13

type Named = { key: string; name: string }

export class SoilTypesLayer {
  on = $state(false)
  status = $state<'loading' | 'ready' | 'error' | 'zoom'>('zoom')
  /** The soil types in what's loaded */
  keys = $state<string[]>([])
  hover = $state<{ x: number; y: number; type: string; unit: string } | null>(null)

  #map: MapLibreMap | undefined
  #box: Bounds | null = null
  #request: AbortController | undefined

  /**
   * @param soilTypes names for the legend and labels
   * @param area what to load, or null when there's nothing to show (zoomed out)
   * @param below the layer to draw under, if it's on the map
   */
  constructor(
    private soilTypes: () => Named[],
    private area: (map: MapLibreMap) => Bounds | null,
    private below?: string,
  ) {}

  /** Start following the map (once it's loaded) */
  attach(map: MapLibreMap) {
    this.#map = map
    map.on('moveend', () => this.load())
    map.on('mousemove', 'soil-types-fill', (event) => {
      const feature = event.features?.[0]
      if (!feature) return
      this.hover = {
        x: event.point.x,
        y: event.point.y,
        type: String(feature.properties.name),
        unit: String(feature.properties.unit),
      }
    })
    map.on('mouseleave', 'soil-types-fill', () => (this.hover = null))
  }

  toggle() {
    this.on = !this.on
    if (this.on) this.load()
    else this.#hide()
  }

  /** Load the area if it's moved out of what's loaded */
  load() {
    const map = this.#map
    if (!map || !this.on) return
    const area = this.area(map)
    if (!area) {
      this.status = this.#box ? this.status : 'zoom'
      return
    }
    if (this.#box && covers(this.#box, area)) return
    this.#request?.abort()
    const request = (this.#request = new AbortController())
    this.status = 'loading'
    fetchSoilAreas(area, request.signal)
      .then((areas) => {
        if (request !== this.#request || !this.#map) return
        this.#box = area
        this.#show(this.#map, areas)
        const keys = areas.features.map((f) => f.properties.key).filter((key) => key !== null)
        this.keys = keys.filter((key, i) => keys.indexOf(key) === i)
        this.status = 'ready'
      })
      .catch((error: Error) => {
        if (error.name !== 'AbortError' && request === this.#request) this.status = 'error'
      })
  }

  /** A soil type's name ("No soil type" for a map unit that matched none) */
  name = (key: string | null) =>
    key ? (this.soilTypes().find((type) => type.key === key)?.name ?? key.replace(/_/g, ' ')) : 'No soil type'

  #show(map: MapLibreMap, areas: SoilAreas) {
    const data = {
      ...areas,
      features: areas.features.map((f) => ({
        ...f,
        properties: { ...f.properties, name: this.name(f.properties.key) },
      })),
    }
    const source = map.getSource<GeoJSONSource>(SOIL_SOURCE)
    if (source) return source.setData(data as never)
    map.addSource(SOIL_SOURCE, {
      type: 'geojson',
      data: data as never,
      attribution: 'Soils: <a href="https://websoilsurvey.nrcs.usda.gov/">USDA NRCS</a>',
    })
    const color = ['match', ['get', 'key'], ...Object.entries(SOIL_COLORS).flat(), '#9ca3af']
    const below = this.below && map.getLayer(this.below) ? this.below : undefined
    map.addLayer(
      {
        id: 'soil-types-fill',
        type: 'fill',
        source: SOIL_SOURCE,
        paint: { 'fill-color': color as never, 'fill-opacity': 0.55 },
      },
      below,
    )
    map.addLayer(
      {
        id: 'soil-types-line',
        type: 'line',
        source: SOIL_SOURCE,
        paint: { 'line-color': '#ffffff', 'line-width': 0.8, 'line-opacity': 0.7 },
      },
      below,
    )
    map.addLayer(
      {
        id: 'soil-types-label',
        type: 'symbol',
        source: SOIL_SOURCE,
        minzoom: 14,
        layout: { 'text-field': ['get', 'name'], 'text-size': 11, 'text-font': LABEL_FONT },
        paint: { 'text-color': '#ffffff', 'text-halo-color': '#000000', 'text-halo-width': 1.2 },
      },
      below,
    )
  }

  #hide() {
    this.#request?.abort()
    this.#box = null
    this.hover = null
    const map = this.#map
    for (const layer of LAYERS) if (map?.getLayer(layer)) map.removeLayer(layer)
    if (map?.getSource(SOIL_SOURCE)) map.removeSource(SOIL_SOURCE)
  }
}

const covers = ([west, south, east, north]: Bounds, area: Bounds) =>
  area[0] >= west && area[1] >= south && area[2] <= east && area[3] <= north

/** The view with half its size again on each side, once zoomed in to SOIL_ZOOM (else null) */
export function viewArea(map: MapLibreMap): Bounds | null {
  if (map.getZoom() < SOIL_ZOOM) return null
  const view = map.getBounds()
  const [west, south, east, north] = [view.getWest(), view.getSouth(), view.getEast(), view.getNorth()]
  const [dx, dy] = [(east - west) / 2, (north - south) / 2]
  return [west - dx, south - dy, east + dx, north + dy]
}
