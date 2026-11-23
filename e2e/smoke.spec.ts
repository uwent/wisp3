import { readFileSync } from 'node:fs'

import AxeBuilder from '@axe-core/playwright'
import { type Page } from '@playwright/test'

import { DEMO, literal } from './demo'
import { firstPlantingPath, firstZonePath, researchFieldPath, signIn, watchErrors } from './session'
import { expect, test } from './test'

// Smoke tests over the demo account seeded by e2e/seed.rb: the main ways of entering data save, and
// the map and charts work. accessibility.spec.ts visits every page, failing on script errors too.

test.beforeEach(async ({ page }) => {
  await signIn(page)
})

test('the dashboard shows field cards with a status', { tag: '@phone' }, async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible()
  await expect(page.locator('main ul li').first()).toBeVisible()
  await expect(page.getByText(/% soil moisture · AD /).first()).toBeVisible()
  await expect(page.getByRole('heading', { name: /^Farm: / }).first()).toBeVisible()
  await expect(page.getByRole('heading', { name: /^Field: / }).first()).toBeVisible()

  // Rain ahead: closed to start, its title saying when rain comes; open, a week per zone
  const rain = page.getByRole('button', { name: /^Rain ahead · (Rain (likely|possible)|No rain expected)/ })
  await expect(rain).toHaveAttribute('aria-expanded', 'false')
  await rain.click()
  await expect(
    page
      .getByRole('list', { name: /^Rain ahead at / })
      .first()
      .getByRole('listitem'),
  ).toHaveCount(7)
  await page.getByRole('button', { name: 'Rain ahead', exact: true }).click()

  // The list: a row per field without the cards' moisture lines, remembered in this browser
  await page.getByRole('group', { name: 'View' }).getByRole('button', { name: 'List' }).click()
  await expect(page.getByRole('button', { name: 'List' })).toHaveAttribute('aria-pressed', 'true')
  const rows = page.locator('[data-field-row]')
  await expect(rows.first()).toBeVisible()
  await expect(page.getByText(/% soil moisture · AD /)).toHaveCount(0)
  // A rainfed planting says so in its row, as on its card
  await expect(rows.filter({ hasText: DEMO.rainfedField }).first()).toContainText('Rainfed')
  await page.reload()
  await expect(rows.first()).toBeVisible()
  const fieldCount = await rows.count()

  // Needs water first: one list across farms, the first row at the most urgent status shown
  await page.getByLabel('Order', { exact: true }).selectOption('urgent')
  await expect(page.getByRole('heading', { name: /^Farm: / })).toHaveCount(0)
  await expect(rows).toHaveCount(fieldCount)
  const statuses = page.getByRole('group', { name: 'Show fields by status' })
  const first = statuses.getByRole('button').first()
  const [, label, count] = (await first.textContent())!.match(
    /(Irrigate|Caution|No canopy data|OK|Full|Stressed|Stress coming|No stress|Season ended)\s*(\d+) fields?/,
  )!
  await expect(rows.first()).toContainText(label)

  // A status count shows only the fields at that status, until Show all
  await first.click()
  await expect(first).toHaveAttribute('aria-pressed', 'true')
  await expect(rows).toHaveCount(Number(count))
  for (const row of await rows.all()) await expect(row).toContainText(label)
  await statuses.getByRole('button', { name: 'Show all' }).click()
  await expect(rows).toHaveCount(fieldCount)
  await page.getByLabel('Order', { exact: true }).selectOption('system')
  await page.getByRole('button', { name: 'Cards' }).click()
  await expect(page.getByRole('heading', { name: /^Field: / }).first()).toBeVisible()

  // A system's name links to its page: its irrigation, and its weather zone's week ahead
  const system = page.getByRole('heading', { name: /^Irrigation system: / }).first()
  const name = (await system.textContent())!.replace('Irrigation system:', '').trim()
  await expect(page.getByRole('link', { name: `View ${name}`, exact: true })).toBeVisible()
  await system.getByRole('link', { name }).click()
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(`Irrigation system: ${name}`)
  await expect(page.getByRole('heading', { name: /^Weather/, level: 2 })).toBeVisible()
  await page.getByRole('link', { name: 'View detailed weather charts for this location →' }).click()
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Weather:')
  await expect(page.getByRole('heading', { name: 'Weather charts', level: 2 })).toBeVisible()
})

test('the Weather tab has the week ahead and a season of weather per zone', async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto('/')
  await page.getByRole('navigation', { name: 'Main' }).getByRole('link', { name: 'Weather', exact: true }).click()
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Weather')
  const week = page.getByRole('list', { name: /^Forecast for / }).first()
  await expect(week.getByRole('listitem')).toHaveCount(7)
  await expect(week.getByRole('listitem').first()).toContainText('Today')
  await expect(week.getByText('Thunderstorms')).toBeVisible()
  await expect(week).toContainText('%')
  await page.locator('main h2 a').first().click()
  // A zone's address is its location
  await expect(page).toHaveURL(/\/weather\/-?\d+\.\d{2},-?\d+\.\d{2}$/)
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Weather:')
  await expect(page.getByRole('heading', { name: 'The week ahead' })).toBeVisible()
  await expect(page.getByLabel('Add the total since')).toBeVisible()
  expect(errors).toEqual([])
})

test('an announcement is composed with a live preview, saved and sent as a test', async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto('/admin/announcements/new')
  await page.getByRole('textbox', { name: 'Subject' }).fill('E2E news for {{first_name|you}}')
  const message = page.getByRole('textbox', { name: 'Message' })
  await message.fill('Hi ')
  await page.getByRole('button', { name: 'Insert first name placeholder' }).click()
  await message.press('End')
  await message.pressSequentially(', see ')
  await page.getByRole('button', { name: 'Bold', exact: true }).click()
  await expect(message).toHaveValue('Hi {{first_name}}, see **bold text**')
  // The preview is the email as the server renders it
  const preview = page.frameLocator('iframe[title="Announcement preview"]')
  await expect(preview.locator('strong', { hasText: 'bold text' })).toBeVisible()
  await expect(preview.getByText('Unsubscribe from WISP announcements')).toBeVisible()

  await page.getByRole('radio', { name: /Joined since a date/ }).check()
  await expect(page.getByLabel('Date', { exact: true })).toBeVisible()
  await page.getByRole('radio', { name: /Everyone/ }).check()
  await page.getByRole('button', { name: 'Save draft' }).click()

  await expect(page.getByRole('heading', { level: 1 })).toHaveText('E2E news for {{first_name|you}}')
  await expect(page.getByText(/Audience:\s*Everyone/)).toBeVisible()
  await page.getByRole('button', { name: 'Send a test to me' }).click()
  await expect(page.getByText(/Test sent to /)).toBeVisible()
  await expect(page.getByRole('button', { name: /^Send to \d+ (person|people)$/ })).toBeVisible()
  // The page, not the email in its sandboxed frame, which axe can't reach
  const results = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
    .exclude('iframe')
    .analyze()
  expect(results.violations.map((violation) => violation.id)).toEqual([])

  // Deleted again, so the list stays as the scans see it
  await page.getByRole('link', { name: 'Edit' }).click()
  page.once('dialog', (dialog) => dialog.accept())
  await page.getByRole('button', { name: 'Delete draft' }).click()
  await expect(page.getByRole('heading', { name: 'Announcements', level: 1 })).toBeVisible()
  expect(errors).toEqual([])
})

test('the Admin tab switches between Users, Weather data and Usage', async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto('/admin/users')
  const pills = page.getByRole('navigation', { name: 'Admin' })
  await expect(pills.getByRole('link', { name: 'Users' })).toHaveAttribute('aria-current', 'page')
  await pills.getByRole('link', { name: 'Weather data' }).click()
  await expect(page.getByRole('heading', { name: 'Weather data', level: 1 })).toBeVisible()
  await pills.getByRole('link', { name: 'Usage' }).click()
  await expect(page.getByRole('heading', { name: 'Usage', level: 1 })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Getting started' })).toBeVisible()
  expect(errors).toEqual([])
  await expect(page.getByRole('navigation', { name: 'Main' }).getByRole('link', { name: 'Admin' })).toHaveAttribute(
    'aria-current',
    'page',
  )
})

test('the map lists the fields and selects a system from the list', async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto('/map')
  await expect(page.getByRole('heading', { name: 'Map', level: 1 })).toBeVisible()
  const list = page.getByRole('complementary', { name: 'Fields' })
  await expect(list.getByRole('heading', { name: /^Field: / }).first()).toBeVisible()

  // Selecting a field opens its system's panel over the map and marks the card
  const select = list.getByRole('button', { name: /on the map$/ }).first()
  await select.click()
  await expect(select).toHaveAttribute('aria-pressed', 'true')
  const panel = page.getByRole('region', { name: /^System: / })
  await expect(panel).toBeVisible()
  // The system's View and Edit, and each field's; the list's cards only select
  await expect(panel.locator('header').getByRole('link', { name: /^View / })).toHaveAttribute('href', /\/systems\/\d+$/)
  await expect(panel.locator('header').getByRole('link', { name: /^Edit / })).toHaveAttribute(
    'href',
    /\/systems\/\d+\/edit$/,
  )
  await expect(
    panel
      .locator('li')
      .first()
      .getByRole('link', { name: /^Edit / }),
  ).toHaveAttribute('href', /\/setup\?field=\d+$/)
  await expect(list.getByRole('link', { name: /^View / })).toHaveCount(0)

  // A field's Edit opens its form in Setup
  await panel
    .locator('li')
    .first()
    .getByRole('link', { name: /^Edit / })
    .click()
  await expect(page.getByRole('dialog', { name: /^Edit / })).toBeVisible()
  await expect(page).not.toHaveURL(/field=/)
  await page.goBack()

  // Escape closes the panel; a card's View opens the field
  await list
    .getByRole('button', { name: /on the map$/ })
    .first()
    .click()
  await expect(panel).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(panel).toBeHidden()
  await list
    .getByRole('button', { name: /on the map$/ })
    .first()
    .click()
  await panel
    .getByRole('link', { name: /^View / })
    .nth(1)
    .click()
  await expect(page).toHaveURL(/\/(fields|plantings)\/\d+/)
  expect(errors).toEqual([])
})

test("the map outlines the systems' weather zones, with their weather on hover and in a panel", async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto('/map')
  await expect(page.locator('.maplibregl-canvas')).toBeVisible()
  // The map flies the system to 170 px left of center beside its panel, at zoom 13.5 or more, where
  // its zone is about a thousand pixels across: somewhere to the left of the system is in it with
  // nothing else there
  await page
    .getByRole('complementary', { name: 'Fields' })
    .getByRole('button', { name: `Show system ${DEMO.splitSystem} on the map` })
    .click()
  const box = (await page.locator('.maplibregl-canvas').boundingBox())!
  const [x, y] = [box.x + box.width / 2 - 170, box.y + box.height / 2]
  const label = page.locator('div[aria-hidden="true"]').filter({ hasText: /^(Past|Next) \d+ days?:|^No weather/ })
  const spots = [-160, -200, -240].flatMap((dx) => [0, -120, 120].map((dy) => [x + dx, y + dy] as const))
  let spot: readonly [number, number] | undefined
  await expect(async () => {
    for (const at of spots) {
      await page.mouse.move(...at)
      if (await label.isVisible({ timeout: 300 }).catch(() => false)) return void (spot = at)
    }
    throw new Error('no spot in a zone with nothing else there')
  }).toPass({ timeout: 10_000 })

  // A click there selects the zone: its weather, the week ahead and a link to its weather page
  await page.mouse.click(...spot!)
  const panel = page.getByRole('region', { name: /^Weather zone: \d+\.\d\d°N, \d+\.\d\d°W$/ })
  await expect(panel).toBeVisible()
  await expect(panel.getByRole('link', { name: 'View its weather' })).toHaveAttribute(
    'href',
    /\/weather\/[\d.-]+,[\d.-]+$/,
  )
  await expect(page.getByRole('region', { name: /^System: / })).toBeHidden()
  await page.keyboard.press('Escape')
  await expect(panel).toBeHidden()

  // The layer can be switched off: no zone's weather on hover, and a click there selects nothing
  await page.getByRole('button', { name: /^Layers/ }).click()
  const zones = page.getByRole('checkbox', { name: 'Weather zones' })
  await expect(zones).toBeChecked()
  await zones.uncheck()
  await page.keyboard.press('Escape')
  await page.mouse.move(...spot!)
  await page.mouse.move(spot![0] + 1, spot![1])
  await expect(label).toBeHidden()
  await page.mouse.click(...spot!)
  await expect(panel).toBeHidden()
  await page.getByRole('button', { name: /^Layers/ }).click()
  await page.getByRole('checkbox', { name: 'Weather zones' }).check()
  expect(errors).toEqual([])
})

