import { type LngLat, pointInPolygon } from '@/lib/geo'

// Optional public layers for the map (PLAN.md Phase 7 E), loaded by the browser from their
// providers, never by our server. Each can fail or be slow; the map marks a failing one
// unavailable and carries on.

export type OverlayId = 'radar' | 'rain24' | 'rain72' | 'qpf1' | 'qpf3' | 'qpf7' | 'drought' | 'soil'

export type Legend =
  /** A color ramp from light to heavy */
  | { kind: 'ramp'; colors: string[]; start: string; end: string }
  /** The provider's legend image */
  | { kind: 'image'; src: string; alt: string; inches: true }
  /** Colors at rain depths, labeled in the user's units */
  | { kind: 'depths'; items: { inches: number; color: string }[] }
  | { kind: 'classes'; items: { label: string; color: string }[] }
  | { kind: 'note'; text: string }

type Base = {
  id: OverlayId
  name: string
  description: string
  credit: { name: string; url: string }
  /** For the map's attribution control */
  attribution: string
  legend: Legend
  opacity: number
  /** How often to reload it while it's shown */
  refreshMinutes?: number
  /** Not drawn below this zoom (the provider refuses large areas) */
  minzoom?: number
  /** When the data is for, for the panel ("Radar at 3:20 PM") */
  time?: () => Promise<string | null>
}
export type RasterOverlay = Base & { kind: 'raster'; tiles: (stamp: number) => string[] }
export type VectorOverlay = Base & { kind: 'drought' }
export type Overlay = RasterOverlay | VectorOverlay

const IEM = 'https://mesonet.agron.iastate.edu'
const iemTiles = (layer: string) => (stamp: number) =>
  // The stamp makes a refresh fetch new tiles rather than the browser's cached ones
  [`${IEM}/cache/tile.py/1.0.0/${layer}/{z}/{x}/{y}.png?t=${stamp}`]
const IEM_CREDIT = { name: 'Iowa Environmental Mesonet', url: 'https://mesonet.agron.iastate.edu/ogc/' }
const IEM_ATTRIBUTION = 'Radar: <a href="https://mesonet.agron.iastate.edu/">Iowa Environmental Mesonet</a>, NOAA'

const WPC_QPF = 'https://mapservices.weather.noaa.gov/vector/rest/services/precip/wpc_qpf/MapServer'
/** WPC's quantitative precipitation forecast layers: day 1, days 1–3, days 1–7 */
export const QPF_LAYERS = { qpf1: 1, qpf3: 9, qpf7: 11 } as const
const qpfTiles = (layer: number) => (stamp: number) => [
  `${WPC_QPF}/export?bbox={bbox-epsg-3857}&bboxSR=3857&imageSR=3857&size=256,256&format=png32&transparent=true` +
    `&layers=show:${layer}&f=image&t=${stamp}`,
]
const WPC_CREDIT = { name: 'NOAA Weather Prediction Center', url: 'https://www.wpc.ncep.noaa.gov/qpf/qpf2.shtml' }
const WPC_ATTRIBUTION = 'Forecast rain: <a href="https://www.wpc.ncep.noaa.gov/">NOAA WPC</a>'
// WPC's own classes (inches), a subset for the legend
const QPF_LEGEND: Legend = {
  kind: 'depths',
  items: [
    { inches: 0.01, color: '#7fff00' },
    { inches: 0.1, color: '#00ff00' },
    { inches: 0.25, color: '#088b00' },
    { inches: 0.5, color: '#104e8b' },
    { inches: 0.75, color: '#1e90ff' },
    { inches: 1, color: '#00b2ee' },
    { inches: 1.5, color: '#8968cd' },
    { inches: 2, color: '#8b008b' },
    { inches: 3, color: '#ff0000' },
    { inches: 5, color: '#ff7f00' },
  ],
}

const USDM_QUERY =
  'https://services5.arcgis.com/0OTVzJS4K09zlixn/ArcGIS/rest/services/USDM_current/FeatureServer/0/query'

/** The Drought Monitor's categories and standard colors */
export const DROUGHT_CATEGORIES = [
  { dm: 0, label: 'D0 Abnormally dry', color: '#ffff00' },
  { dm: 1, label: 'D1 Moderate drought', color: '#fcd37f' },
  { dm: 2, label: 'D2 Severe drought', color: '#ffaa00' },
  { dm: 3, label: 'D3 Extreme drought', color: '#e60000' },
  { dm: 4, label: 'D4 Exceptional drought', color: '#730000' },
]

