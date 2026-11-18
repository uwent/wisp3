// A system's location typed or pasted into one box (CoordinatesField): what Google Maps copies
// ("44.12345, -89.54321"), a spreadsheet's two cells (tab-separated), degrees, minutes and seconds
// with hemisphere letters ("44°07'12.3"N 89°32'24"W"), or a Google Maps link. Latitude comes first
// unless letters or words say otherwise, or the numbers read as a US place the other way round (a
// GIS file's longitude, latitude order), which is read the other way round and said so.

export type LatLng = { latitude: number; longitude: number }

export type CoordinatesResult = { ok: true; value: LatLng | null; swapped?: boolean } | { ok: false; error: string }

const EXAMPLE = 'such as 44.1234, -89.5678'

type Hemisphere = 'N' | 'S' | 'E' | 'W'
type Role = 'lat' | 'lon'
type Part = { degrees: number; minutes?: number; seconds?: number; hemisphere?: Hemisphere; role?: Role }

const HEMISPHERES: Record<string, Hemisphere> = {
  n: 'N',
  north: 'N',
  s: 'S',
  south: 'S',
  e: 'E',
  east: 'E',
  w: 'W',
  west: 'W',
}
const ROLES: Record<string, Role> = {
  lat: 'lat',
  latitude: 'lat',
  lon: 'lon',
  lng: 'lon',
  long: 'lon',
  longitude: 'lon',
}

// Google Maps links: …/@44.1234,-89.5678,15z or ?q=44.1234,-89.5678 (also query, ll, center, destination)
const NUMBER = '[-+]?\\d+(?:\\.\\d+)?'
const AT_LINK = new RegExp(`@(${NUMBER}),(${NUMBER})`)
const QUERY_LINK = new RegExp(`[?&](?:q|query|ll|center|destination)=(${NUMBER})(?:,|%2C)(?:\\+|%20)*(${NUMBER})`, 'i')

const round = (value: number) => Math.round(value * 1e6) / 1e6

export function formatCoordinates({ latitude, longitude }: LatLng): string {
  return `${latitude}, ${longitude}`
}

export function parseCoordinates(text: string): CoordinatesResult {
  const trimmed = text.trim()
  if (trimmed === '') return { ok: true, value: null }

  if (/^https?:\/\//i.test(trimmed) || /^(www\.)?(maps\.)?google\./i.test(trimmed)) {
    const match = trimmed.match(AT_LINK) ?? trimmed.match(QUERY_LINK)
    if (!match) {
      return {
        ok: false,
        error: "That link doesn't include coordinates: right-click the spot in Google Maps and copy them",
      }
    }
    return place({ degrees: Number(match[1]) }, { degrees: Number(match[2]) })
  }

  const tokens = normalize(trimmed).match(/[-+]?\d+(?:\.\d+)?|[-+]?\.\d+|[a-z]+|[°'"]/gi) ?? []
  const parts: Part[] = []
  let pendingHemisphere: Hemisphere | undefined
  let pendingRole: Role | undefined
  let justEnded: Part | undefined
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i]
    const word = token.toLowerCase()
    if (/^[a-z]+$/.test(word)) {
      if (HEMISPHERES[word]) {
        // After a number without one, it's that number's ("44.1 N"); otherwise the next one's ("N 44.1")
        if (justEnded && !justEnded.hemisphere && !pendingHemisphere) justEnded.hemisphere = HEMISPHERES[word]
        else pendingHemisphere = HEMISPHERES[word]
        justEnded = undefined
      } else if (ROLES[word]) {
        pendingRole = ROLES[word]
        justEnded = undefined
      } else {
        return { ok: false, error: `Enter the latitude and longitude, ${EXAMPLE}` }
      }
      continue
    }
    if (!/\d/.test(token)) continue // a degree, minute or second mark, read with its number below
    const value = Number(token)
    const mark = tokens[i + 1]
    const current = parts.at(-1)
    // Minutes and seconds belong to the number before them, which they follow without letters between
    if (mark === "'" && current && justEnded === current && current.minutes === undefined) {
      current.minutes = value
      continue
    }
    if (
      mark === '"' &&
      current &&
      justEnded === current &&
      current.minutes !== undefined &&
      current.seconds === undefined
    ) {
      current.seconds = value
      continue
    }
    const part: Part = { degrees: value, hemisphere: pendingHemisphere, role: pendingRole }
    pendingHemisphere = pendingRole = undefined
    parts.push(part)
    justEnded = part
  }

  if (parts.length === 0) return { ok: false, error: `Enter the latitude and longitude, ${EXAMPLE}` }
  if (parts.length === 1) return { ok: false, error: `Add the longitude after the latitude, ${EXAMPLE}` }
  if (parts.length > 2) return { ok: false, error: `Enter two numbers, the latitude then the longitude, ${EXAMPLE}` }
  return place(parts[0], parts[1])
}

