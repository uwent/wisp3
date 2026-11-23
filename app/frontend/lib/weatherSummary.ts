import type { Units } from './units'

// A weather zone's weather in brief (WeatherSummary on the server): rain and reference ET totals
// and the range of highs and lows over the last week of stored days and the next week of the
// forecast. Worded as the daily email words it (digest_weather), with "reference ET": it's the
// zone's, not any crop's.

/** Days with weather, totals in inches, and the highs' and lows' range in °F as [lowest, highest]; missing is null */
export type WeatherSpan = {
  days: number
  precip: number | null
  et0: number | null
  tmax: [number, number] | null
  tmin: [number, number] | null
}
export type ZoneWeather = { past: WeatherSpan | null; ahead: WeatherSpan | null }

/** "68–82°F", or "75°F" when the range is one value */
export function temperatureRange([low, high]: [number, number], units: Units): string {
  const [from, to] = [low, high].map((f) => units.format('temperature', f, { unit: false }))
  return `${from === to ? from : `${from}–${to}`}${units.label('temperature')}`
}

/** "0.85 in rain · 1.12 in reference ET · highs 68–82°F, lows 48–60°F", or null without a value */
export function spanText(span: WeatherSpan, units: Units): string | null {
  const temps = [
    span.tmax && `highs ${temperatureRange(span.tmax, units)}`,
    span.tmin && `lows ${temperatureRange(span.tmin, units)}`,
  ].filter(Boolean)
  const parts = [
    span.precip !== null && `${units.format('depth', span.precip)} rain`,
    span.et0 !== null && `${units.format('depth', span.et0)} reference ET`,
    temps.length && temps.join(', '),
  ].filter((part): part is string => !!part)
  return parts.length ? parts.join(' · ') : null
}

/**
 * A line for each week there's weather for: ["Past 7 days: 0.85 in rain · …", "Next 7 days: …"];
 * empty when there's none yet
 */
export function weatherLines(weather: ZoneWeather | null | undefined, units: Units): string[] {
  if (!weather) return []
  return (
    [
      ['Past', weather.past],
      ['Next', weather.ahead],
    ] as const
  ).flatMap(([label, span]) => {
    if (!span) return []
    const text = spanText(span, units)
    return [`${label} ${span.days} ${span.days === 1 ? 'day' : 'days'}: ${text ?? 'not available yet'}`]
  })
}