const SOIL_WMS =
  'https://SDMDataAccess.sc.egov.usda.gov/Spatial/SDM.wms?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap' +
  '&LAYERS=mapunitpoly&STYLES=&SRS=EPSG:3857&BBOX={bbox-epsg-3857}&WIDTH=256&HEIGHT=256&FORMAT=image/png&TRANSPARENT=true'

/** "Sat 3:20 PM" in the browser's time zone */
export function describeTime(date: Date): string {
  return date.toLocaleString('en-US', { weekday: 'short', hour: 'numeric', minute: '2-digit' })
}

/** WPC's issue_time ("2026-10-17 22:03:02", UTC) as a Date */
export const parseWpcTime = (value: string) => new Date(`${value.replace(' ', 'T')}Z`)

async function json(url: string) {
  const response = await fetch(url)
  if (!response.ok) throw new Error(`${response.status} from ${url}`)
  return response.json()
}

async function radarTime() {
  const data = await json(`${IEM}/data/gis/images/4326/USCOMP/n0q_0.json`)
  return data?.meta?.valid ? `Radar at ${describeTime(new Date(data.meta.valid))}` : null
}

const qpfTime = (layer: number) => async () => {
  const data = await json(
    `${WPC_QPF}/${layer}/query?where=1%3D1&outFields=issue_time&returnGeometry=false&resultRecordCount=1&f=json`,
  )
  const issued = data?.features?.[0]?.attributes?.issue_time
  return issued ? `Issued ${describeTime(parseWpcTime(issued))}` : null
}

const qpf = (id: 'qpf1' | 'qpf3' | 'qpf7', name: string, description: string): RasterOverlay => ({
  id,
  kind: 'raster',
  name,
  description,
  credit: WPC_CREDIT,
  attribution: WPC_ATTRIBUTION,
  legend: QPF_LEGEND,
  opacity: 0.6,
  refreshMinutes: 60,
  tiles: qpfTiles(QPF_LAYERS[id]),
  time: qpfTime(QPF_LAYERS[id]),
})

const QPF_NOTE =
  "A forecaster's product from the National Weather Service; WISP's own forecast (Open-Meteo) can differ."

/** Rain layers: one at a time */
export const RAIN_OVERLAYS: RasterOverlay[] = [
  {
    id: 'radar',
    kind: 'raster',
    name: 'Radar now',
    description: 'Base reflectivity across the US, updated every 5 minutes.',
    credit: IEM_CREDIT,
    attribution: IEM_ATTRIBUTION,
    legend: {
      kind: 'ramp',
      colors: [
        '#04e9e7',
        '#019ff4',
        '#0300f4',
        '#02fd02',
        '#01c501',
        '#008e00',
        '#fdf802',
        '#e5bc00',
        '#fd9500',
        '#fd0000',
        '#bc0000',
        '#f800fd',
      ],
      start: 'Light',
      end: 'Heavy',
    },
    opacity: 0.7,
    refreshMinutes: 5,
    tiles: iemTiles('nexrad-n0q-900913'),
    time: radarTime,
  },
  {
    id: 'rain24',
    kind: 'raster',
    name: 'Rain, last 24 hours',
    description: "Estimated from radar and gauges (NOAA MRMS). Compare it with your gauge and WISP's weather.",
    credit: IEM_CREDIT,
    attribution: IEM_ATTRIBUTION,
    legend: { kind: 'image', src: `${IEM}/images/mrms_q3_p24h.png`, alt: 'Rain from 0.25 to 15 inches', inches: true },
    opacity: 0.7,
    refreshMinutes: 30,
    tiles: iemTiles('q2-p24h-900913'),
  },
  {
    id: 'rain72',
    kind: 'raster',
    name: 'Rain, last 72 hours',
    description: 'Estimated from radar and gauges (NOAA MRMS).',
    credit: IEM_CREDIT,
    attribution: IEM_ATTRIBUTION,
    legend: { kind: 'image', src: `${IEM}/images/mrms_q3_p24h.png`, alt: 'Rain from 0.25 to 15 inches', inches: true },
    opacity: 0.7,
    refreshMinutes: 30,
    tiles: iemTiles('q2-p72h-900913'),
  },
  qpf('qpf1', 'Forecast rain, day 1', `The next 24 hours from 7 pm Central. ${QPF_NOTE}`),
  qpf('qpf3', 'Forecast rain, days 1–3', `The next 3 days. ${QPF_NOTE}`),
  qpf('qpf7', 'Forecast rain, days 1–7', `The next 7 days. ${QPF_NOTE}`),
]

