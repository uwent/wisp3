import {
  type Boundary,
  boundaryAcres,
  boundaryErrors,
  boundaryFrom,
  closeRing,
  type LngLat,
  ringAreaM2,
  roundBoundary,
  simplifyBoundary,
  vertexCount,
} from '@/lib/geo'

// Field outlines from a file (PLAN.md Phase 8 G.10), read in the browser so nothing is uploaded
// but the result: a zipped shapefile (FSA Common Land Units, John Deere and Climate FieldView
// exports; shpjs reprojects with its .prj), GeoJSON, or KML and KMZ (Google Earth). Each feature
// with a polygon becomes a shape: a field's outline is one ring (G.14), so a feature's largest part
// is kept, without its holes, then simplified to the corner limit; points and lines are counted and
// left out. The parsers load only when a file is read.

export type Properties = Record<string, unknown>

export type ImportedShape = {
  /** Its attributes, for its name */
  properties: Properties
  boundary: Boundary
  acres: number
  /** What was changed to make it one outline ("kept the largest of 3 parts", "1 hole removed", "simplified to fewer corners") */
  notes: string[]
  /** Why it can't be saved (FieldBoundary's wording), or [] */
  problems: string[]
}

export type ReadResult = {
  shapes: ImportedShape[]
  /** Features that aren't polygons (points, lines), left out */
  skipped: number
  /** The attribute most likely to hold the field's name, or null */
  nameKey: string | null
}

type Geometry = { type: string; coordinates?: unknown; geometries?: Geometry[] }
type Feature = { type: 'Feature'; geometry: Geometry | null; properties: Properties | null }
type Collection = { type: 'FeatureCollection'; features: Feature[] }

/** What the reader understands, for the file input's accept */
export const ACCEPT = '.zip,.geojson,.json,.kml,.kmz'

export class OutlineFileError extends Error {}

/** A file's shapes, or an OutlineFileError saying what's wrong with it */
export async function readOutlineFile(file: File): Promise<ReadResult> {
  const extension = file.name.toLowerCase().split('.').pop() ?? ''
  const collections = await parse(extension, file)
  return shapesFrom(collections)
}

async function parse(extension: string, file: File): Promise<Collection[]> {
  switch (extension) {
    case 'zip':
      return readShapefile(new Uint8Array(await file.arrayBuffer()))
    case 'shp':
    case 'dbf':
    case 'prj':
    case 'shx':
      throw new OutlineFileError(
        'A shapefile is several files. Zip the .shp, .dbf and .prj together and choose the .zip.',
      )
    case 'geojson':
    case 'json':
      return [parseGeoJson(await file.text())]
    case 'kml':
      return [await parseKml(await file.text())]
    case 'kmz':
      return [await parseKml(await kmlFromKmz(new Uint8Array(await file.arrayBuffer())))]
    default:
      throw new OutlineFileError(
        'WISP reads a zipped shapefile (.zip), GeoJSON (.geojson or .json), or Google Earth (.kml or .kmz).',
      )
  }
}

async function readShapefile(bytes: Uint8Array): Promise<Collection[]> {
  const { parseZip } = await import('shpjs')
  const { iter } = await import('but-unzip')
  const names = [...iter(bytes)].map((entry) => entry.filename.toLowerCase())
  if (!names.some((name) => name.endsWith('.shp'))) {
    throw new OutlineFileError('This .zip has no shapefile (.shp) in it.')
  }
  if (!names.some((name) => name.endsWith('.prj'))) {
    throw new OutlineFileError(
      'This shapefile has no .prj file, which says where its coordinates are. Export it again with its projection, or as GeoJSON or KML.',
    )
  }
  try {
    const parsed = (await parseZip(bytes)) as Collection | Collection[]
    return Array.isArray(parsed) ? parsed : [parsed]
  } catch (error) {
    throw new OutlineFileError(`This shapefile couldn't be read (${(error as Error).message}).`)
  }
}

export function parseGeoJson(text: string): Collection {
  let json: { type?: string; features?: Feature[]; geometry?: Geometry } & Geometry
  try {
    json = JSON.parse(text)
  } catch {
    throw new OutlineFileError("This file isn't valid GeoJSON.")
  }
  if (json.type === 'FeatureCollection' && Array.isArray(json.features)) return json as Collection
  if (json.type === 'Feature') return { type: 'FeatureCollection', features: [json as unknown as Feature] }
  if (typeof json.type === 'string' && (json.coordinates || json.geometries)) {
    return { type: 'FeatureCollection', features: [{ type: 'Feature', geometry: json, properties: {} }] }
  }
  throw new OutlineFileError("This file isn't GeoJSON features.")
}

