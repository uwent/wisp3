import type { RouteDefinition, RouteOptions } from '@/routes/runtime'
import { exportWeatherZone, weatherZones } from '@/routes'

// A weather zone's address is its cell's center, /weather/44.12,-89.54 (G.6). The generated route
// helpers encode the comma (%2C), which works but reads badly in the address bar; a comma is
// allowed in a path, so these put it back.

const readable = (route: RouteDefinition<'get'>): RouteDefinition<'get'> => ({
  ...route,
  url: route.url.replace(/%2C/gi, ','),
})

/** The zone's page: weatherZone('44.12,-89.54', { query: { year: 2025 } }) */
export function weatherZone(location: string, options?: RouteOptions): RouteDefinition<'get'> {
  return readable(weatherZones.show(location, options))
}

/** Its season of weather as CSV */
export function weatherZoneExport(location: string, options?: RouteOptions): RouteDefinition<'get'> {
  return readable(exportWeatherZone(location, options))
}