test("the map's list is the operation as a tree, selected at any level", { tag: '@phone' }, async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto('/map')
  await expect(page.locator('.maplibregl-canvas')).toBeVisible()
  const list = page.getByRole('complementary', { name: 'Fields' })
  const panel = page.locator('[data-map-panel]')

  // A farm or an irrigation group zooms the map to its systems, and opens its panel: its Edit, and
  // what's in it, each selecting itself
  const farm = list.getByRole('button', { name: `Zoom the map to the farm ${DEMO.farm}` })
  await farm.click()
  await expect(farm).toHaveAttribute('aria-pressed', 'true')
  const farmPanel = page.getByRole('region', { name: `Farm: ${DEMO.farm}` })
  await expect(farmPanel.getByRole('link', { name: `Edit ${DEMO.farm}` })).toHaveAttribute('href', /\/setup\?farm=\d+$/)
  await expect(farmPanel.getByRole('button', { name: /^Show (system|the irrigation group) / }).first()).toBeVisible()
  const group = list.getByRole('button', { name: `Zoom the map to the irrigation group ${DEMO.gauge}` })
  await group.click()
  await expect(group).toHaveAttribute('aria-pressed', 'true')
  await expect(farm).toHaveAttribute('aria-pressed', 'false')
  await expect(page.getByRole('region', { name: `Group: ${DEMO.gauge}` })).toBeVisible()
  await expect(panel).toHaveCount(1) // the group's, in place of the farm's

  // A system opens its panel, naming its farm, which selects it
  const system = list.getByRole('button', { name: `Show system ${DEMO.splitSystem} on the map` })
  await system.click()
  await expect(system).toHaveAttribute('aria-pressed', 'true')
  const systemPanel = page.getByRole('region', { name: `System: ${DEMO.splitSystem}` })
  await expect(systemPanel).toBeVisible()
  await expect(systemPanel.locator('li[aria-current="true"]')).toHaveCount(0)

  // A card in the panel selects its field, there and in the list; View opens the field
  const east = new RegExp(`${literal(DEMO.splitEast)}.*on the map$`)
  await systemPanel.getByRole('button', { name: east }).click()
  await expect(systemPanel.locator('li[aria-current="true"]')).toContainText(DEMO.splitEast)
  await expect(list.getByRole('button', { name: east })).toHaveAttribute('aria-pressed', 'true')
  await expect(system).toHaveAttribute('aria-pressed', 'false')

  // The filter keeps a match with its parents
  await list.getByRole('searchbox', { name: 'Search fields' }).fill(DEMO.splitEast)
  await expect(list.getByRole('button', { name: /on the map$/ })).toHaveCount(2) // the system and the field
  await expect(list.getByRole('button', { name: /^Zoom the map to the farm / })).toHaveCount(1)
  await expect(list.getByText(/^1 farm · 1 system · 1 field · \d+ plantings?$/)).toBeVisible()

  await systemPanel.getByRole('link', { name: `View ${DEMO.splitEast}` }).click()
  await expect(page).toHaveURL(/\/(fields|plantings)\/\d+/)
  expect(errors).toEqual([])
})

test('roads and place names over the imagery switch off, and stay off', async ({ page }) => {
  await page.goto('/map')
  await page.getByRole('group', { name: 'Basemap' }).getByRole('button', { name: 'Satellite' }).click()
  await page.getByRole('button', { name: /^Layers/ }).click()
  const roads = page.getByRole('checkbox', { name: /Roads and place names/ })
  await expect(roads).toBeChecked()
  await roads.uncheck()
  await page.reload()
  await page.getByRole('button', { name: /^Layers/ }).click()
  await expect(page.getByRole('checkbox', { name: /Roads and place names/ })).not.toBeChecked()
  // The street map has its own: no checkbox there
  await page.getByRole('group', { name: 'Basemap' }).getByRole('button', { name: 'Map', exact: true }).click()
  await expect(page.getByRole('checkbox', { name: /Roads and place names/ })).toHaveCount(0)
  await page.getByRole('group', { name: 'Basemap' }).getByRole('button', { name: 'Satellite' }).click()
  await page.getByRole('checkbox', { name: /Roads and place names/ }).check()
})

test('a map layer that fails says so, and the rest of the map carries on', async ({ page }) => {
  const errors = watchErrors(page)
  await page.route('**/mesonet.agron.iastate.edu/**', (route) => route.abort())
  await page.goto('/map')
  await page.getByRole('button', { name: 'Layers' }).click()
  const layers = page.getByRole('group', { name: 'Map layers' })
  await layers.getByRole('radio', { name: /Radar now/ }).check()
  await expect(page.getByRole('status').filter({ hasText: "Radar now isn't loading" })).toBeVisible()
  await expect(layers.getByText('Unavailable', { exact: true })).toBeVisible()

  // Systems still select
  await page
    .getByRole('complementary', { name: 'Fields' })
    .getByRole('button', { name: /on the map$/ })
    .first()
    .click()
  await expect(page.getByRole('region', { name: /^System: / })).toBeVisible()
  expect(errors).toEqual([])
})

test('the Drought Monitor layer gives the category at the selected system', async ({ page }) => {
  // A moderate drought over all of Wisconsin, so the test doesn't depend on this week's map
  const wisconsin = [
    [-93, 42],
    [-86, 42],
    [-86, 47.5],
    [-93, 47.5],
    [-93, 42],
  ]
  await page.route('**/USDM_current/FeatureServer/0/query**', (route) =>
    route.fulfill({
      json: {
        type: 'FeatureCollection',
        features: [1, 0].map((dm) => ({
          type: 'Feature',
          properties: { DM: dm, ValidStart: Date.UTC(2026, 9, 13) },
          geometry: { type: 'Polygon', coordinates: [wisconsin] },
        })),
      },
    }),
  )
  await page.goto('/map')
  await page.getByRole('button', { name: 'Layers' }).click()
  const layers = page.getByRole('group', { name: 'Map layers' })
  await layers.getByRole('checkbox', { name: /Drought Monitor/ }).check()
  await expect(layers.getByText('Map for Oct 13')).toBeVisible()

  await page
    .getByRole('complementary', { name: 'Fields' })
    .getByRole('button', { name: /on the map$/ })
    .first()
    .click()
  await expect(page.getByRole('region', { name: /^System: / })).toContainText('D1 Moderate drought')
})

test("tapping the map gives the rain layer's value there", { tag: '@phone' }, async ({ page }) => {
  // A blank tile for the picture, and 18.9 mm from NOAA's MRMS at any point
  const blank = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
    'base64',
  )
  await page.route('**/mrms_qpe/ImageServer/exportImage**', (route) =>
    route.fulfill({ body: blank, contentType: 'image/png' }),
  )
  await page.route('**/mrms_qpe/ImageServer/identify**', (route) => route.fulfill({ json: { value: '18.9' } }))
  await page.goto('/map')
  await page.getByRole('button', { name: 'Layers' }).click()
  const layers = page.getByRole('group', { name: 'Map layers' })
  await layers.getByRole('radio', { name: /last 24 hours/ }).check()
  await page.getByRole('button', { name: 'Close map layers' }).click()

  // A tap away from the systems (the map's lower left corner)
  const map = page.getByRole('application', { name: /Map of the operation/ })
  const box = (await map.boundingBox())!
  await map.click({ position: { x: 30, y: box.height - 60 } })
  const tooltip = page.getByRole('status').filter({ hasText: 'Rain, last 24 hours' })
  await expect(tooltip).toContainText('About 0.74 in')
})

test('the radar layer gives the reflectivity under a tap', async ({ page }) => {
  // Every radar tile a solid 20 dBZ, in IEM's palette
  const tile = readFileSync(new URL('./fixtures/radar-20dbz.png', import.meta.url))
  await page.route('**/nexrad-n0q-900913/**', (route) => route.fulfill({ body: tile, contentType: 'image/png' }))
  await page.goto('/map')
  await page.getByRole('button', { name: 'Layers' }).click()
  await page
    .getByRole('group', { name: 'Map layers' })
    .getByRole('radio', { name: /Radar now/ })
    .check()
  await page.getByRole('button', { name: 'Close map layers' }).click()

  const map = page.getByRole('application', { name: /Map of the operation/ })
  const box = (await map.boundingBox())!
  await map.click({ position: { x: 30, y: box.height - 60 } })
  await expect(page.getByRole('status').filter({ hasText: 'Radar now' })).toContainText('Light rain (20 dBZ)')
})

test('quick setup suggests the soil from the soil survey under the system', { tag: '@phone' }, async ({ page }) => {
  // The survey's answer for a Central Sands pivot: mostly Plainfield sand, some Coloma loamy sand
  await page.route('**/Tabular/post.rest', (route) =>
    route.fulfill({
      json: {
        Table: [
          ['mukey', 'share', 'muname', 'compname', 'texdesc'],
          ['423976', '0.55', 'Plainfield sand, 2 to 6 percent slopes', 'Plainfield', 'Sand'],
          ['423954', '0.45', 'Coloma loamy sand, 6 to 12 percent slopes', 'Coloma', 'Loamy sand'],
        ],
      },
    }),
  )
  await page.goto('/setup/start')
  await expect(page.getByText('Place the pivot on the map to see the soils around it')).toBeVisible()
  await expect(page.getByRole('textbox', { name: 'Radius' })).toHaveValue('')
  await page.getByRole('application', { name: /click to place the pivot/ }).click()
  await expect(page.getByRole('textbox', { name: 'Radius' })).not.toHaveValue('')
  await expect(page.getByText(/Soil survey:\s*mostly Sand/)).toBeVisible()
  // The menu gives each soil's share, the survey's main one chosen
  const soil = page.getByLabel('Soil', { exact: true })
  await expect(soil.locator('option:checked')).toHaveText('Sand, 55% of the pivot')
  await expect(soil.locator('option').nth(1)).toHaveText('Loamy Sand, 45% of the pivot')
  await expect(page.getByText('From the soil survey')).toBeVisible()

  // A soil the survey doesn't find there is noted, with the main one offered
  await soil.selectOption({ label: 'Muck' })
  await expect(page.getByText("The soil survey finds no muck under the pivot; it's mostly sand.")).toBeVisible()
  await page.getByRole('button', { name: 'Use Sand' }).click()
  await expect(soil.locator('option:checked')).toHaveText('Sand, 55% of the pivot')
})

