import type { LngLat } from './geo'

// The soil survey under a pivot (PLAN.md Phase 7 F): USDA NRCS Soil Data Access (SSURGO), queried
// from the browser. For each map unit under the pivot's circle or arc: its share of the area, and
// its main component's surface texture, which suggests one of WISP's soil types (soil_types.yml).
// A suggestion only; the user picks the soil.

const ENDPOINT = 'https://SDMDataAccess.sc.egov.usda.gov/Tabular/post.rest'

// The main component's surface texture (as tg.texdesc): its top horizon for an organic soil
// (Histosols: Markey, Seelyeville), and otherwise its first mineral horizon. Mineral soils are often
// recorded with a few centimeters of leaf litter or muck on top (Friendship loamy sand: 2 cm of
// "moderately decomposed plant material" over the loamy sand), which would suggest Muck.
const SURFACE_TEXTURE =
  'OUTER APPLY (SELECT TOP 1 t.texdesc FROM chorizon h ' +
  "JOIN chtexturegrp t ON t.chkey = h.chkey AND t.rvindicator = 'Yes' " +
  "WHERE h.cokey = c.cokey AND (c.taxorder = 'Histosols' OR " +
  "(t.texdesc NOT IN ('Muck', 'Peat', 'Mucky peat') AND t.texdesc NOT LIKE '%plant material')) " +
  'ORDER BY h.hzdept_r) tg '

export type MapUnit = {
  mukey: string
  /** Share of the pivot's area, 0–1 */
  share: number
  /** "Plainfield sand, 2 to 6 percent slopes" */
  name: string
  /** The main component ("Plainfield") and its surface texture ("Sand"), if the survey has them */
  component: string | null
  texture: string | null
}

// USDA texture → soil type key. Modifiers (fine, coarse, gravelly…) are dropped first; textures we
// have no type for (silty clay, sandy clay, peat) suggest nothing.
const TEXTURES: Record<string, string> = {
  sand: 'sand',
  'loamy sand': 'loamy_sand',
  'sandy loam': 'sandy_loam',
  loam: 'loam',
  'silt loam': 'silt_loam',
  silt: 'silt',
  'sandy clay loam': 'sandy_clay_loam',
  'clay loam': 'clay_loam',
  'silty clay loam': 'silty_clay_loam',
  clay: 'clay',
  muck: 'muck',
  'mucky peat': 'muck',
  // Organic horizons as SSURGO names them: highly decomposed is muck, moderately is mucky peat
  'highly decomposed plant material': 'muck',
  'moderately decomposed plant material': 'muck',
}
const MODIFIERS =
  /\b(extremely|very|fine|coarse|gravelly|cobbly|stony|bouldery|channery|flaggy|cherty|shaly|mucky(?! peat))\b/g

/** The soil type key for a USDA texture, or null */
export function soilKeyFor(texture: string | null): string | null {
  if (!texture) return null
  const plain = texture.toLowerCase()
  if (TEXTURES[plain]) return TEXTURES[plain]
  return TEXTURES[plain.replace(MODIFIERS, '').replace(/\s+/g, ' ').trim()] ?? null
}

/** The survey query for a polygon ring ([lng, lat], closed) */
export function soilQuery(ring: LngLat[]): string {
  const wkt = `POLYGON((${ring.map(([lng, lat]) => `${lng.toFixed(6)} ${lat.toFixed(6)}`).join(', ')}))`
  return (
    `WITH aoi AS (SELECT geometry::STGeomFromText('${wkt}', 4326) AS g), ` +
    'areas AS (SELECT p.mukey, SUM(p.mupolygongeo.STIntersection(aoi.g).STArea()) AS area ' +
    'FROM mupolygon p, aoi WHERE p.mupolygongeo.STIntersects(aoi.g) = 1 GROUP BY p.mukey) ' +
    'SELECT a.mukey, a.area / SUM(a.area) OVER () AS share, mu.muname, c.compname, tg.texdesc ' +
    'FROM areas a JOIN mapunit mu ON mu.mukey = a.mukey ' +
    'LEFT JOIN component c ON c.cokey = ' +
    '(SELECT TOP 1 c2.cokey FROM component c2 WHERE c2.mukey = a.mukey ORDER BY c2.comppct_r DESC) ' +
    SURFACE_TEXTURE +
    'ORDER BY share DESC'
  )
}

