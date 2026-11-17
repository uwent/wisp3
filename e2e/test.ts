import { readFileSync } from 'node:fs'

import { test as base } from '@playwright/test'

// Playwright's test, with the outside services every page may call answered here, so a USDA, USGS or
// OpenFreeMap outage (or a slow day) can't fail the suite. A test's own page.route() takes precedence over these (smoke.spec.ts
// gives the soil survey its own answer). E2E_LIVE=1 bin/e2e reaches the real services instead.

export { expect } from '@playwright/test'

/** The soil survey's answer for any area: mostly Plainfield sand, some Coloma loamy sand */
export const SURVEY_SHARES = [
  ['mukey', 'share', 'muname', 'compname', 'texdesc'],
  ['423976', '0.7', 'Plainfield sand, 2 to 6 percent slopes', 'Plainfield', 'Sand'],
  ['423954', '0.3', 'Coloma loamy sand, 6 to 12 percent slopes', 'Coloma', 'Loamy sand'],
]

// A plain green 256 px tile for the satellite basemap
const imageryTile = readFileSync(new URL('./fixtures/imagery-tile.png', import.meta.url))

export const test = base.extend({
  context: async ({ context }, use) => {
    if (!process.env.E2E_LIVE) {
      // The soil survey (lib/soils.ts): the Soil types layer asks for map unit polygons in a box
      // (answered with the box as one unit of sand), everything else for the units' shares of an area
      await context.route('**/Tabular/post.rest', (route) => {
        const query: string = route.request().postDataJSON()?.query ?? ''
        const box = query.match(/POLYGON\(\([^)]*\)\)/)?.[0]
        const table =
          query.includes('STAsText') && box
            ? [
                ['mukey', 'wkt', 'muname', 'texdesc'],
                ['423976', box, 'Plainfield sand, 2 to 6 percent slopes', 'Sand'],
              ]
            : SURVEY_SHARES
        return route.fulfill({ json: { Table: table }, headers: { 'Access-Control-Allow-Origin': '*' } })
      })
      // OpenFreeMap's vector tiles (the roads over the imagery, the street map): empty, so maps load
      // at once (the shape page's tools wait for its map). Its fonts and street style stay live.
      await context.route('**/tiles.openfreemap.org/planet', (route) =>
        route.fulfill({
          json: { tilejson: '3.0.0', tiles: ['https://tiles.openfreemap.org/planet/e2e/{z}/{x}/{y}.pbf'], maxzoom: 14 },
          headers: { 'Access-Control-Allow-Origin': '*' },
        }),
      )
      await context.route('**/tiles.openfreemap.org/planet/**', (route) =>
        route.fulfill({
          body: Buffer.alloc(0),
          contentType: 'application/x-protobuf',
          headers: { 'Access-Control-Allow-Origin': '*' },
        }),
      )
      // The USGS imagery basemap's tiles (lib/map/basemaps.ts)
      await context.route('**/basemap.nationalmap.gov/**', (route) =>
        route.fulfill({ body: imageryTile, contentType: 'image/png', headers: { 'Access-Control-Allow-Origin': '*' } }),
      )
    }
    await use(context)
  },
})