test("quick setup makes fields without crops, then Setup's next steps add each planting", async ({ page }) => {
  await page.goto('/setup/start')
  await page.getByLabel('Farm', { exact: true }).selectOption({ label: 'A new farm…' })
  // The save waits for what the server needs, saying what's missing
  const save = page.getByRole('button', { name: 'Save and continue' })
  await expect(save).toBeDisabled()
  await expect(page.getByText(/^Still needed: a farm name, the pivot's name and its location/)).toBeVisible()
  await page.getByLabel('Farm name').fill('Zz Start Farm')
  await page.getByLabel('Name', { exact: true }).fill('Zz Pivot')
  await expect(page.getByText('Still needed: its location (click the map).')).toBeVisible()
  await placeSystem(page)
  await expect(save).toBeEnabled()
  await expect(page.getByLabel('Crop', { exact: true })).toHaveCount(0)
  await page.getByLabel('Field name').fill('Zz North')
  await page.getByRole('button', { name: 'Save and continue' }).click()

  const steps = page.getByRole('region', { name: 'Next steps' })
  await expect(steps).toContainText('Zz North')
  await steps.getByRole('button', { name: 'Add a planting to Zz North' }).click()
  const dialog = page.getByRole('dialog', { name: /^Add a \d{4} planting to Zz North/ })
  await dialog.getByLabel('Crop', { exact: true }).selectOption({ label: 'Soybean' })
  await dialog.getByRole('button', { name: 'Add planting' }).click()
  await expect(page.getByRole('region', { name: 'Set up' })).toContainText('Zz Pivot and its fields are set up')

  // Leave the demo account as it was
  await page.getByRole('button', { name: 'Edit Zz Start Farm' }).click()
  page.once('dialog', (confirm) => confirm.accept())
  await page.getByRole('button', { name: 'Delete this farm' }).click()
  await expect(page.getByRole('heading', { name: 'Farm: Zz Start Farm' })).toHaveCount(0)
})

test('quick setup can save a farm alone, leaving the rest for later', async ({ page }) => {
  await page.goto('/setup/start')
  await page.getByLabel('Farm', { exact: true }).selectOption({ label: 'A new farm…' })
  await page.getByLabel('Farm name').fill('Zz Later Farm')
  await page.getByRole('button', { name: 'set up an irrigation system later' }).click()
  await expect(page.getByRole('heading', { name: '3. Fields' })).toHaveCount(0)
  await page.getByRole('button', { name: 'Save the farm' }).click()
  await expect(page.getByRole('region', { name: 'Next steps' })).toContainText(
    'Add an irrigation system to Zz Later Farm',
  )

  await page.getByRole('button', { name: 'Edit Zz Later Farm' }).click()
  page.once('dialog', (confirm) => confirm.accept())
  await page.getByRole('button', { name: 'Delete this farm' }).click()
  await expect(page.getByRole('heading', { name: 'Farm: Zz Later Farm' })).toHaveCount(0)
})

/** Drags a map handle (a marker, found by its title) by dx, dy pixels, once the map has settled */
/** Clicks the system picker's map once MapLibre is ready for it */
async function placeSystem(page: Page) {
  const map = page.getByRole('application', { name: /click to place the / })
  await expect(map.locator('canvas')).toBeVisible()
  await map.click()
}

async function dragHandle(page: Page, title: string, dx: number, dy: number) {
  const handle = page.getByTitle(title, { exact: true }).first()
  await handle.scrollIntoViewIfNeeded()
  let box = await handle.boundingBox()
  await expect
    .poll(async () => {
      const last = box
      box = await handle.boundingBox()
      return JSON.stringify(box) === JSON.stringify(last)
    })
    .toBe(true)
  box = box!
  const [x, y] = [box.x + box.width / 2, box.y + box.height / 2]
  await page.mouse.move(x, y)
  await page.mouse.down()
  await page.mouse.move(x + dx / 2, y + dy / 2, { steps: 5 })
  await page.mouse.move(x + dx, y + dy, { steps: 5 })
  await page.mouse.up()
}

test('a linear is sized by dragging a corner and turned by its handle', async ({ page }) => {
  const name = `Ditch linear ${Date.now()}`
  await page.goto('/systems/new')
  await page.getByLabel('Name', { exact: true }).fill(name)
  await page.getByRole('radio', { name: /Linear/ }).check()
  await placeSystem(page)
  const travel = page.getByRole('textbox', { name: 'Travel distance' })
  const before = await travel.inputValue()
  await dragHandle(page, 'Drag to resize the linear', 0, 20)
  await expect(travel).not.toHaveValue(before)
  const direction = page.getByLabel('Direction of travel', { exact: true })
  await expect(direction).toHaveValue('0')
  await dragHandle(page, 'Drag to turn the linear', 60, 0)
  await expect(direction).not.toHaveValue('0')
  await page.getByRole('button', { name: 'Add irrigation system' }).click()
  const row = page.getByRole('heading', { name: `Irrigation system: ${name}` }).locator('../..')
  // Dragging a corner by pixels can nudge the length a few feet as well as the travel
  await expect(row).toContainText(/1,[23]\d\d ft long, travels [\d,]+ ft at \d+° from north/)

  // Delete it again (from its edit page): a new system sorts first on the dashboard, and its weather
  // cell has no seeded weather, so leaving it would change what later tests open
  await row.getByRole('link', { name: `Edit ${name}` }).click()
  // A saved system's kind is one line until Change shows the choices, the current one focused
  await expect(page.getByRole('radio', { name: /Linear/ })).toHaveCount(0)
  await page.getByRole('button', { name: 'Change the kind of system' }).click()
  await expect(page.getByRole('radio', { name: /Linear/ })).toBeChecked()
  await expect(page.getByRole('radio', { name: /Linear/ })).toBeFocused()
  // A saved system's map is locked until Edit on the map; Cancel puts back what the map changed
  const saved = await travel.inputValue()
  await expect(page.getByRole('application', { name: /^Map of the linear/ }).locator('canvas')).toBeVisible()
  await expect(page.getByTitle('Drag to resize the linear', { exact: true })).toHaveCount(0)
  await page.getByRole('button', { name: 'Edit on the map' }).click()
  await dragHandle(page, 'Drag to resize the linear', 0, 20)
  await expect(travel).not.toHaveValue(saved)
  await page.getByRole('button', { name: 'Cancel' }).click()
  await expect(travel).toHaveValue(saved)
  await expect(page.getByRole('button', { name: 'Edit on the map' })).toBeVisible()
  page.once('dialog', (dialog) => dialog.accept())
  await page.getByRole('button', { name: 'Delete this linear' }).click()
  await expect(page.getByRole('heading', { name: 'Setup', level: 1 })).toBeVisible()
  await expect(page.getByRole('heading', { name: `Irrigation system: ${name}` })).toHaveCount(0)
})

test('a traveler is placed with a click and keeps no shape', async ({ page }) => {
  const name = `Lane ${Date.now()}`
  await page.goto('/systems/new')
  await page.getByLabel('Name', { exact: true }).fill(name)
  await page.getByRole('radio', { name: /^Traveler/ }).check()
  await expect(page.getByRole('textbox', { name: 'Radius' })).toHaveCount(0)
  await expect(page.getByRole('textbox', { name: 'Flow' })).toBeVisible()
  const map = page.getByRole('application', { name: /click to place the traveler/ })
  await expect(map.locator('canvas')).toBeVisible()
  await map.click()
  await expect(page.getByText('Drag the pin to move the traveler.')).toBeVisible()
  await page.getByLabel('Equipment', { exact: true }).fill('Hard hose reel #9')
  await page.getByRole('button', { name: 'Add irrigation system' }).click()
  const heading = page.getByRole('heading', { name: `Irrigation system: ${name} (traveler)` })
  const row = heading.locator('../..')
  await expect(row).toContainText('Hard hose reel #9')
  await expect(row).not.toContainText('radius')

  await row.getByRole('link', { name: `Edit ${name}` }).click()
  page.once('dialog', (dialog) => dialog.accept())
  await page.getByRole('button', { name: 'Delete this traveler' }).click()
  await expect(page.getByRole('heading', { name: 'Setup', level: 1 })).toBeVisible()
  await expect(heading).toHaveCount(0)
})

test("a partial circle's arc is set by dragging its ends", async ({ page }) => {
  await page.goto('/systems/new')
  await placeSystem(page)
  await page.getByText('Partial circle', { exact: true }).click()
  await expect(page.getByRole('radio', { name: 'Partial circle' })).toBeChecked()
  const arcEnd = page.getByRole('textbox', { name: 'Arc ends at' })
  await expect(arcEnd).toHaveValue('270')
  await dragHandle(page, 'Drag to set where the arc ends', 0, -80)
  await expect(arcEnd).not.toHaveValue('270')
})

test('a grid cell saves on Enter, and Escape cancels without saving', async ({ page }) => {
  await page.goto(await firstPlantingPath(page))
  const note = `Checked gauge ${Date.now()}`
  const cell = page.locator('[data-grid="days"][data-row="2"][data-col="4"]')

  await cell.click()
  await page.keyboard.type(note)
  await page.keyboard.press('Enter')
  await expect(page.locator('[data-grid="days"][data-row="2"][data-col="4"]')).toContainText(note)

  const writes: string[] = []
  page.on('request', (request) => {
    if (request.method() !== 'GET') writes.push(request.url())
  })
  // Enter moved on and opened the cell below
  await expect(page.getByRole('textbox', { name: /^Notes, / })).toBeFocused()
  await page.keyboard.type('not saved')
  await page.keyboard.press('Escape')
  await expect(page.getByRole('textbox', { name: /^Notes, / })).toBeHidden()
  expect(writes).toEqual([])

  await page.reload()
  await expect(page.locator('[data-grid="days"][data-row="2"][data-col="4"]')).toContainText(note)
  await expect(page.locator('[data-grid="days"][data-row="3"][data-col="4"]')).not.toContainText('not saved')

  // Clear the note again so reruns start from the seed
  await page.locator('[data-grid="days"][data-row="2"][data-col="4"]').click()
  await page.keyboard.press('Control+a')
  await page.keyboard.press('Delete')
  await page.keyboard.press('Enter')
  await page.keyboard.press('Escape')
  await expect(page.locator('[data-grid="days"][data-row="2"][data-col="4"]')).not.toContainText(note)
})

test(
  'an open grid cell keeps its column width, and clicking another cell opens that one',
  { tag: '@phone' },
  async ({ page }) => {
    await page.goto(await firstPlantingPath(page))
    const cell = (row: number, col: number) => page.locator(`[data-grid="days"][data-row="${row}"][data-col="${col}"]`)
    const widths = () =>
      page
        .locator('table:has([data-grid="days"]) thead th')
        .evaluateAll((ths) => ths.map((th) => Math.round(th.getBoundingClientRect().width)))
    // The table renders after the page's first paint; wait as long as a click would
    await cell(2, 0).waitFor()
    const before = await widths()
    expect(before.length).toBeGreaterThan(0)

    await cell(2, 0).click()
    await expect(page.getByRole('textbox', { name: /^Rain, / })).toBeFocused()
    expect(await widths()).toEqual(before)

    await cell(4, 1).click()
    await expect(page.getByRole('textbox', { name: /^Irrigation, / })).toBeFocused()
    await page.keyboard.press('Escape')
  },
)

test('planned irrigation updates the projection', async ({ page }) => {
  await page.goto(await firstPlantingPath(page))
  await expect(page.locator('main h1')).toBeVisible()
  const forecast = page.getByRole('heading', { name: /^Next \d+ days$/ })
  test.skip(!(await forecast.isVisible()), 'the season has no projection on this date')

  const plan = page.locator('[data-grid="forecast"][data-row="1"][data-col="0"]')
  // The projected AD the day after
  const nextAd = page.locator('tbody:has([data-grid="forecast"]) > tr').nth(2).locator('td').nth(3)
  const before = await nextAd.textContent()

  await plan.click()
  await page.keyboard.type('1.5')
  // Timed in the page, checking every frame (expect's retries back off)
  const cell = await nextAd.elementHandle()
  const changed = page.waitForFunction(
    ([element, text]) => element!.textContent !== text && performance.now(),
    [cell, before] as const,
    { polling: 'raf' },
  )
  const started = await page.evaluate(() => performance.now())
  await page.keyboard.press('Enter')
  const elapsed = Math.round(((await (await changed).jsonValue()) as number) - started)
  // The target is 300 ms; CI machines are slower, so this only catches regressions
  console.log(`projection updated in ${elapsed} ms`)
  expect(elapsed).toBeLessThan(1000)

  // Clear it again so reruns start from the seed
  await page.keyboard.press('Escape')
  await plan.click()
  await page.keyboard.press('Control+a')
  await page.keyboard.press('Delete')
  await page.keyboard.press('Enter')
  await expect(nextAd).toHaveText(before!)
})

test('time travel shows a field on an earlier day, read-only, and returns to today', async ({ page }) => {
  await page.goto(await firstPlantingPath(page))
  const rewind = page.getByRole('button', { name: 'View this field on an earlier date' })
  // Once the page is drawn, or the button's absence means nothing
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible()
  test.skip(!(await rewind.isVisible()), "the field's season has no earlier days on this date")

  // The date picker flies out to the clock's left, leaving the clock where it was
  const at = async () => (await rewind.boundingBox())!.x
  const before = await at()
  await rewind.click()
  await expect(rewind).toHaveAttribute('aria-expanded', 'true')
  const date = page.getByLabel('Date to view')
  await expect(date).toBeFocused()
  expect((await date.boundingBox())!.x).toBeLessThan(before)
  expect(await at()).toBe(before)
  // As tall as the clock and the row's other buttons
  const heights = async () =>
    page
      .locator('#time-travel input, #time-travel button, #time-travel a, button[aria-controls="time-travel"]')
      .evaluateAll((elements) => [...new Set(elements.map((element) => element.getBoundingClientRect().height))])
  expect(await heights()).toHaveLength(1)

  // A week before the latest day it offers, within the season
  const [min, max] = [await date.getAttribute('min'), await date.getAttribute('max')]
  const week = new Date(`${max}T00:00:00Z`)
  week.setUTCDate(week.getUTCDate() - 7)
  const pick = [week.toISOString().slice(0, 10), min!].sort().at(-1)!
  await date.fill(pick)
  await page.getByRole('button', { name: 'View', exact: true }).click()

  await expect(page).toHaveURL(new RegExp(`as_of=${pick}`))
  const banner = page.getByRole('status').filter({ hasText: 'Viewing' })
  await expect(banner).toContainText('as of')
  await expect(banner.getByRole('link', { name: 'Return to today' })).toBeVisible()
  await expect(page).toHaveTitle(/^As of /)
  await expect(page.locator('[data-grid]')).toHaveCount(0)
  await expect(page.getByRole('link', { name: 'Edit in setup' })).toHaveCount(0)
  // The picker starts open on the day in view, with Today beside it, and the clock hasn't moved
  await expect(rewind).toHaveAttribute('aria-expanded', 'true')
  await expect(date).toHaveValue(pick)
  // View does nothing on the date already in view, so it waits for another
  const view = page.getByRole('button', { name: 'View', exact: true })
  await expect(view).toBeDisabled()
  if (pick !== max) {
    await date.fill(max!)
    await expect(view).toBeEnabled()
  }
  expect(await at()).toBe(before)
  expect(await heights()).toHaveLength(1)

  // Once the card scrolls away, a bar across the top keeps the date in view
  const topBar = page.getByTestId('time-travel-bar')
  await expect(topBar).toHaveCount(0)
  await page.evaluate(() => scrollTo(0, document.body.scrollHeight))
  await expect(topBar).toBeVisible()
  await expect(topBar).toContainText('as of')
  await page.evaluate(() => scrollTo(0, 0))
  await expect(topBar).toHaveCount(0)

  await page.locator('#time-travel').getByRole('link', { name: 'Return to today' }).click()
  await expect(page).not.toHaveURL(/as_of=/)
  await expect(banner).toHaveCount(0)
  await expect(rewind).toHaveAttribute('aria-expanded', 'false')
  await expect(page.getByRole('link', { name: 'Edit in setup' })).toBeVisible()
})

test('an irrigation group switches to entered rain only and back', async ({ page }) => {
  const planting = await firstPlantingPath(page)
  await page.goto(planting)
  // The section starts open, like the page's others
  const summary = page.locator('#season-summary')
  await expect(page.getByRole('button', { name: 'Season summary' })).toHaveAttribute('aria-expanded', 'true')
  await expect(summary).toContainText('Your gauge and the model')
  const note = page.getByText('Rain: only what you enter, plus the forecast for the days ahead.')
  await expect(note).toBeHidden()

  // The setting is the irrigation group's, in its dialog in Setup
  await page.goto('/setup')
  await page.getByRole('button', { name: `Edit ${DEMO.firstFieldGroup}`, exact: true }).click()
  const dialog = page.getByRole('dialog')
  const setting = (name: RegExp) => dialog.getByRole('radio', { name })
  await setting(/^Only the rain you enter/).check()
  await dialog.getByRole('button', { name: 'Save' }).click()
  await expect(dialog).toBeHidden()

  await page.goto(planting)
  await expect(note).toBeVisible()
  await expect(summary).toContainText('Modeled rain not used in the balance')

  // Back to following the farm, as the seed had it, from the note's link to the group's dialog
  await page.getByRole('link', { name: 'Change this' }).click()
  await expect(page).toHaveURL(/\/setup/)
  await expect(setting(/^Only the rain you enter/)).toBeChecked()
  await setting(/^The farm's setting/).check()
  await dialog.getByRole('button', { name: 'Save' }).click()
  await expect(dialog).toBeHidden()
  await page.goto(planting)
  await expect(note).toBeHidden()
})

test('a field of plots lists each planting, on the dashboard, its page and Setup', async ({ page }) => {
  // The dashboard card lists the research field's four plots, each linking to its page
  await page.goto('/')
  const card = page
    .locator('main li')
    .filter({ has: page.getByRole('heading', { name: `Field: ${DEMO.researchField}` }) })
  const plantings = card.getByRole('list', { name: `Plantings on ${DEMO.researchField}` })
  await expect(plantings.getByRole('listitem')).toHaveCount(4)
  // Each named by its crop, with its dates below
  await expect(plantings.getByText('Soybean', { exact: true })).toBeVisible()
  await expect(plantings.getByText(/^Apr 1 – /).first()).toBeVisible()

  // The field page: its timeline, a status card per planting, and tabs for each
  await card.getByRole('link', { name: new RegExp(literal(DEMO.researchField)) }).click()
  await expect(page).toHaveURL(/\/fields\/\d+/)
  await expect(page.getByRole('heading', { name: `${DEMO.researchField}`, level: 1 })).toBeVisible()
  const timeline = page.getByRole('list', { name: new RegExp(`^Plantings on ${literal(DEMO.researchField)}`) })
  await expect(timeline.getByRole('link')).toHaveCount(4)
  await expect(page.getByRole('button', { name: 'Rain and irrigation on the field' })).toBeVisible()

  // A plot's page, named by its crop and variety: its size
  const tabs = page.getByRole('navigation', { name: 'Field and plantings' })
  const plot = new RegExp(`^${literal(DEMO.namedPlot.replace(/\)$/, ''))}`)
  await tabs.getByRole('link', { name: plot }).click()
  await expect(page).toHaveURL(/\/plantings\/\d+/)
  await expect(page.getByText('Part of the field: 300 × 60 ft (0.41 ac)')).toBeVisible()
  await expect(tabs.getByRole('link', { name: plot })).toHaveAttribute('aria-current', 'page')

  // Setup: each level labelled, the field's plantings on a timeline, each opening its form, with its size
  await page.goto('/setup')
  await expect(page.getByRole('heading', { name: `Farm: ${DEMO.researchFarm}` })).toBeVisible()
  await expect(page.getByRole('heading', { name: `Irrigation system: ${DEMO.researchSystemLabel}` })).toBeVisible()
  await expect(page.getByRole('link', { name: `View ${DEMO.researchSystem}`, exact: true })).toBeVisible()
  const bars = page.getByRole('list', { name: new RegExp(`^Plantings on ${literal(DEMO.researchField)}`) })
  await bars
    .getByRole('button', { name: /^Soybean/ })
    .first()
    .click()
  await page.getByRole('menuitem', { name: 'Edit planting' }).click()
  const dialog = page.getByRole('dialog', { name: new RegExp(`^Edit Soybean on ${literal(DEMO.researchField)}`) })
  await expect(dialog.getByRole('radio', { name: 'Part of the field' })).toBeChecked()
  await expect(dialog.getByLabel('Length', { exact: true })).toHaveValue('300')
  await expect(dialog.getByText('0.41 ac', { exact: true })).toBeVisible()
  await expect(dialog.getByRole('checkbox', { name: "Use the field's soil (Silt loam)" })).toBeChecked()

  // A plot can't be larger than the field
  await dialog.getByLabel('Length', { exact: true }).fill('300000')
  await expect(dialog.getByText(/^That's more than the field's [\d.,]+ ac\.$/)).toBeVisible()
  await expect(dialog.getByRole('button', { name: 'Save planting' })).toBeDisabled()

  // "Add the next planting" starts a new one the day after this one ends, the same size, asking
  // first about the length typed above
  page.once('dialog', (confirm) => {
    expect(confirm.message()).toContain('Length: 300')
    void confirm.accept()
  })
  await dialog.getByRole('button', { name: 'Add the next planting' }).click()
  const next = page.getByRole('dialog', { name: `Add the next planting on ${DEMO.researchField}` })
  // Its season and size show once a crop is chosen
  await next.getByLabel('Crop', { exact: true }).selectOption({ label: 'Wheat' })
  await expect(next.getByLabel('Length', { exact: true })).toHaveValue('300')
})

test("a new planting's harvest follows the crop, emergence and season length until one is typed", async ({ page }) => {
  const year = new Date().getFullYear()
  await page.goto('/setup')
  await page.getByRole('button', { name: `Add a planting to ${DEMO.firstField}` }).click()
  const dialog = page.getByRole('dialog', { name: new RegExp(`^Add a \\d{4} planting to ${literal(DEMO.firstField)}`) })
  const harvest = dialog.getByLabel('Harvest or kill', { exact: true })
  await dialog.getByLabel('Crop', { exact: true }).selectOption({ label: 'Soybean' })
  await expect(harvest).toHaveValue(`${year}-08-30`) // May 1 + 121 days
  // The crop's typical season shows in the blank season length
  const season = dialog.getByLabel('Season length', { exact: true })
  await expect(season).toHaveAttribute('placeholder', '121')
  await dialog.getByLabel('Emergence', { exact: true }).fill(`${year}-05-20`)
  await expect(harvest).toHaveValue(`${year}-09-18`)
  // Its own season length moves the suggestion, and blank goes back to the typical one
  await season.fill('100')
  await expect(harvest).toHaveValue(`${year}-08-28`)
  await season.fill('')
  await expect(harvest).toHaveValue(`${year}-09-18`)
  await harvest.fill(`${year}-10-01`)
  await dialog.getByLabel('Emergence', { exact: true }).fill(`${year}-05-25`)
  await expect(harvest).toHaveValue(`${year}-10-01`)
})

test('a crop without its own canopy curve follows a generic one, or readings only', async ({ page }) => {
  const year = new Date().getFullYear()
  await page.goto('/setup')
  await page.getByRole('button', { name: `Add a planting to ${DEMO.firstField}` }).click()
  const dialog = page.getByRole('dialog', { name: new RegExp(`^Add a \\d{4} planting to ${literal(DEMO.firstField)}`) })
  await dialog.getByLabel('Crop', { exact: true }).selectOption({ label: 'Onion' })
  // The canopy choices are under Settings, collapsed to a line saying what's in effect
  const settings = dialog.locator('summary')
  await expect(settings).toContainText('percent cover, following the slow, partial cover curve')
  await settings.click()
  const curves = dialog.getByRole('group', { name: 'Canopy curve' })
  await expect(curves.getByRole('radio', { name: /^Slow, partial cover \(suggested\)/ })).toBeChecked()
  await expect(curves.getByText('An approximation for onion')).toBeVisible()
  await expect(dialog.getByLabel('Harvest or kill', { exact: true })).toHaveValue(`${year}-08-29`) // May 1 + 120 days
  await curves.getByRole('radio', { name: 'No curve: readings only' }).check()
  await expect(curves.getByText('Irrigation scheduling works only if you enter percent cover regularly')).toBeVisible()
  await expect(settings).toContainText('percent cover, readings only')
  // A crop with its own curve has no choice
  await dialog.getByLabel('Crop', { exact: true }).selectOption({ label: 'Soybean' })
  await expect(curves).toBeHidden()
})

test("a perennial's cuttings restart its canopy, and are added and removed on its page", async ({ page }) => {
  await page.goto('/')
  const card = page.locator('main li').filter({ has: page.getByRole('heading', { name: `Field: ${DEMO.hayField}` }) })
  await card.getByRole('link').first().click()
  await expect(page).toHaveURL(/\/plantings\/\d+/)
  const cuttings = page.getByRole('region', { name: 'Cuttings' })
  await expect(cuttings.getByRole('list', { name: 'Cuttings' }).getByRole('listitem')).toHaveCount(3)

  const year = new Date().getFullYear()
  await cuttings.getByLabel('Cut on').fill(`${year}-09-20`)
  await cuttings.getByRole('button', { name: 'Add cutting' }).click()
  await expect(cuttings.getByRole('listitem')).toHaveCount(4)
  page.once('dialog', (dialog) => dialog.accept())
  await cuttings.getByRole('button', { name: 'Remove the Sep 20 cutting' }).click()
  await expect(cuttings.getByRole('listitem')).toHaveCount(3)
})

test('a new whole-field planting over another offers to replace it', async ({ page }) => {
  await page.goto('/setup')
  await page.getByRole('button', { name: `Add a planting to ${DEMO.firstField}` }).click()
  const dialog = page.getByRole('dialog', { name: new RegExp(`^Add a \\d{4} planting to ${literal(DEMO.firstField)}`) })
  // No scroll lock: the page keeps its scrollbar, so nothing shifts
  await expect(dialog).toBeVisible()
  expect(
    await page.evaluate(() => [getComputedStyle(document.body).overflow, document.body.style.paddingRight]),
  ).toEqual(['visible', ''])
  await dialog.getByLabel('Crop', { exact: true }).selectOption({ label: 'Soybean' })
  await expect(dialog.getByRole('radio', { name: /^Whole field/ })).toBeChecked()
  await expect(dialog.getByText(`This overlaps: ${DEMO.firstCrop}`)).toBeVisible()
  await dialog.getByLabel('Season start', { exact: true }).fill(`${new Date().getFullYear()}-08-01`)
  await expect(
    dialog.getByRole('checkbox', { name: new RegExp(`^Replace: end ${literal(DEMO.firstCrop)} on Jul 31`) }),
  ).toBeVisible()
  // Part of the field leaves the cabbage alone, but can't overlap a planting covering the whole field
  await dialog
    .locator('label')
    .filter({ hasText: /^\s*Part of the field\s*$/ })
    .click()
  await expect(dialog.getByText('This overlaps a planting covering the whole field')).toBeVisible()
})

test("a new whole-field planting offers the system's other fields free for its dates", async ({ page }) => {
  // A field sharing its system with another (firstField is alone on its system); nothing is saved
  await page.goto('/setup')
  await page.getByRole('button', { name: `Add a planting to ${DEMO.splitWest}` }).click()
  const dialog = page.getByRole('dialog', { name: new RegExp(`^Add a \\d{4} planting to ${literal(DEMO.splitWest)}`) })
  await dialog.getByLabel('Crop', { exact: true }).selectOption({ label: 'Soybean' })
  // Collapsed to a line with a count, opened to a checklist (or a line saying none is free)
  const also = dialog.locator('details').filter({ hasText: 'Also plant this on' })
  await expect(also.locator('summary')).toContainText(/other fields? free|None free for these dates/)
  await also.locator('summary').click()
  await expect(
    also.getByText(/Fields on this irrigation system with nothing planted|all have a planting on these dates/),
  ).toBeVisible()
  // Not for part of the field
  await dialog
    .locator('label')
    .filter({ hasText: /^\s*Part of the field\s*$/ })
    .click()
  await expect(also).toHaveCount(0)
})

// Mid-season, so the demo's fields are in season whatever today's date (in November they're collapsed)
const midSeason = `/daily?date=${new Date().getFullYear()}-07-15`

test("daily entry saves an irrigation system's rain", { tag: '@phone' }, async ({ page }) => {
  // The phone project runs beside the desktop one (two workers): its own day, so the desktop tests
  // on July 15 never see its rain
  await page.goto(test.info().project.name === 'phone' ? midSeason.replace('-07-15', '-07-10') : midSeason)
  const rain = page.getByLabel(/^Rain on /).first()
  await rain.fill('0.3')
  await page.getByRole('button', { name: /^Save / }).click()
  await expect(page.getByText(/^Saved /)).toBeVisible()
  // Depths show two places (NumberField's precision)
  await expect(page.getByLabel(/^Rain on /).first()).toHaveValue('0.30')

  await page
    .getByLabel(/^Rain on /)
    .first()
    .fill('')
  // Cleared once the save is done (the box is empty before it is), so the next test starts from the seed
  await Promise.all([
    page.waitForResponse((response) => response.request().method() !== 'GET' && response.url().includes('/daily')),
    page.getByRole('button', { name: /^Save / }).click(),
  ])
  await page.reload()
  await expect(page.getByLabel(/^Rain on /).first()).toHaveValue('')
})

test("daily entry fills an irrigation group's rain into its systems, and saves a plot's irrigation and a cover reading", async ({
  page,
}) => {
  await page.goto(midSeason)
  // Rain is entered on group and system rows (D15); a system named as its field (hayField's traveler)
  const rain = (row: string) => page.getByLabel(`Rain on ${row}`, { exact: true })
  const gauge = rain(DEMO.gauge)
  await gauge.fill('0.4')
  await expect(rain(DEMO.hayField)).toHaveValue('0.40')
  await expect(rain(DEMO.gaugeFieldSystem)).toHaveValue('0.40')
  await rain(DEMO.gaugeFieldSystem).fill('0.5')
  await expect(gauge).toHaveValue('')
  await expect(gauge).toHaveAttribute('placeholder', 'varies')

  const plots = page.getByRole('button', { name: `Plots on ${DEMO.researchField}` })
  if ((await plots.getAttribute('aria-expanded')) === 'false') await plots.click()
  const plot = page.getByLabel(
    new RegExp(`^Irrigation on ${literal(DEMO.namedPlot)}, .* on ${literal(DEMO.researchField)}`),
  )
  await plot.fill('0.3')
  const cover = page.getByLabel(new RegExp(`^Percent cover on ${literal(DEMO.hayField)}`))
  await cover.fill('30')
  await page.getByRole('button', { name: /^Save / }).click()
  await expect(page.getByText(/^Saved /)).toBeVisible()
  await expect(rain(DEMO.hayField)).toHaveValue('0.40')
  await expect(rain(DEMO.gaugeFieldSystem)).toHaveValue('0.50')
  await expect(gauge).toHaveAttribute('placeholder', 'varies')
  await expect(plot).toHaveValue('0.30')
  await expect(cover).toHaveValue('30')

  // Collapsing the group is remembered
  await page.getByRole('button', { name: `Irrigation systems in ${DEMO.gauge}` }).click()
  await expect(rain(DEMO.hayField)).toBeHidden()
  await page.reload()
  await expect(rain(DEMO.hayField)).toBeHidden()
  await page.getByRole('button', { name: `Irrigation systems in ${DEMO.gauge}` }).click()

  // Typing over varied rain and clearing it again puts each system's back
  await gauge.fill('0.7')
  await expect(rain(DEMO.gaugeFieldSystem)).toHaveValue('0.70')
  await gauge.fill('')
  await expect(rain(DEMO.gaugeFieldSystem)).toHaveValue('0.50')
  await expect(rain(DEMO.hayField)).toHaveValue('0.40')

  // Leave the day as it was for other tests: one value from the group, saved, then cleared from there
  await gauge.fill('0.4')
  await plot.fill('')
  await cover.fill('')
  await page.getByRole('button', { name: /^Save / }).click()
  await expect(page.getByText(/^Saved /)).toBeVisible()
  await expect(rain(DEMO.gaugeFieldSystem)).toHaveValue('0.40')
  await gauge.fill('')
  await page.getByRole('button', { name: /^Save / }).click()
  await expect(page.getByText(/^Saved /)).toBeVisible()
  await expect(rain(DEMO.gaugeFieldSystem)).toHaveValue('')
})

test("daily entry offers the day before's irrigation, filled in only when chosen", async ({ page }) => {
  // The demo's system ran on July 18 and has nothing on the 19th
  await page.goto(midSeason.replace('-07-15', '-07-19'))
  const amount = page.getByLabel(`Irrigation by ${DEMO.otherSystem}`, { exact: true })
  await expect(amount).toHaveValue('')
  const same = page.getByRole('button', { name: `Same as the day before for ${DEMO.otherSystem}` })
  await same.click()
  await expect(amount).toHaveValue('0.40')
  await expect(same).toBeHidden()
})

test("daily entry's calculator works out a system's irrigation and fills its fields", async ({ page }) => {
  await page.goto(midSeason)
  await page.getByRole('button', { name: `Work out ${DEMO.splitSystem}'s irrigation` }).click()
  const dialog = page.getByRole('dialog', {
    name: new RegExp(`^Irrigation for ${literal(DEMO.splitSystem)} on Jul 15$`),
  })
  // The demo's split system puts on 0.21 in a circle at 100%: at 20%, 1.05 in
  await dialog.getByRole('radio', { name: '% timer' }).check({ force: true })
  await expect(dialog.getByLabel('Depth at 100%')).toHaveAttribute('placeholder', '0.21')
  await dialog.getByLabel('Timer', { exact: true }).fill('20')
  await expect(dialog.getByText('1.05 in')).toBeVisible()
  await dialog.getByRole('radio', { name: 'Specific fields' }).check()
  await dialog.getByRole('checkbox', { name: DEMO.splitEast }).uncheck()
  await dialog.getByRole('button', { name: 'Apply to 1 field' }).click()

  await expect(page.getByLabel(`Irrigation on ${DEMO.splitWest}`, { exact: true })).toHaveValue('1.05')
  await expect(page.getByLabel(`Irrigation on ${DEMO.splitEast}`, { exact: true })).toHaveValue('')
  await expect(page.getByLabel(`Irrigation by ${DEMO.splitSystem}`, { exact: true })).toHaveAttribute(
    'placeholder',
    'varies',
  )
})

test('daily entry asks before changing the date with unsaved values', async ({ page }) => {
  await page.goto(midSeason)
  const date = await page.getByLabel('Date', { exact: true }).inputValue()
  await page
    .getByLabel(/^Rain on /)
    .first()
    .fill('0.2')

  // The confirm lists the change
  let message = ''
  page.once('dialog', (dialog) => {
    message = dialog.message()
    return dialog.dismiss()
  })
  await page.getByRole('button', { name: 'Previous day' }).click()
  // Leaving the box shows it to two places
  expect(message).toMatch(/^You have unsaved changes:\n\n• Rain on .+: 0\.20? in\n/)
  await expect(page.getByLabel('Date', { exact: true })).toHaveValue(date)
  await expect(page.getByLabel(/^Rain on /).first()).toHaveValue('0.20')

  page.once('dialog', (dialog) => dialog.accept())
  await page.getByRole('button', { name: 'Previous day' }).click()
  await expect(page.getByLabel('Date', { exact: true })).not.toHaveValue(date)
})

// Late August: a week no other test enters or reads (the desktop project only)
const lateAugust = `/daily/week?date=${new Date().getFullYear()}-08-30`
const weekCell = (row: string, kind: 'rain' | 'irrigation', day: string) =>
  new RegExp(`^${literal(row)} ${kind}, \\w{3}, ${day}$`)

test("daily entry's week saves rain for a group's fields and a system's irrigation, and asks before replacing varied rain", async ({
  page,
}) => {
  await page.goto(lateAugust)
  await expect(page.getByText(/Aug 24–30/).first()).toBeVisible()
  const rain = page.getByLabel(weekCell(DEMO.gauge, 'rain', 'Aug 25'))
  // Aug 24: the system's plantings end Aug 20 and 25, and a day after them takes nothing
  const irrigation = page.getByLabel(weekCell(DEMO.otherSystem, 'irrigation', 'Aug 24'))
  await rain.fill('0.4')
  await irrigation.fill('0.5')
  await page.getByRole('button', { name: 'Save Aug 24–30' }).click()
  await expect(page.getByText('Saved Aug 24–30')).toBeVisible()
  await expect(rain).toHaveValue('0.40')
  await expect(irrigation).toHaveValue('0.50')

  // The date links to the day, where the group's systems have the rain; one changed there
  await page
    .getByRole('link', { name: /Aug 25/ })
    .first()
    .click()
  const system = page.getByLabel(`Rain on ${DEMO.gaugeFieldSystem}`, { exact: true })
  await expect(system).toHaveValue('0.40')
  await system.fill('0.6')
  await page.getByRole('button', { name: /^Save / }).click()
  await expect(page.getByText(/^Saved /)).toBeVisible()

  // Back in the week, the group's rain varies, and replacing it asks first
  await page.goto(lateAugust)
  await expect(rain).toHaveValue('')
  await expect(rain).toHaveAttribute('placeholder', 'varies')
  await rain.fill('0.3')
  let message = ''
  page.once('dialog', (dialog) => {
    message = dialog.message()
    return dialog.dismiss()
  })
  await page.getByRole('button', { name: 'Save Aug 24–30' }).click()
  await expect
    .poll(() => message)
    .toMatch(
      new RegExp(
        `^This replaces different amounts on each field for: ${literal(DEMO.gauge)}, \\w{3}, Aug 25\\. Save anyway\\?$`,
      ),
    )
  await expect(rain).toHaveValue('0.30')

  // Saved anyway, every field has it again
  page.once('dialog', (dialog) => dialog.accept())
  await page.getByRole('button', { name: 'Save Aug 24–30' }).click()
  await expect(page.getByText('Saved Aug 24–30')).toBeVisible()
  await expect(rain).toHaveValue('0.30')
  await expect(rain).toHaveAttribute('placeholder', '')

  // Cleared for the next run (a blank box on varied rain would leave the fields' amounts as they are).
  // The last save's message is still showing, so wait for this save itself before reloading
  await rain.fill('')
  await irrigation.fill('')
  await Promise.all([
    page.waitForResponse((response) => response.request().method() !== 'GET' && response.url().includes('/daily/week')),
    page.getByRole('button', { name: 'Save Aug 24–30' }).click(),
  ])
  await expect(page.getByText('Saved Aug 24–30')).toBeVisible()
  await page.reload()
  await expect(rain).toHaveValue('')
  await expect(rain).toHaveAttribute('placeholder', '')
  await expect(irrigation).toHaveValue('')
})

test('daily entry switches between day and week, keeping the date', async ({ page }) => {
  await page.goto(midSeason)
  await page.getByRole('link', { name: 'Week', exact: true }).click()
  await expect(page).toHaveURL(/\/daily\/week\?date=\d{4}-07-15$/)
  await expect(page.getByText(/Jul 9–15/).first()).toBeVisible()

  await page.getByRole('link', { name: 'Day', exact: true }).click()
  await expect(page).toHaveURL(/\/daily\?date=\d{4}-07-15$/)
  await expect(page.getByLabel('Date', { exact: true })).toBeVisible()

  // Not remembered: the nav's Daily entry opens the day
  await page.goto('/daily/week')
  await page.getByRole('link', { name: 'Daily entry', exact: true }).click()
  await expect(page).toHaveURL(/\/daily$/)
  await expect(page.getByLabel('Date', { exact: true })).toBeVisible()
})

test("Setup's Duplicate starts a new irrigation system from another, to be placed on the map", async ({ page }) => {
  await page.goto('/setup')
  await page.getByRole('link', { name: `Duplicate ${DEMO.otherSystem}`, exact: true }).click()
  await expect(page.getByRole('heading', { name: `Duplicate ${DEMO.otherSystem}` })).toBeVisible()
  await expect(page.getByRole('textbox', { name: 'Name' })).toHaveValue(`${DEMO.otherSystem} copy`)
  await expect(page.getByRole('textbox', { name: 'Pump capacity' })).toHaveValue(/^1,?000$/)
  await expect(page.getByText(`It joins the group ${DEMO.firstFieldGroup}`)).toBeVisible()
})

test('a dialog asks before dropping changes, listing them', async ({ page }) => {
  await page.goto('/setup')
  await page.getByRole('button', { name: `Edit ${DEMO.researchField}` }).click()
  const dialog = page.getByRole('dialog')
  const area = dialog.getByRole('textbox', { name: 'Field area' })
  const before = await area.inputValue()

  // Escape with a change: the change listed in place of the form, Keep editing returns to it
  await area.fill('12.5')
  await page.keyboard.press('Escape')
  await expect(dialog.getByRole('heading', { name: 'Save your changes?' })).toBeFocused()
  await expect(dialog.getByRole('listitem')).toHaveText([`Field area: ${before} ac → 12.5 ac`])
  await dialog.getByRole('button', { name: 'Keep editing' }).click()
  await expect(area).toHaveValue('12.5')
  await expect(area).toBeFocused()

  // ✕ asks too; Discard closes, and the field opens again unchanged
  await dialog.getByRole('button', { name: 'Close' }).click()
  await dialog.getByRole('button', { name: 'Discard' }).click()
  await expect(dialog).toBeHidden()
  await page.getByRole('button', { name: `Edit ${DEMO.researchField}` }).click()
  await expect(dialog.getByRole('textbox', { name: 'Field area' })).toHaveValue(before)
  // Nothing changed: Escape just closes
  await page.keyboard.press('Escape')
  await expect(dialog).toBeHidden()
})

test("adding a system's irrigation on a date that has one offers to edit it instead", async ({ page }) => {
  await page.goto(await firstPlantingPath(page))
  await page.locator('main a[href*="/systems/"]').first().click()

  // Add one for today; the form resets to today, which now has an irrigation
  await page.getByLabel('Amount').fill('0.4')
  await page.getByRole('button', { name: 'Save irrigation' }).click()
  await expect(page.getByRole('status').filter({ hasText: 'Saving will replace it' })).toBeVisible()

  await page.getByRole('button', { name: 'Edit that one instead' }).click()
  await expect(page.getByRole('heading', { name: /^Edit / })).toBeVisible()
  await expect(page.getByLabel('Amount')).toHaveValue('0.40')

  // Deleted (the newest row, today's), the list is one day shorter
  const rows = page.locator('main table tbody tr')
  const before = await rows.count()
  page.once('dialog', (dialog) => dialog.accept())
  await rows.first().getByRole('button', { name: 'Delete' }).click()
  await expect(rows).toHaveCount(before - 1)
})

test('logging irrigation from the dashboard, an amount on each field', async ({ page }) => {
  // otherSystem's fields, yesterday (the system page's test above writes the first field's system today)
  const system = DEMO.otherSystem
  const [west, east] = ['Home West', 'Home East']
  await page.goto('/')
  await page.getByRole('button', { name: `Log irrigation on ${system}`, exact: true }).click()
  const dialog = page.getByRole('dialog', { name: `Log irrigation on ${system}` })
  await expect(dialog.getByText(/^(Last irrigated|No irrigation entered)/)).toBeVisible()
  await dialog.getByRole('button', { name: 'Yesterday' }).click()
  const date = await dialog.getByLabel('Choose a date').inputValue()
  for (const name of [west, east]) await dialog.getByRole('checkbox', { name: new RegExp(`^${name}`) }).check()
  // The calculator's workings open under the amount and fill it as they're typed
  await dialog.getByRole('button', { name: `Work out ${system}'s irrigation` }).click()
  await dialog.getByLabel('Hours it ran').fill('10')
  await expect(dialog.getByLabel('Amount', { exact: true })).not.toHaveValue('')
  await dialog.getByLabel('Amount', { exact: true }).fill('0.3')
  await dialog.getByRole('button', { name: 'A different amount on each field' }).click()
  await expect(dialog.getByLabel(`Irrigation on ${west}`)).toHaveValue('0.30')
  await dialog.getByLabel(`Irrigation on ${east}`).fill('0.5')
  await dialog.getByRole('button', { name: 'Save irrigation' }).click()
  await expect(dialog).toBeHidden()
  await expect(page.getByText('Irrigation saved')).toBeVisible()

  // Again on that day: it warns before replacing, and closing with something typed asks first
  await page.getByRole('button', { name: `Log irrigation on ${system}`, exact: true }).click()
  // Fresh: the calculator's earlier result doesn't come back into the amount
  await expect(dialog.getByLabel('Amount', { exact: true })).toHaveValue('')
  await dialog.getByRole('button', { name: `Work out ${system}'s irrigation` }).click()
  await expect(dialog.getByLabel('Hours it ran')).toHaveValue('')
  await expect(dialog.getByLabel('Amount', { exact: true })).toHaveValue('')
  await dialog.getByRole('button', { name: `Work out ${system}'s irrigation` }).click()
  await dialog.getByRole('button', { name: 'Yesterday' }).click()
  for (const name of [west, east]) await dialog.getByRole('checkbox', { name: new RegExp(`^${name}`) }).check()
  await dialog.getByLabel('Amount', { exact: true }).fill('0.4')
  await expect(dialog.getByRole('status').filter({ hasText: 'Saving replaces it' })).toContainText(
    `${east} (0.50 in) and ${west} (0.30 in)`,
  )
  await page.keyboard.press('Escape')
  await dialog.getByRole('button', { name: 'Discard' }).click()
  await expect(dialog).toBeHidden()

  // On the system page, by field; deleted again
  await page.getByRole('link', { name: `View ${system}`, exact: true }).click()
  const shown = new Intl.DateTimeFormat('en-US', { timeZone: 'UTC', weekday: 'short', month: 'short', day: 'numeric' })
  const row = page.locator('main table tbody tr').filter({ hasText: shown.format(new Date(`${date}T00:00:00Z`)) })
  await expect(row).toContainText(`${east} (0.50 in), ${west} (0.30 in)`)
  page.once('dialog', (confirm) => confirm.accept())
  await row.getByRole('button', { name: 'Delete' }).click()
  await expect(row).toHaveCount(0)
})

test('the weather charts follow the page width without overlapping', async ({ page }) => {
  await page.setViewportSize({ width: 1400, height: 900 })
  await page.goto(await firstZonePath(page))
  const card = (name: string) =>
    page
      .getByRole('button', { name: `About the ${name} chart` })
      .locator('xpath=ancestor::div[contains(@class, "rounded-lg")][1]')
  await expect(card('Air temperature').locator('canvas').first()).toBeVisible()

  // Narrower (still two columns), then wide again: the left column's cards end before the right's begin
  for (const width of [900, 1400]) {
    await page.setViewportSize({ width, height: 900 })
    await expect(async () => {
      const left = (await card('Air temperature').boundingBox())!
      const right = (await card('Precipitation').boundingBox())!
      const canvas = (await card('Air temperature').locator('canvas').first().boundingBox())!
      expect(left.x + left.width).toBeLessThanOrEqual(right.x)
      expect(canvas.x + canvas.width).toBeLessThanOrEqual(left.x + left.width)
    }).toPass({ timeout: 3000 })
  }
})

test('a weather chart explains itself, and zooms the rest with it', async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto(await firstZonePath(page))

  const info = page.getByRole('button', { name: 'About the Precipitation chart' })
  await info.click()
  await expect(page.getByRole('tooltip')).toContainText('rain plus the water in snow')
  await info.click()
  await expect(page.getByRole('tooltip')).toBeHidden()

  const card = info.locator('xpath=ancestor::div[contains(@class, "rounded-lg")][1]')
  // Zooming one chart moves the season slider (and the other charts) with it, whose reset puts them all back
  const reset = page.getByRole('button', { name: 'Reset', exact: true })
  await expect(reset).toBeHidden()
  await card.locator('canvas').first().scrollIntoViewIfNeeded()
  const box = (await card.locator('canvas').first().boundingBox())!
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 3)
  await page.mouse.wheel(0, -400)
  await expect(reset).toBeVisible()
  await expect(page.getByRole('button', { name: 'Reset Precipitation chart' })).toBeHidden()
  await reset.click()
  await expect(reset).toBeHidden()

  // Its summary and daily values, for reading the numbers (and its text alternative)
  await expect(card.getByRole('img', { name: /^Precipitation\. Last 7 days: Rain / })).toBeVisible()
  // in a dialog, so the grid stays as it is (Ben, 2026-11-17)
  await card.getByRole('button', { name: 'Summary and data' }).click()
  const data = page.getByRole('dialog', { name: 'Precipitation: summary and data' })
  await expect(data.getByText(/^Last 7 days: Rain /)).toBeVisible()
  const table = data.getByRole('table', { name: /^Precipitation by day/ })
  await expect(table.getByRole('columnheader', { name: 'Rain (in)', exact: true })).toBeVisible()
  await expect(table.getByRole('rowheader', { name: /\(forecast\)$/ }).first()).toBeVisible()

  // Its values download as a CSV, opening with frontmatter (built in the browser)
  const [download] = await Promise.all([
    page.waitForEvent('download'),
    data.getByRole('button', { name: 'Download CSV of the Precipitation data' }).click(),
  ])
  expect(download.suggestedFilename()).toMatch(/^wisp-.+-precipitation\.csv$/)
  const csv = readFileSync(await download.path(), 'utf8')
  expect(csv).toMatch(/^\uFEFF"?WISP weather chart: Precipitation, /)
  expect(csv).toContain('\r\nDate,Forecast,Rain (in)')
  // Named by the zone's location (Ben, 2026-11-17)
  expect(download.suggestedFilename()).toMatch(/^wisp-weather-\d+\.\d\d[NS]-\d+\.\d\d[EW]-\d{4}-precipitation\.csv$/)
  await expect(data.getByRole('button', { name: 'Copy to clipboard: the Precipitation data' })).toBeVisible()
  await page.keyboard.press('Escape')

  // Every chart's values in one table, with the zone's whole CSV
  await page.getByRole('button', { name: "all of this zone's weather" }).click()
  const all = page.getByRole('dialog', { name: "All of this zone's weather" })
  const columns = all.getByRole('table').getByRole('columnheader')
  await expect(columns.first()).toHaveText('Date')
  await expect(all.getByRole('columnheader', { name: 'Rain (in)', exact: true })).toBeVisible()
  expect(await columns.count()).toBeGreaterThan(15)
  await expect(all.getByRole('link', { name: "Download CSV of all of this zone's weather" })).toHaveAttribute(
    'href',
    /\/weather\/-?[\d.]+,-?[\d.]+\/export\?year=\d{4}$/,
  )
  expect(errors).toEqual([])
})

test("alerts previews today's email and sends a test, then waits", async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto('/alerts')
  await expect(page.getByLabel('Email frequency')).toBeVisible()

  await page.getByRole('button', { name: "Preview today's email" }).click()
  const email = page.frameLocator('iframe[title="Daily email preview"]')
  await expect(email.getByRole('heading', { name: 'Your fields this morning' })).toBeVisible()

  // One test send per cooldown (reset by e2e/seed.rb); desktop only, as is every test not tagged @phone
  await page.getByRole('button', { name: 'Send me a test email' }).click()
  await expect(page.getByText('Test email sent to')).toBeVisible()
  await expect(page.getByRole('button', { name: /Send a test email \(again in \d+ min\)/ })).toBeDisabled()
  // The preview stays open across the redirect
  await expect(email.getByRole('heading', { name: 'Your fields this morning' })).toBeVisible()

  // Changes save themselves, rebuilding the open preview in the same request; the preview waits for them
  const status = page.getByRole('status').filter({ hasText: /Saving|save automatically/ })
  await page.getByLabel('Email frequency').selectOption('needed')
  const field = page.getByRole('checkbox', { name: DEMO.splitEast })
  await field.uncheck()
  await expect(page.getByRole('button', { name: 'Refresh preview' })).toBeDisabled()
  await expect(status).toHaveText('Changes save automatically')
  await expect(email.getByRole('heading', { name: 'Your fields this morning' })).toBeVisible()
  await page.getByRole('button', { name: 'Refresh preview' }).click()
  await expect(field).not.toBeChecked()
  await page.reload()
  await expect(page.getByLabel('Email frequency')).toHaveValue('needed')
  await expect(field).not.toBeChecked()
  await field.check()
  await expect(status).toHaveText('Changes save automatically')
  expect(errors).toEqual([])
})

test('glossary terms explain themselves on hover or tap', { tag: '@phone' }, async ({ page }) => {
  await page.goto(await firstPlantingPath(page))
  const term = page.getByRole('button', { name: 'allowable depletion', exact: true })
  if (test.info().project.name === 'phone') await term.tap()
  else await term.hover()
  await expect(page.getByText('The water left in the root zone that the crop can use without stress.')).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(page.getByText('The water left in the root zone that the crop can use without stress.')).toBeHidden()
})

test('a field shape is read from a file, its area offered, and saved', async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto(await researchFieldPath(page))
  await page.getByRole('link', { name: /^(Draw\/import field shape|Edit field shape)$/ }).click()
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(`Field shape: ${DEMO.researchField}`)
  await expect(page.locator('.maplibregl-canvas')).toBeVisible()

  // A KML field of about 111 acres: its area goes into the box, the saved area still shown beside it
  // (Ben, 2026-11-17)
  await expect(page.getByRole('group', { name: 'Shape tools' })).toBeEnabled()
  const area = page.getByLabel('Field area', { exact: true })
  const before = await area.inputValue()
  const saved = page.getByText('Current area').locator('xpath=following-sibling::p')
  await expect(saved).toHaveText(`${Number(before).toFixed(2)} ac`)
  await page.getByLabel('Shape file').setInputFiles('spec/fixtures/files/outlines/google_earth.kml')
  await expect(area).toHaveValue(/^111\.\d\d$/)
  await expect(saved).toHaveText(`${Number(before).toFixed(2)} ac`)
  await expect(page.getByText(/^Field as drawn: 111\.\d\d ac\.\s*$/)).toBeVisible()
  // An area typed after it stays, and the difference is said and warned
  await area.fill(before)
  await expect(
    page.getByText(/^Field as drawn: 111\.\d\d ac, [\d.]+ ac more than the area above\. Check that/),
  ).toBeVisible()

  await page.getByRole('button', { name: 'Save' }).click()
  await expect(page.getByText(`Saved the shape of ${DEMO.researchField}`)).toBeVisible()
  await expect(page.getByRole('heading', { name: `${DEMO.researchField}`, level: 1 })).toBeVisible()
  await page.goto('/setup')
  // The area entered, and the shape's beside it
  await expect(page.getByText(new RegExp(`${Number(before).toFixed(1)} ac · Mapped as 111\\.\\d ac`))).toBeVisible()
  // The field's dialog shows the shape
  await page.getByRole('button', { name: `Edit ${DEMO.researchField}` }).click()
  const dialog = page.getByRole('dialog')
  await expect(dialog.getByRole('img', { name: `The shape of ${DEMO.researchField}` })).toBeVisible()
  await dialog.getByRole('link', { name: 'Edit shape' }).click()
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(`Field shape: ${DEMO.researchField}`)
  expect(errors).toEqual([])
})

