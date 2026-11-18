import { describe, expect, it } from 'vitest'

import { formatCoordinates, outsideUs, parseCoordinates } from './coordinates'

const at = (latitude: number, longitude: number) => ({ ok: true, value: { latitude, longitude } })

describe('parseCoordinates', () => {
  it('reads nothing as no location', () => {
    expect(parseCoordinates('  ')).toEqual({ ok: true, value: null })
  })

  it.each([
    ['44.1234, -89.5678', 'Google Maps'],
    ['44.1234\t-89.5678', 'two spreadsheet cells'],
    ['44.1234 -89.5678', 'a space'],
    ['44.1234;-89.5678', 'a semicolon'],
    ['(44.1234, -89.5678)', 'parentheses'],
    [' 44.1234,-89.5678 \n', 'surrounding whitespace'],
    ['44.1234, −89.5678', 'a minus sign'],
    ['Lat: 44.1234 Lon: -89.5678', 'labels'],
    ['44.1234° N, 89.5678° W', 'hemisphere letters after'],
    ['N44.1234 W89.5678', 'hemisphere letters before'],
    ['44.1234 north 89.5678 west', 'hemisphere words'],
  ])('reads %j (%s)', (text) => {
    expect(parseCoordinates(text)).toEqual(at(44.1234, -89.5678))
  })

  it('reads degrees, minutes and seconds', () => {
    expect(parseCoordinates(`44°07'24.2"N 89°34'04.1"W`)).toEqual(at(44.123389, -89.567806))
    expect(parseCoordinates('44°07′24.2″N, 89°34′04.1″W')).toEqual(at(44.123389, -89.567806))
    expect(parseCoordinates("N 44° 07.404' W 89° 34.068'")).toEqual(at(44.1234, -89.5678))
    expect(parseCoordinates("44 07.404' -89 34.068'")).toEqual(at(44.1234, -89.5678))
  })

  it('reads the hemispheres, labels or ranges for the order', () => {
    expect(parseCoordinates('89.5678 W, 44.1234 N')).toEqual(at(44.1234, -89.5678))
    expect(parseCoordinates('lon -89.5678 lat 44.1234')).toEqual(at(44.1234, -89.5678))
    expect(parseCoordinates('-89.5678, 44.1234')).toEqual({ ...at(44.1234, -89.5678), swapped: true })
  })

  it('reads a Google Maps link', () => {
    expect(parseCoordinates('https://www.google.com/maps/@44.1234,-89.5678,15z')).toEqual(at(44.1234, -89.5678))
    expect(parseCoordinates('https://maps.google.com/?q=44.1234,-89.5678')).toEqual(at(44.1234, -89.5678))
    expect(parseCoordinates('https://www.google.com/maps/place/Stevens+Point')).toMatchObject({ ok: false })
  })

  it('rounds to a millionth of a degree, as the map does', () => {
    expect(parseCoordinates('44.123456789, -89.5')).toEqual(at(44.123457, -89.5))
  })

  it.each([
    ['44.1234', /Add the longitude/],
    ['abc', /Enter the latitude and longitude/],
    ['44.1, -89.5, 300', /two numbers/],
    ['44.1 N 45.2 S', /Both are latitudes/],
    ['95, 100', /Latitude is between/],
    ['44.1, -189.5', /Longitude is between/],
    ["44°75' N 89° W", /less than 60/],
    ["44.5°07' N 89 W", /whole number/],
  ])('says what is wrong with %j', (text, error) => {
    const result = parseCoordinates(text)
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.error).toMatch(error)
  })
})

describe('formatCoordinates', () => {
  it('reads back as it was', () => {
    const value = { latitude: 44.123457, longitude: -89.5 }
    expect(parseCoordinates(formatCoordinates(value))).toEqual({ ok: true, value })
  })
})

describe('outsideUs', () => {
  it('flags a longitude or latitude with the wrong sign', () => {
    expect(outsideUs({ latitude: 44.1, longitude: 89.5 })).toMatch(/negative/)
    expect(outsideUs({ latitude: -44.1, longitude: -89.5 })).toMatch(/positive/)
    expect(outsideUs({ latitude: 44.1, longitude: -89.5 })).toBeNull()
  })
})