export async function parseKml(text: string): Promise<Collection> {
  const { kml } = await import('@tmcw/togeojson')
  const document = new DOMParser().parseFromString(text, 'text/xml')
  if (document.getElementsByTagName('parsererror').length) throw new OutlineFileError("This KML file can't be read.")
  return kml(document) as unknown as Collection
}

async function kmlFromKmz(bytes: Uint8Array): Promise<string> {
  const { iter } = await import('but-unzip')
  for (const entry of iter(bytes)) {
    if (entry.filename.toLowerCase().endsWith('.kml')) return new TextDecoder().decode(await entry.read())
  }
  throw new OutlineFileError('This .kmz has no KML in it.')
}

/** The polygons in a geometry, each [outer, ...holes] (a collection's included) */
function polygonsOf(geometry: Geometry | null): LngLat[][][] {
  if (!geometry) return []
  if (geometry.type === 'Polygon') return [geometry.coordinates as LngLat[][]]
  if (geometry.type === 'MultiPolygon') return geometry.coordinates as LngLat[][][]
  if (geometry.type === 'GeometryCollection') return (geometry.geometries ?? []).flatMap(polygonsOf)
  return []
}

/** The features' polygons as shapes ready to save: closed, rounded, simplified and checked */
export function shapesFrom(collections: Collection[]): ReadResult {
  const shapes: ImportedShape[] = []
  let skipped = 0
  for (const feature of collections.flatMap((collection) => collection.features ?? [])) {
    const polygons = polygonsOf(feature.geometry)
      .map((polygon) => polygon.map(closeRing))
      .filter((polygon) => polygon[0]?.length >= 4)
    if (!polygons.length) {
      skipped++
      continue
    }
    const largest = polygons.reduce((best, polygon) => (ringAreaM2(polygon[0]) > ringAreaM2(best[0]) ? polygon : best))
    const holes = largest.length - 1
    const rounded = roundBoundary(boundaryFrom(largest[0]))
    const boundary = simplifyBoundary(rounded)
    const notes: string[] = []
    if (polygons.length > 1) notes.push(`kept the largest of ${polygons.length} parts`)
    if (holes) notes.push(holes === 1 ? '1 hole removed' : `${holes} holes removed`)
    if (vertexCount(boundary) < vertexCount(rounded)) notes.push('simplified to fewer corners')
    shapes.push({
      properties: feature.properties ?? {},
      boundary,
      acres: boundaryAcres(boundary),
      notes,
      problems: boundaryErrors(boundary),
    })
  }
  if (!shapes.length) {
    throw new OutlineFileError(
      skipped ? 'This file has points or lines but no field shapes (polygons).' : 'This file has no shapes in it.',
    )
  }
  return { shapes, skipped, nameKey: nameKey(shapes.map((shape) => shape.properties)) }
}

// Attributes that name a field in common exports, most telling first (KML's name, John Deere's
// FIELD_NAME, Climate's field_name, FSA's CLU number)
const NAME_KEYS = [
  'name',
  'field_name',
  'fieldname',
  'field',
  'fld_name',
  'label',
  'title',
  'clu_number',
  'clunbr',
  'clu',
]

/** The attribute most likely to name each field: a known one, else the first holding text */
export function nameKey(properties: Properties[]): string | null {
  const keys = [...new Set(properties.flatMap((p) => Object.keys(p)))]
  const filled = (key: string) => properties.some((p) => p[key] !== null && p[key] !== undefined && p[key] !== '')
  for (const wanted of NAME_KEYS) {
    const key = keys.find((k) => k.toLowerCase().replace(/[\s-]/g, '_') === wanted && filled(k))
    if (key) return key
  }
  return keys.find((key) => properties.some((p) => typeof p[key] === 'string' && p[key] !== '')) ?? null
}

/** A shape's name under an attribute: its value as text, trimmed, or '' */
export function shapeName(shape: ImportedShape, key: string | null): string {
  const value = key ? shape.properties[key] : null
  return value === null || value === undefined ? '' : String(value).trim()
}

/** A shape's notes as one sentence ("Kept the largest of 3 parts; 1 hole removed"), or '' */
export function shapeNotes(shape: ImportedShape): string {
  const text = shape.notes.join('; ')
  return text && text[0].toUpperCase() + text.slice(1)
}