test('a field shape is drawn corner by corner, or picked from a file of several', async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto('/setup')
  await page.getByRole('button', { name: `Edit ${DEMO.shapeField}` }).click()
  await page
    .getByRole('dialog')
    .getByRole('link', { name: /^(Add a shape|Edit shape)$/ })
    .click()
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(`Field shape: ${DEMO.shapeField}`)
  if (await page.getByRole('button', { name: 'Remove the shape' }).isVisible())
    await page.getByRole('button', { name: 'Remove the shape' }).click()

  // Four corners, then the first again to close it: the part is ready to adjust
  await expect(page.getByRole('group', { name: 'Shape tools' })).toBeEnabled()
  await page.getByRole('button', { name: 'Draw the shape' }).click()
  await expect(page.getByText(/Click the map at each corner/)).toBeVisible()
  const box = (await page.locator('.maplibregl-canvas').boundingBox())!
  const at = (x: number, y: number) => [box.x + box.width * x, box.y + box.height * y] as const
  for (const [x, y] of [at(0.4, 0.4), at(0.6, 0.4), at(0.6, 0.6), at(0.4, 0.6), at(0.4, 0.4)]) {
    await page.mouse.click(x, y)
    await page.waitForTimeout(150)
  }
  // Finished, it's selected to adjust until Done editing
  const shapeBar = page.getByRole('group', { name: 'The shape on the map' })
  await shapeBar.getByRole('button', { name: 'Done editing' }).click()
  const drawn = page.getByText(/^Field as drawn: [\d.]+ (ac|ha)/)
  await expect(drawn).toBeVisible()
  const first = await drawn.textContent()

  // Drawing again asks first, and the new shape replaces the old one: a field is one polygon
  page.once('dialog', (dialog) => dialog.accept())
  await page.getByRole('button', { name: 'Draw a new one' }).click()
  for (const [x, y] of [at(0.45, 0.45), at(0.55, 0.45), at(0.55, 0.55), at(0.45, 0.55), at(0.45, 0.45)]) {
    await page.mouse.click(x, y)
    await page.waitForTimeout(150)
  }
  await shapeBar.getByRole('button', { name: 'Done editing' }).click()
  await expect(drawn).not.toHaveText(first!)
  const second = await drawn.textContent()

  // Corners go anywhere, but a shape whose edges cross can't be kept; Cancel puts back the one before
  page.once('dialog', (dialog) => dialog.accept())
  await page.getByRole('button', { name: 'Draw a new one' }).click()
  for (const [x, y] of [at(0.4, 0.4), at(0.6, 0.6), at(0.6, 0.4), at(0.4, 0.5), at(0.4, 0.4)]) {
    await page.mouse.click(x, y)
    await page.waitForTimeout(150)
  }
  await expect(shapeBar.getByText('Its edges cross: move a corner to fix it.')).toBeVisible()
  await expect(shapeBar.getByRole('button', { name: 'Done editing' })).toBeDisabled()
  await expect(page.getByRole('button', { name: 'Save', exact: true })).toBeDisabled()
  await expect(page.getByText('The shape crosses itself.')).toBeVisible()
  await shapeBar.getByRole('button', { name: 'Cancel' }).click()
  await expect(shapeBar).toBeHidden()
  await expect(drawn).toHaveText(second!)

  // A shapefile with two fields asks which one (a file of one is read in the test above)
  await page.getByLabel('Shape file').setInputFiles('spec/fixtures/files/outlines/clu_utm.zip')
  await expect(page.getByRole('heading', { name: 'Field import', exact: true })).toBeVisible()
  await expect(
    page.getByText(/^Loaded 2 shapes from clu_utm\.zip\. Sort or search to find your field\.$/),
  ).toBeVisible()
  const shapes = page.getByRole('table', { name: 'Shapes from clu_utm.zip', exact: true })
  await expect(shapes.getByRole('columnheader', { name: 'Distance' })).toBeVisible()
  await shapes.getByRole('button', { name: 'Home South' }).click()
  await expect(page.getByText(/^Field as drawn: 10\d\.\d\d ac/)).toBeVisible()
  // Picked, it stays open to try another, the shape on the map marked
  await expect(shapes.getByRole('button', { name: 'Home South' })).toHaveAttribute('aria-current', 'true')
  // Expanded, every attribute is a column
  await page.getByRole('button', { name: 'Expand the table' }).click()
  const all = page.getByRole('table', { name: 'All of the shapes from clu_utm.zip' })
  await expect(all.getByRole('columnheader', { name: 'Notes' })).toBeVisible()
  await all.getByRole('button', { name: 'Home North' }).click()
  await expect(all).toBeHidden()
  await expect(shapes.getByRole('button', { name: 'Home North' })).toHaveAttribute('aria-current', 'true')
  // Closed, Import from a file opens the same shapes again
  await page.getByRole('button', { name: 'Close the field import' }).click()
  await expect(shapes).toBeHidden()
  await page.getByRole('button', { name: 'Import from a file' }).click()
  await expect(shapes).toBeVisible()

  // Leaving asks first; nothing is saved
  page.once('dialog', (dialog) => dialog.accept())
  await page.getByRole('link', { name: 'Cancel' }).click()
  await expect(page.getByRole('heading', { name: 'Setup', level: 1 })).toBeVisible()

  // The file's shapes are kept in the browser: Setup's import matches them as it opens, without
  // reading the file again, and can forget them
  await page.getByRole('link', { name: 'Import field shapes' }).click()
  await expect(page.getByText(/^Shapes from clu_utm\.zip \(read at .*\)$/)).toBeVisible()
  await expect(page.getByText(/^2 shapes\./)).toBeVisible()
  await expect(page.getByLabel('Choose another file')).toBeAttached()
  await page.getByRole('button', { name: 'Forget this file' }).click()
  await expect(page.getByText(/^2 shapes\./)).toBeHidden()
  await expect(page.getByLabel('Choose a file')).toBeAttached()
  await page.reload()
  await expect(page.getByLabel('Choose a file')).toBeAttached()
  await expect(page.getByText(/^Shapes from/)).toBeHidden()
  expect(errors).toEqual([])
})