/** Soil Data Access's JSON+COLUMNNAME table (a header row, then strings) → map units */
export function parseSoilTable(body: { Table?: (string | null)[][] }): MapUnit[] {
  const [header, ...rows] = body.Table ?? []
  if (!header) return []
  const at = (name: string) => header.indexOf(name)
  // A map unit can repeat when its main component has several surface texture groups
  const seen = new Set<string>()
  return rows.flatMap((row) => {
    const mukey = row[at('mukey')] ?? ''
    if (seen.has(mukey)) return []
    seen.add(mukey)
    return [
      {
        mukey,
        share: Number(row[at('share')]),
        name: row[at('muname')] ?? 'Unnamed map unit',
        component: row[at('compname')],
        texture: row[at('texdesc')],
      },
    ]
  })
}

export async function fetchSoilSurvey(ring: LngLat[], signal?: AbortSignal): Promise<MapUnit[]> {
  const response = await fetch(ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ format: 'JSON+COLUMNNAME', query: soilQuery(ring) }),
    signal,
  })
  if (!response.ok) throw new Error(`Soil survey: ${response.status}`)
  // An area outside the survey answers with an empty body
  const text = await response.text()
  return text.trim() ? parseSoilTable(JSON.parse(text)) : []
}

export type SoilSuggestion = {
  /** The soil type key covering the most of the pivot, or null if the survey doesn't suggest one */
  key: string | null
  /** Its share of the pivot's area */
  share: number
  units: MapUnit[]
}

/**
 * The soil type covering the most of the pivot (adding up map units of the same type), if the map
 * units we can match cover at least half of it (not mostly water, peat or unsurveyed)
 */
export function suggestSoil(units: MapUnit[]): SoilSuggestion {
  const byKey = new Map<string, number>()
  for (const unit of units) {
    const key = soilKeyFor(unit.texture)
    if (key) byKey.set(key, (byKey.get(key) ?? 0) + unit.share)
  }
  const matched = [...byKey.values()].reduce((sum, share) => sum + share, 0)
  const [best] = [...byKey.entries()].sort((a, b) => b[1] - a[1])
  return best && matched >= 0.5 ? { key: best[0], share: best[1], units } : { key: null, share: 0, units }
}

// The soil types around a pivot, for the picker's map: each map unit's polygons in an area, colored
// by the soil type its main component's surface texture suggests

/** Coarse to fine (pale yellow to dark brown), muck near black */
export const SOIL_COLORS: Record<string, string> = {
  sand: '#fbeea6',
  loamy_sand: '#f3d27c',
  sandy_loam: '#e3b25a',
  loam: '#c98f45',
  silt_loam: '#ad7337',
  sandy_clay_loam: '#b5654a',
  silt: '#c2a98a',
  clay_loam: '#8a5230',
  silty_clay_loam: '#74452e',
  clay: '#573223',
  muck: '#2c2a28',
}

/** [west, south, east, north] */
export type Bounds = [number, number, number, number]

/** The survey query for the map units' polygons in an area, simplified to a few meters */
export function soilAreaQuery([west, south, east, north]: Bounds): string {
  const box = [
    [west, south],
    [east, south],
    [east, north],
    [west, north],
    [west, south],
  ]
    .map(([lng, lat]) => `${lng.toFixed(6)} ${lat.toFixed(6)}`)
    .join(', ')
  return (
    `WITH aoi AS (SELECT geometry::STGeomFromText('POLYGON((${box}))', 4326) AS g) ` +
    'SELECT p.mukey, p.mupolygongeo.STIntersection(aoi.g).Reduce(0.00003).STAsText() AS wkt, mu.muname, tg.texdesc ' +
    'FROM mupolygon p CROSS JOIN aoi JOIN mapunit mu ON mu.mukey = p.mukey ' +
    'LEFT JOIN component c ON c.cokey = ' +
    '(SELECT TOP 1 c2.cokey FROM component c2 WHERE c2.mukey = p.mukey ORDER BY c2.comppct_r DESC) ' +
    SURFACE_TEXTURE +
    'WHERE p.mupolygongeo.STIntersects(aoi.g) = 1'
  )
}

