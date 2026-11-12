// The week ahead in brief (ForecastStrip, G.12): each day's sky in words and as an icon, from the
// day's most severe WMO weather code (Open-Meteo's weather_code, stored per day as its highest
// hour), with what's stored to fall back on when a day has no code.

import type { ForecastDay } from '@/types/serializers'

export type Sky =
  'clear' | 'partly' | 'cloudy' | 'fog' | 'drizzle' | 'rain' | 'showers' | 'freezing' | 'snow' | 'thunder'

export type SkyWords = { sky: Sky; label: string }

// WMO 4677 codes as Open-Meteo uses them (https://open-meteo.com/en/docs, "WMO Weather interpretation codes")
const CODES: Record<number, SkyWords> = {
  45: { sky: 'fog', label: 'Fog' },
  48: { sky: 'fog', label: 'Freezing fog' },
  51: { sky: 'drizzle', label: 'Light drizzle' },
  53: { sky: 'drizzle', label: 'Drizzle' },
  55: { sky: 'drizzle', label: 'Heavy drizzle' },
  56: { sky: 'freezing', label: 'Freezing drizzle' },
  57: { sky: 'freezing', label: 'Freezing drizzle' },
  61: { sky: 'rain', label: 'Light rain' },
  63: { sky: 'rain', label: 'Rain' },
  65: { sky: 'rain', label: 'Heavy rain' },
  66: { sky: 'freezing', label: 'Freezing rain' },
  67: { sky: 'freezing', label: 'Freezing rain' },
  71: { sky: 'snow', label: 'Light snow' },
  73: { sky: 'snow', label: 'Snow' },
  75: { sky: 'snow', label: 'Heavy snow' },
  77: { sky: 'snow', label: 'Snow grains' },
  80: { sky: 'showers', label: 'Light showers' },
  81: { sky: 'showers', label: 'Showers' },
  82: { sky: 'showers', label: 'Heavy showers' },
  85: { sky: 'snow', label: 'Snow showers' },
  86: { sky: 'snow', label: 'Heavy snow showers' },
  95: { sky: 'thunder', label: 'Thunderstorms' },
  96: { sky: 'thunder', label: 'Thunderstorms with hail' },
  99: { sky: 'thunder', label: 'Thunderstorms with hail' },
}

/** By the day's mean cloud cover (percent) */
function clouds(cover: number): SkyWords {
  if (cover < 20) return { sky: 'clear', label: 'Sunny' }
  if (cover < 50) return { sky: 'partly', label: 'Mostly sunny' }
  if (cover < 80) return { sky: 'partly', label: 'Partly cloudy' }
  return { sky: 'cloudy', label: 'Cloudy' }
}

/**
 * The day's sky in words. Codes 0–3 only say how cloudy the cloudiest hour was, so a dry day is
 * worded from the day's mean cloud cover when there is one. Without a code, measurable snow or
 * precipitation, then cloud cover; null with nothing to go on.
 */
export function skyFor(
  day: Pick<ForecastDay, 'weather_code' | 'cloud_cover_pct' | 'precip_in' | 'snowfall_in'>,
): SkyWords | null {
  const code = day.weather_code
  if (code !== null && CODES[code]) return CODES[code]
  if (code === null) {
    if ((day.snowfall_in ?? 0) >= 0.1) return { sky: 'snow', label: 'Snow' }
    if ((day.precip_in ?? 0) >= 0.1) return { sky: 'rain', label: 'Rain' }
    if ((day.precip_in ?? 0) >= 0.01) return { sky: 'showers', label: 'Light showers' }
  }
  if (day.cloud_cover_pct !== null) return clouds(day.cloud_cover_pct)
  if (code === null) return null
  return code <= 1 ? { sky: 'clear', label: 'Sunny' } : code === 2 ? clouds(60) : clouds(100)
}

const weekdays = new Intl.DateTimeFormat('en-US', { timeZone: 'UTC', weekday: 'short' })

/** "Today", "Tomorrow" or "Thu" */
export function dayName(iso: string, today: string): string {
  if (iso === today) return 'Today'
  const next = new Date(`${today}T00:00:00Z`)
  next.setUTCDate(next.getUTCDate() + 1)
  if (iso === next.toISOString().slice(0, 10)) return 'Tomorrow'
  return weekdays.format(new Date(`${iso}T00:00:00Z`))
}