test('a field shape away from its system can move the field to a new Location', async ({ page }) => {
  const errors = watchErrors(page)
  // A field on a traveler a kilometer or more west of the KML's field
  const [name, system] = [DEMO.awayField, DEMO.awaySystem]
  await page.goto('/setup')
  await page.getByRole('button', { name: `Edit ${name}` }).click()
  await page
    .getByRole('dialog')
    .getByRole('link', { name: /^(Add a shape|Edit shape)$/ })
    .click()
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(`Field shape: ${name}`)
  await expect(page.getByRole('group', { name: 'Shape tools' })).toBeEnabled()

  await page.getByLabel('Shape file').setInputFiles('spec/fixtures/files/outlines/google_earth.kml')
  const escaped = system.replace(/[()]/g, '\\$&')
  await expect(
    page.getByText(
      new RegExp(`^This field is [\\d.]+ (mi|ft) away from its assigned irrigation system, ${escaped}\\. All fields`),
    ),
  ).toBeVisible()
  const menu = page.getByLabel(`Irrigation system for ${name}`)
  await expect(menu).toHaveValue('keep')
  // Then any system within half a mile (the other size's Location, after its run), then Create a new system
  await expect(menu.locator('option').first()).toHaveText(new RegExp(`^Keep with ${escaped} – [\\d.]+ (mi|ft) away$`))
  await expect(menu.locator('option').last()).toHaveText('Create a new system')

  await menu.selectOption('location')
  await expect(
    page.getByText(
      /^This will create a new location-only system named .* at the center of this field when you save your changes\. You will need to configure this system later in Setup\.$/,
    ),
  ).toBeVisible()
  await page.getByRole('button', { name: 'Save' }).click()
  await expect(page.getByText(`Saved the shape of ${name} and moved it to ${name} (location)`)).toBeVisible()

  // On Setup, under its new Location, with no shape to check
  await page.goto('/setup')
  await expect(page.getByRole('button', { name: `Edit ${name}` })).toBeVisible()
  await expect(page.getByText(`${name}'s shape`)).toBeHidden()
  expect(errors).toEqual([])
})