// Curly quotes and primes from a web page or word processor, the minus sign, and the ordinal or ring
// some sources use for degrees
function normalize(text: string): string {
  return text
    .replace(/[″“”]|''/g, '"')
    .replace(/[′‘’´`]/g, "'")
    .replace(/[º˚]/g, '°')
    .replace(/−/g, '-')
}

function decimal(part: Part): number | string {
  const { degrees, minutes, seconds } = part
  if (minutes === undefined) return degrees
  if (!Number.isInteger(degrees)) return 'Degrees with minutes should be a whole number'
  if (minutes >= 60 || (seconds ?? 0) >= 60) return 'Minutes and seconds are less than 60'
  const size = Math.abs(degrees) + minutes / 60 + (seconds ?? 0) / 3600
  return degrees < 0 || Object.is(degrees, -0) ? -size : size
}

function axis(part: Part): Role | undefined {
  if (part.hemisphere) return part.hemisphere === 'N' || part.hemisphere === 'S' ? 'lat' : 'lon'
  return part.role
}

function place(first: Part, second: Part): CoordinatesResult {
  const values = [decimal(first), decimal(second)]
  for (const value of values) if (typeof value === 'string') return { ok: false, error: value }
  const [a, b] = values as number[]
  const signed = (part: Part, value: number) =>
    part.hemisphere === 'S' || part.hemisphere === 'W' ? -Math.abs(value) : part.hemisphere ? Math.abs(value) : value

  let firstAxis = axis(first)
  const secondAxis = axis(second)
  if (firstAxis && firstAxis === secondAxis) {
    return {
      ok: false,
      error:
        firstAxis === 'lat'
          ? 'Both are latitudes (N or S): add the longitude'
          : 'Both are longitudes (E or W): add the latitude',
    }
  }
  // One named says which the other is
  firstAxis ??= secondAxis === 'lat' ? 'lon' : secondAxis === 'lon' ? 'lat' : undefined

  let swapped = false
  if (!firstAxis) {
    // Nothing says which is which: latitude first, unless it can't be one and the second can, or the
    // signs are a US place's the other way round (WISP's places have a positive latitude, a negative
    // longitude)
    swapped = (Math.abs(a) > 90 && Math.abs(b) <= 90) || (a < 0 && b > 0)
    firstAxis = swapped ? 'lon' : 'lat'
  }
  const [latPart, latValue, lonPart, lonValue] = firstAxis === 'lat' ? [first, a, second, b] : [second, b, first, a]
  const latitude = signed(latPart, latValue)
  const longitude = signed(lonPart, lonValue)
  if (Math.abs(latitude) > 90) return { ok: false, error: 'Latitude is between -90 and 90' }
  if (Math.abs(longitude) > 180) return { ok: false, error: 'Longitude is between -180 and 180' }
  return {
    ok: true,
    value: { latitude: round(latitude), longitude: round(longitude) },
    ...(swapped ? { swapped } : {}),
  }
}

/** A word under the box when the place can't be in the US: most likely a sign left off */
export function outsideUs({ latitude, longitude }: LatLng): string | null {
  if (longitude > 0)
    return "That's east of Greenwich, not in the US: US longitudes are negative (west), such as -89.5678."
  if (latitude < 0) return "That's south of the equator, not in the US: US latitudes are positive (north)."
  return null
}