type Nested = LngLat | Nested[]

/**
 * The polygons in a WKT POLYGON, MULTIPOLYGON or GEOMETRYCOLLECTION (what clipping a map unit to the
 * area returns); lines and points (a unit touching the edge) are left out
 */
export function wktPolygons(wkt: string): LngLat[][][] {
  const tokens = wkt.match(/[A-Za-z]+|-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?|[(),]/g) ?? []
  let i = 0
  const polygons: LngLat[][][] = []

  // "(x y, x y)" → points; "((…), (…))" → lists of them
  function list(): Nested[] {
    i++ // (
    const items: Nested[] = []
    while (i < tokens.length && tokens[i] !== ')') {
      if (tokens[i] === ',') i++
      else if (tokens[i] === '(') items.push(list())
      else {
        const coordinates: number[] = []
        while (i < tokens.length && /^-?\d/.test(tokens[i])) coordinates.push(Number(tokens[i++]))
        items.push([coordinates[0], coordinates[1]])
      }
    }
    i++ // )
    return items
  }

  function geometry() {
    const type = tokens[i++]?.toUpperCase()
    if (tokens[i]?.toUpperCase() === 'EMPTY') return void i++
    if (type === 'GEOMETRYCOLLECTION') {
      i++ // (
      while (i < tokens.length && tokens[i] !== ')') {
        if (tokens[i] === ',') i++
        else geometry()
      }
      i++ // )
      return
    }
    const body = list()
    if (type === 'POLYGON') polygons.push(body as LngLat[][])
    else if (type === 'MULTIPOLYGON') polygons.push(...(body as LngLat[][][]))
  }

  while (i < tokens.length) geometry()
  return polygons.filter((polygon) => polygon.length && polygon[0].length >= 4)
}

export type SoilAreaProperties = { key: string | null; unit: string; texture: string | null }
export type SoilAreas = {
  type: 'FeatureCollection'
  features: {
    type: 'Feature'
    properties: SoilAreaProperties
    geometry: { type: 'MultiPolygon'; coordinates: LngLat[][][] }
  }[]
}

/** Soil Data Access's table of map unit polygons → GeoJSON, each with its suggested soil type */
export function parseSoilAreas(body: { Table?: (string | null)[][] }): SoilAreas {
  const [header, ...rows] = body.Table ?? []
  const at = (name: string) => header?.indexOf(name) ?? -1
  return {
    type: 'FeatureCollection',
    features: rows.flatMap((row) => {
      const coordinates = wktPolygons(row[at('wkt')] ?? '')
      if (!coordinates.length) return []
      const texture = row[at('texdesc')]
      return [
        {
          type: 'Feature' as const,
          properties: { key: soilKeyFor(texture), unit: row[at('muname')] ?? 'Unnamed map unit', texture },
          geometry: { type: 'MultiPolygon' as const, coordinates },
        },
      ]
    }),
  }
}

export async function fetchSoilAreas(bounds: Bounds, signal?: AbortSignal): Promise<SoilAreas> {
  const response = await fetch(ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ format: 'JSON+COLUMNNAME', query: soilAreaQuery(bounds) }),
    signal,
  })
  if (!response.ok) throw new Error(`Soil survey: ${response.status}`)
  const text = await response.text()
  return text.trim() ? parseSoilAreas(JSON.parse(text)) : { type: 'FeatureCollection', features: [] }
}