test('field shapes are imported from a shapefile, matched to fields or new ones', async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto('/setup')
  await page.getByRole('link', { name: 'Import field shapes' }).click()
  await expect(page.getByRole('heading', { name: 'Import field shapes', level: 1 })).toBeVisible()
  await page.getByLabel('Choose a file').setInputFiles('spec/fixtures/files/outlines/clu_utm.zip')

  // Two shapes, named from FIELD_NAME, matching no field's name. The first covers an outlined field
  // (not exactly its shape), so it starts as that field's update; made a new field instead, it says it
  // overlaps that field
  await expect(page.getByText(/^2 shapes\./)).toBeVisible()
  await expect(page.getByLabel('Names from', { exact: true })).toHaveValue('FIELD_NAME')
  const first = page.locator('#shape-0')
  const second = page.locator('#shape-1')
  await expect(first.getByRole('button', { name: 'Home North', exact: true })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Fields to import' })).toBeVisible()
  await expect(page.getByRole('radio', { name: 'N–S' })).toBeChecked()
  await expect(first.getByRole('radio', { name: 'Update', exact: true })).toBeChecked()
  await expect(first.getByRole('combobox', { name: 'Field to update' })).toContainText(
    new RegExp(`^${literal(DEMO.coveredField)} \\(.*\\) · overlaps 100%`),
  )
  await expect(first.getByText('Replaces its shape')).toBeVisible()
  await first.getByText('New', { exact: true }).click()
  await expect(first.getByText(`Overlaps ${DEMO.coveredField} (100%)`)).toBeVisible()
  await expect(first.getByRole('button', { name: `Update ${DEMO.coveredField} instead` })).toBeVisible()

  // A new field takes another system, and offers the outline's name
  const research = await page
    .locator('#shape-0-system option', { hasText: `${DEMO.researchFarm} › ${DEMO.researchSystemLabel} · ` })
    .getAttribute('value')
  await page.locator('#shape-0-system').selectOption(research!)
  await expect(first.getByLabel("New field's name")).toHaveValue('Home North')
  await first.getByText('Skip', { exact: true }).click()
  await expect(first.getByRole('radio', { name: 'Skip' })).toBeChecked()

  // The second outlines an existing field
  await second.getByText('Update', { exact: true }).click()
  const garden = await page
    .locator('#shape-1-field option', { hasText: new RegExp(`^${literal(DEMO.shapeField)}`) })
    .getAttribute('value')
  await page.locator('#shape-1-field').selectOption(garden!)
  await expect(second.getByRole('combobox', { name: 'Field to update' })).toHaveValue(garden!)
  await page.getByRole('button', { name: 'Save the shape' }).click()
  await expect(page.getByText('Saved a field shape')).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Setup', level: 1 })).toBeVisible()
  await page.getByRole('button', { name: `Edit ${DEMO.shapeField}` }).click()
  await expect(page.getByRole('dialog').getByRole('img', { name: `The shape of ${DEMO.shapeField}` })).toBeVisible()
  await page.keyboard.press('Escape')

  // That shape is near Arlington, nowhere near the field's system at Coloma: Setup says so
  const issues = page.getByRole('region', { name: 'Field shapes to check' })
  await expect(issues).toContainText(
    new RegExp(`${literal(DEMO.shapeField)}'s shape isn't under ${literal(DEMO.shapeFieldSystem)}, \\d+\\.\\d mi away`),
  )
  expect(errors).toEqual([])
})

