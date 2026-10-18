import type { LngLat } from './geo'

// The soil survey under a pivot (PLAN.md Phase 7 F): USDA NRCS Soil Data Access (SSURGO), queried
// from the browser. For each map unit under the pivot's circle or arc: its share of the area, and
// its main component's surface texture, which suggests one of WISP's soil types (soil_types.yml).
// A suggestion only; the user picks the soil.

const ENDPOINT = 'https://SDMDataAccess.sc.egov.usda.gov/Tabular/post.rest'

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
    'LEFT JOIN chorizon h ON h.cokey = c.cokey AND h.hzdept_r = 0 ' +
    "LEFT JOIN chtexturegrp tg ON tg.chkey = h.chkey AND tg.rvindicator = 'Yes' " +
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