export const DROUGHT_OVERLAY: VectorOverlay = {
  id: 'drought',
  kind: 'drought',
  name: 'Drought Monitor',
  description: 'The U.S. Drought Monitor, released each Thursday.',
  credit: { name: 'National Drought Mitigation Center, USDA, NOAA', url: 'https://droughtmonitor.unl.edu/' },
  attribution: 'Drought: <a href="https://droughtmonitor.unl.edu/">U.S. Drought Monitor</a>',
  legend: { kind: 'classes', items: DROUGHT_CATEGORIES.map(({ label, color }) => ({ label, color })) },
  opacity: 0.45,
}

export const SOIL_OVERLAY: RasterOverlay = {
  id: 'soil',
  kind: 'raster',
  name: 'Soil survey',
  description: 'Soil map unit outlines and symbols from SSURGO. Zoom in to a pivot to see them.',
  credit: { name: 'USDA NRCS Web Soil Survey', url: 'https://websoilsurvey.nrcs.usda.gov/' },
  attribution: 'Soils: <a href="https://websoilsurvey.nrcs.usda.gov/">USDA NRCS</a>',
  legend: { kind: 'note', text: 'Orange outlines with each map unit’s symbol' },
  opacity: 0.9,
  minzoom: 12,
  tiles: () => [SOIL_WMS],
}

export const OVERLAYS: Overlay[] = [...RAIN_OVERLAYS, DROUGHT_OVERLAY, SOIL_OVERLAY]

export const overlayById = (id: string) => OVERLAYS.find((overlay) => overlay.id === id)

/** Bottom to top; each overlay is drawn under the ones after it, and all under the pivots */
export const OVERLAY_ORDER: OverlayId[] = ['drought', 'radar', 'rain24', 'rain72', 'qpf1', 'qpf3', 'qpf7', 'soil']

/** [west, south, east, north] */
export type Bounds = [number, number, number, number]

/** The Drought Monitor's current polygons in an area, as GeoJSON, simplified to about 1 km */
export function droughtUrl([west, south, east, north]: Bounds): string {
  const params = new URLSearchParams({
    where: '1=1',
    outFields: 'DM,ValidStart',
    geometry: [west, south, east, north].map((value) => value.toFixed(3)).join(','),
    geometryType: 'esriGeometryEnvelope',
    inSR: '4326',
    spatialRel: 'esriSpatialRelIntersects',
    outSR: '4326',
    maxAllowableOffset: '0.01',
    geometryPrecision: '4',
    f: 'geojson',
  })
  return `${USDM_QUERY}?${params}`
}

/** The area to load drought polygons for: around the pivots, wide enough to zoom out a little */
export function droughtBounds(points: LngLat[], margin = 3): Bounds {
  if (!points.length) return [-93, 42.4, -86.7, 47.1] // Wisconsin
  const lngs = points.map(([lng]) => lng)
  const lats = points.map(([, lat]) => lat)
  return [
    Math.min(...lngs) - margin,
    Math.min(...lats) - margin,
    Math.max(...lngs) + margin,
    Math.max(...lats) + margin,
  ]
}

type Geometry = { type: 'Polygon'; coordinates: LngLat[][] } | { type: 'MultiPolygon'; coordinates: LngLat[][][] }
export type DroughtFeature = {
  type: 'Feature'
  properties: { DM: number; ValidStart?: number | null }
  geometry: Geometry | null
}
export type DroughtData = { type: 'FeatureCollection'; features: DroughtFeature[] }

const contains = (geometry: Geometry | null, point: LngLat) =>
  geometry?.type === 'Polygon'
    ? pointInPolygon(point, geometry.coordinates)
    : geometry?.type === 'MultiPolygon'
      ? geometry.coordinates.some((polygon) => pointInPolygon(point, polygon))
      : false

/**
 * The Drought Monitor category at a point: the highest one whose area contains it (the map's areas
 * overlap, D1 inside D0 and so on), or null for none
 */
export function droughtAt(data: DroughtData, point: LngLat) {
  const found = data.features.filter((feature) => contains(feature.geometry, point)).map((f) => f.properties.DM)
  if (!found.length) return null
  return DROUGHT_CATEGORIES.find((category) => category.dm === Math.max(...found)) ?? null
}

/** The map's week ("Map for Oct 13"), from its features' ValidStart (epoch ms) */
export function droughtDate(data: DroughtData): Date | null {
  const start = data.features.find((feature) => feature.properties.ValidStart)?.properties.ValidStart
  return start ? new Date(start) : null
}