test("field shapes under none of the operation's systems start skipped, without a card, and can be added", async ({
  page,
}) => {
  const errors = watchErrors(page)
  // A field near Superior, far from every demo system
  const far = {
    type: 'FeatureCollection',
    features: [
      {
        type: 'Feature',
        properties: { NAME: 'Far Forty', CLU: 'A-123' },
        geometry: {
          type: 'Polygon',
          coordinates: [
            [
              [-92.1, 46.7],
              [-92.095, 46.7],
              [-92.095, 46.703],
              [-92.1, 46.703],
              [-92.1, 46.7],
            ],
          ],
        },
      },
    ],
  }
  await page.goto('/setup/outlines/import')
  await page
    .getByLabel('Choose a file')
    .setInputFiles({ name: 'far.geojson', mimeType: 'application/geo+json', buffer: Buffer.from(JSON.stringify(far)) })

  const skipped = page.getByText("1 shape matches no field and isn't under your irrigation systems, so it's skipped.")
  await expect(skipped).toBeVisible()
  await expect(page.locator('#shape-0')).toBeHidden()

  // Found by an attribute the table doesn't show, then added as a new field
  await skipped.click()
  await page.getByPlaceholder('Search the skipped shapes').fill('A-123')
  await page.getByRole('button', { name: 'Add Far Forty', exact: true }).click()
  await expect(page.locator('#shape-0').getByRole('button', { name: 'Far Forty', exact: true })).toBeVisible()
  await expect(page.locator('#shape-0').getByRole('radio', { name: 'New', exact: true })).toBeChecked()
  await expect(page.getByText('Choose the system that waters it')).toBeVisible()
  await expect(skipped).toBeHidden()
  expect(errors).toEqual([])
})

test("a kept file's shapes not yet imported are on the irrigation system map, to place a system on", async ({
  page,
}) => {
  const errors = watchErrors(page)
  // Two fields near Superior, far from every demo system
  const square = (lng: number, lat: number) => [
    [lng, lat],
    [lng + 0.005, lat],
    [lng + 0.005, lat + 0.003],
    [lng, lat + 0.003],
    [lng, lat],
  ]
  const file = {
    type: 'FeatureCollection',
    features: [
      {
        type: 'Feature',
        properties: { NAME: 'Far Forty' },
        geometry: { type: 'Polygon', coordinates: [square(-92.1, 46.7)] },
      },
      {
        type: 'Feature',
        properties: { NAME: 'Far Eighty' },
        geometry: { type: 'Polygon', coordinates: [square(-92.11, 46.7)] },
      },
    ],
  }
  await page.goto('/setup/outlines/import')
  await page
    .getByLabel('Choose a file')
    .setInputFiles({ name: 'far.geojson', mimeType: 'application/geo+json', buffer: Buffer.from(JSON.stringify(file)) })
  await expect(page.getByText(/^2 shapes\./)).toBeVisible()
  await page.getByRole('link', { name: 'add an irrigation system' }).click()

  await expect(page.getByText(/^The 2 shapes from far\.geojson not yet imported are a layer on the map/)).toBeVisible()
  await page.getByRole('button', { name: /^Layers/ }).click()
  const layer = page.getByRole('checkbox', { name: /^Shapes from far\.geojson/ })
  await expect(layer).toBeChecked()
  await layer.uncheck()
  await expect(layer).not.toBeChecked()
  // The way back to the import stays
  await expect(page.getByRole('link', { name: 'import the shapes as fields' })).toBeVisible()
  expect(errors).toEqual([])
})

test('a field shape file of more than 1,000 shapes is read as its first 1,000', async ({ page }) => {
  const errors = watchErrors(page)
  // 1,003 small squares in a grid near Superior, far from every demo system
  const features = Array.from({ length: 1003 }, (_, i) => {
    const [lng, lat] = [-92.2 + (i % 40) * 0.005, 46.6 + Math.floor(i / 40) * 0.005]
    return {
      type: 'Feature',
      properties: { NAME: `Square ${i + 1}` },
      geometry: {
        type: 'Polygon',
        coordinates: [
          [
            [lng, lat],
            [lng + 0.003, lat],
            [lng + 0.003, lat + 0.003],
            [lng, lat + 0.003],
            [lng, lat],
          ],
        ],
      },
    }
  })
  await page.goto('/setup/outlines/import')
  await page.getByLabel('Choose a file').setInputFiles({
    name: 'many.geojson',
    mimeType: 'application/geo+json',
    buffer: Buffer.from(JSON.stringify({ type: 'FeatureCollection', features })),
  })
  await expect(
    page.getByText('This file has 1,003 shapes. WISP read the first 1,000 and discarded the other 3;'),
  ).toBeVisible()
  await expect(page.getByText(/^1,000 shapes\./)).toBeVisible()
  expect(errors).toEqual([])
})

test('the map shades outlined fields and badges them at their center, and marks the selected one', async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto('/map')
  await expect(page.locator('.maplibregl-canvas')).toBeVisible()
  // Zoomed out, every system is a dot, the split system too, though its two fields have outlines
  const dot = page.getByRole('button', { name: new RegExp(`^${literal(DEMO.splitSystem)}: `) })
  await expect(page.getByRole('button', { name: new RegExp(`^${literal(DEMO.otherSystem)}: `) })).toBeVisible()
  await expect(dot).toBeVisible()

  // A field picked from the list (as a click in its outline does) is marked in its system's panel
  const list = page.getByRole('complementary', { name: 'Fields' })
  await list.getByRole('button', { name: new RegExp(`${literal(DEMO.splitWest)}.*on the map$`) }).click()
  const panel = page.getByRole('region', { name: `System: ${DEMO.splitSystem}` })
  await expect(panel.locator('li[aria-current="true"]')).toContainText(DEMO.splitWest)
  // Closer in, the outlined fields carry their plantings' badges, and the system's marker goes
  const badges = page.getByRole('button', { name: new RegExp(`^Field: ${literal(DEMO.splitWest)}, Planting: `) })
  await expect(badges).toBeVisible()
  await expect(badges).toHaveAttribute('aria-pressed', 'true')
  await expect(dot).toBeHidden()

  // A click in a field's outline selects that field, not the system drawn over it. The map
  // flies the system to 170 px left of center beside the panel (wide screens), at zoom 13.5 or more,
  // where its 1,300 ft radius is over 80 px: splitEast is its east half.
  const box = (await page.locator('.maplibregl-canvas').boundingBox())!
  // Clicked again until the flight has ended there
  await expect(async () => {
    await page.mouse.click(box.x + box.width / 2 - 170 + 40, box.y + box.height / 2)
    await expect(panel.locator('li[aria-current="true"]')).toContainText(DEMO.splitEast, { timeout: 500 })
  }).toPass({ timeout: 10_000 })

  // The systems' shapes are a layer that can be switched off, and stays off
  await page.getByRole('button', { name: /^Layers/ }).click()
  const systems = page.getByRole('checkbox', { name: 'Irrigation systems' })
  await expect(systems).toBeChecked()
  await systems.uncheck()
  await page.reload()
  await page.getByRole('button', { name: /^Layers/ }).click()
  await expect(page.getByRole('checkbox', { name: 'Irrigation systems' })).not.toBeChecked()
  await page.getByRole('checkbox', { name: 'Irrigation systems' }).check()
  expect(errors).toEqual([])
})

test("a planting's bar in Setup opens its page or its form, and the page's Edit in setup comes back to the form", async ({
  page,
}) => {
  await page.goto('/setup')
  const bars = page.getByRole('list', { name: new RegExp(`^Plantings on ${literal(DEMO.researchField)}`) })
  // The menu opens under the bar where it's clicked, centred on the pointer
  const bar = bars.getByRole('button', { name: /^Soybean/ }).first()
  const box = (await bar.boundingBox())!
  await bar.click({ position: { x: box.width * 0.6, y: box.height / 2 } })
  const menu = (await page.getByRole('menu').boundingBox())!
  expect(Math.abs(menu.x + menu.width / 2 - (box.x + box.width * 0.6))).toBeLessThan(4)
  // Below the bar, or above it near the bottom of the window
  expect(menu.y >= box.y + box.height - 1 || menu.y + menu.height <= box.y + 1).toBe(true)
  await page.getByRole('menuitem', { name: 'View this planting' }).click()
  await expect(page).toHaveURL(/\/plantings\/\d+/)

  await page.getByRole('link', { name: 'Edit in setup' }).click()
  const dialog = page.getByRole('dialog', { name: new RegExp(`^Edit Soybean on ${literal(DEMO.researchField)}`) })
  await expect(dialog).toBeVisible()
  await expect(page).not.toHaveURL(/planting=/)

  // From the form, its page again
  await dialog.getByRole('link', { name: 'View this planting' }).click()
  await expect(page).toHaveURL(/\/plantings\/\d+/)
})

test('the dashboard and Setup search fields by name or crop', async ({ page }) => {
  await page.goto('/')
  const search = page.getByRole('searchbox', { name: 'Search fields' })
  const fieldHeading = (name: string) => page.getByRole('heading', { name: `Field: ${name}`, exact: true })
  await expect(fieldHeading(DEMO.researchField)).toBeVisible()
  await search.fill(DEMO.firstCrop.toLowerCase())
  await expect(fieldHeading(DEMO.firstField)).toBeVisible()
  await expect(fieldHeading(DEMO.researchField)).toHaveCount(0)
  // What matched is highlighted (the CSS Custom Highlight API)
  await expect
    .poll(() => page.evaluate(() => (CSS.highlights.get('search') as Highlight | undefined)?.size ?? 0))
    .toBeGreaterThan(0)
  await search.fill('no such field')
  await expect(page.getByText('Nothing matches "no such field".')).toBeVisible()

  await page.goto('/setup')
  const edit = (name: string) => page.getByRole('button', { name: `Edit ${name}`, exact: true })
  await expect(edit(DEMO.firstField)).toBeVisible()
  await page.getByRole('searchbox', { name: 'Search fields' }).fill(DEMO.researchField)
  await expect(edit(DEMO.researchField)).toBeVisible()
  await expect(edit(DEMO.firstField)).toHaveCount(0)

  // A group's form still has all its systems, not just those the search left (saving it keeps them)
  await page.getByRole('button', { name: `Edit ${DEMO.gauge}`, exact: true }).click()
  const group = page.getByRole('group', { name: 'Irrigation systems in this group' })
  await expect(group.getByRole('checkbox', { name: new RegExp(`^${literal(DEMO.gaugeFieldSystem)}`) })).toBeChecked()
  await expect(group.getByRole('checkbox', { name: new RegExp(`^${literal(DEMO.researchSystem)}`) })).toBeChecked()
  await page.keyboard.press('Escape')
})
