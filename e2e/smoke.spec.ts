import { readFileSync } from 'node:fs'

import { expect, type Page, test } from '@playwright/test'

import { firstPlantingPath, firstZonePath, researchFieldPath, signIn, watchErrors } from './session'

// Smoke tests over the demo account seeded by e2e/seed.rb: the main ways of entering data save, and
// the map and charts work. accessibility.spec.ts visits every page, failing on script errors too.

test.beforeEach(async ({ page }) => {
  await signIn(page)
})

test('the dashboard shows field cards with a status', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible()
  await expect(page.locator('main ul li').first()).toBeVisible()
  await expect(page.getByText('AD today').first()).toBeVisible()
  await expect(page.getByRole('heading', { name: /^Farm: / }).first()).toBeVisible()
  await expect(page.getByRole('heading', { name: /^Field: / }).first()).toBeVisible()

  // A pivot's name links to its page: its irrigation, and its weather zone's week ahead (G.12)
  const pivot = page.getByRole('heading', { name: /^Pivot: / }).first()
  const name = (await pivot.textContent())!.replace('Pivot:', '').trim()
  await expect(page.getByRole('link', { name: `Irrigation on ${name}` })).toBeVisible()
  await pivot.getByRole('link', { name }).click()
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(`Pivot: ${name}`)
  await expect(page.getByRole('heading', { name: /^Weather/, level: 2 })).toBeVisible()
  await page.getByRole('link', { name: /^Season's weather: / }).click()
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Weather:')
  await expect(page.getByRole('heading', { name: 'Weather charts', level: 2 })).toBeVisible()
})

test('the Weather tab has the week ahead and a season of weather per zone (G.12)', async ({ page }) => {
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
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Weather:')
  await expect(page.getByRole('heading', { name: 'The week ahead' })).toBeVisible()
  await expect(page.getByLabel('Add the total since')).toBeVisible()
  expect(errors).toEqual([])
})

test('the Admin tab switches between Users and Weather data', async ({ page }) => {
  await page.goto('/admin/users')
  const pills = page.getByRole('navigation', { name: 'Admin' })
  await expect(pills.getByRole('link', { name: 'Users' })).toHaveAttribute('aria-current', 'page')
  await pills.getByRole('link', { name: 'Weather data' }).click()
  await expect(page.getByRole('heading', { name: 'Weather data', level: 1 })).toBeVisible()
  await expect(page.getByRole('navigation', { name: 'Main' }).getByRole('link', { name: 'Admin' })).toHaveAttribute(
    'aria-current',
    'page',
  )
})

test('the map lists the fields and selects a pivot from the list', async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto('/map')
  await expect(page.getByRole('heading', { name: 'Map', level: 1 })).toBeVisible()
  const list = page.getByRole('complementary', { name: 'Fields' })
  await expect(list.getByRole('heading', { name: /^Field: / }).first()).toBeVisible()

  // Selecting a field opens its pivot's panel over the map and marks the card
  const select = list.getByRole('button', { name: /on the map$/ }).first()
  await select.click()
  await expect(select).toHaveAttribute('aria-pressed', 'true')
  const panel = page.getByRole('region', { name: /^Pivot: / })
  await expect(panel).toBeVisible()
  await expect(panel.getByRole('heading').getByRole('link')).toBeVisible()
  await expect(panel.getByRole('link', { name: 'Irrigation', exact: true })).toBeVisible()

  // Escape closes it; the list's link opens the field
  await page.keyboard.press('Escape')
  await expect(panel).toBeHidden()
  await list
    .getByRole('link', { name: /^Open / })
    .first()
    .click()
  await expect(page).toHaveURL(/\/(fields|plantings)\/\d+/)
  expect(errors).toEqual([])
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

  // Pivots still select
  await page
    .getByRole('complementary', { name: 'Fields' })
    .getByRole('button', { name: /on the map$/ })
    .first()
    .click()
  await expect(page.getByRole('region', { name: /^Pivot: / })).toBeVisible()
  expect(errors).toEqual([])
})

test('the Drought Monitor layer gives the category at the selected pivot', async ({ page }) => {
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
  await expect(page.getByRole('region', { name: /^Pivot: / })).toContainText('D1 Moderate drought')
})

test("tapping the map gives the rain layer's value there", async ({ page }) => {
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

  // A tap away from the pivots (the map's lower left corner)
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

test('quick setup suggests the soil from the soil survey under the pivot', async ({ page }) => {
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
  await page.getByRole('application', { name: /click to place the pivot/ }).click()
  await expect(page.getByText(/Soil survey:\s*mostly Sand/)).toBeVisible()
  await expect(page.getByLabel('Soil').locator('option:checked')).toHaveText('Sand')
  await expect(page.getByText('From the soil survey')).toBeVisible()
})

/** Drags a map handle (a marker, found by its title) by dx, dy pixels, once the map has settled */
/** Clicks the pivot picker's map once MapLibre is ready for it */
async function placePivot(page: Page) {
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

test('a linear move is sized by dragging a corner and turned by its handle', async ({ page }) => {
  const name = `Ditch linear ${Date.now()}`
  await page.goto('/pivots/new')
  await page.getByLabel('Name', { exact: true }).fill(name)
  await page.getByLabel(/Linear move/).check()
  await placePivot(page)
  const travel = page.getByLabel('Travel distance')
  const before = await travel.inputValue()
  await dragHandle(page, 'Drag to resize the linear move', 0, 20)
  await expect(travel).not.toHaveValue(before)
  const direction = page.getByLabel('Direction of travel')
  await expect(direction).toHaveValue('0')
  await dragHandle(page, 'Drag to turn the linear move', 60, 0)
  await expect(direction).not.toHaveValue('0')
  await page.getByRole('button', { name: 'Add irrigation system' }).click()
  const row = page.getByRole('heading', { name: `Linear: ${name}` }).locator('../..')
  // Dragging a corner by pixels can nudge the length a few feet as well as the travel
  await expect(row).toContainText(/1,[23]\d\d ft long, travels [\d,]+ ft at \d+° from north/)

  // Delete it again (from its edit page): a new pivot sorts first on the dashboard, and its weather
  // cell has no seeded weather, so leaving it would change what later tests open
  await row.getByRole('link', { name: `Edit ${name}` }).click()
  page.once('dialog', (dialog) => dialog.accept())
  await page.getByRole('button', { name: 'Delete this linear move' }).click()
  await expect(page.getByRole('heading', { name: 'Setup', level: 1 })).toBeVisible()
  await expect(page.getByRole('heading', { name: `Linear: ${name}` })).toHaveCount(0)
})

test('a traveler is placed with a click and keeps no shape', async ({ page }) => {
  const name = `Lane ${Date.now()}`
  await page.goto('/pivots/new')
  await page.getByLabel('Name', { exact: true }).fill(name)
  await page.getByRole('radio', { name: /^Traveler/ }).check()
  await expect(page.getByLabel('Radius')).toHaveCount(0)
  await expect(page.getByLabel('Flow')).toBeVisible()
  const map = page.getByRole('application', { name: /click to place the traveler/ })
  await expect(map.locator('canvas')).toBeVisible()
  await map.click()
  await expect(page.getByText('Drag the pin to move the traveler.')).toBeVisible()
  await page.getByLabel('Equipment', { exact: true }).fill('Hard hose reel #9')
  await page.getByRole('button', { name: 'Add irrigation system' }).click()
  const heading = page.getByRole('heading', { name: `Traveler: ${name}` })
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
  await page.goto('/pivots/new')
  await placePivot(page)
  await page.getByLabel(/Partial circle/).check()
  const arcEnd = page.getByLabel('Arc ends at')
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
  await page.waitForTimeout(500)
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

test('an open grid cell keeps its column width, and clicking another cell opens that one', async ({ page }) => {
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
})

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
  // PLAN.md's Phase 5 target is 300 ms; CI machines are slower, so this only catches regressions
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
  await expect(page.getByRole('button', { name: 'Rainfall preferences' })).toHaveCount(0)
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

test('a field switches to entered rain only and back', async ({ page }) => {
  const planting = await firstPlantingPath(page)
  await page.goto(planting)
  // The section starts closed; following the summary's links opens it
  const summary = page.locator('#season-summary')
  await expect(page.getByRole('button', { name: 'Season summary' })).toHaveAttribute('aria-expanded', 'false')
  await page.getByRole('button', { name: 'Season summary' }).click()
  await expect(summary).toContainText('Your gauge and the model')
  const note = page.getByText('Rain: only what you enter, plus the forecast for the days ahead.')

  // The setting is the field's, on its page
  await page
    .getByRole('navigation', { name: 'Field and plantings' })
    .getByRole('link', { name: /^Field/ })
    .click()
  await expect(page).toHaveURL(/\/fields\/\d+/)
  const details = page.locator('#rainfall')
  const rainfall = page.getByRole('button', { name: 'Rainfall preferences' })
  if ((await rainfall.getAttribute('aria-expanded')) === 'false') await rainfall.click()
  const setting = (name: RegExp) => details.getByRole('radio', { name })
  await setting(/^Only the rain you enter/).check()
  await details.getByRole('button', { name: 'Save' }).click()
  await expect(setting(/^Only the rain you enter/)).toBeChecked()

  await page.goto(planting)
  await expect(note).toBeVisible()
  await expect(summary).toContainText('Modeled rain not used in the balance')

  // Back to following the operation, as the seed had it, from the note's link
  await page.getByRole('link', { name: 'Change this' }).click()
  await expect(details).toBeVisible()
  await setting(/^Follow the operation's setting/).check()
  await details.getByRole('button', { name: 'Save' }).click()
  await expect(setting(/^Follow the operation's setting/)).toBeChecked()
  await page.goto(planting)
  await expect(note).toBeHidden()
})

test('a field of plots lists each planting, on the dashboard, its page and Setup', async ({ page }) => {
  // The dashboard card lists the research field's four plots, each linking to its page
  await page.goto('/')
  const card = page.locator('main li').filter({ has: page.getByRole('heading', { name: 'Field: Arlington 525' }) })
  const plantings = card.getByRole('list', { name: 'Plantings on Arlington 525' })
  await expect(plantings.getByRole('listitem')).toHaveCount(4)
  await expect(card.getByText('Soybean, 300 × 60 ft (0.41 ac)')).toBeVisible()

  // The field page: its timeline, a status card per planting, and tabs for each
  await card.getByRole('link', { name: /Arlington 525/ }).click()
  await expect(page).toHaveURL(/\/fields\/\d+/)
  await expect(page.getByRole('heading', { name: 'Arlington 525', level: 1 })).toBeVisible()
  const timeline = page.getByRole('list', { name: /^Plantings on Arlington 525/ })
  await expect(timeline.getByRole('link')).toHaveCount(4)
  await expect(page.getByRole('button', { name: 'Rain and irrigation on the field' })).toBeVisible()

  // A plot's page: its size, and its own irrigation from the drip
  const tabs = page.getByRole('navigation', { name: 'Field and plantings' })
  await tabs.getByRole('link', { name: /^Snap bean/ }).click()
  await expect(page).toHaveURL(/\/plantings\/\d+/)
  await expect(page.getByText('Part of the field: 300 × 60 ft (0.41 ac)')).toBeVisible()
  await expect(tabs.getByRole('link', { name: /^Snap bean/ })).toHaveAttribute('aria-current', 'page')

  // Setup: each level labelled, the field's plantings on a timeline, each opening its form, with its size
  await page.goto('/setup')
  await expect(page.getByRole('heading', { name: 'Farm: Arlington Research' })).toBeVisible()
  const station = page.getByRole('heading', { name: 'Pivot: Station pivot' })
  await expect(station.getByRole('link', { name: 'Station pivot' })).toBeVisible()
  const bars = page.getByRole('list', { name: /^Plantings on Arlington 525/ })
  await bars.getByRole('button', { name: /^Edit Soybean/ }).click()
  const dialog = page.getByRole('dialog', { name: /^Edit Soybean on Arlington 525/ })
  await expect(dialog.getByRole('radio', { name: 'Part of the field' })).toBeChecked()
  await expect(dialog.getByLabel('Length', { exact: true })).toHaveValue('300')
  await expect(dialog.getByText('0.41 ac', { exact: true })).toBeVisible()
  await expect(dialog.getByRole('checkbox', { name: "Use the field's soil (Silt loam)" })).toBeChecked()

  // A plot can't be larger than the field
  await dialog.getByLabel('Length', { exact: true }).fill('3000')
  await expect(dialog.getByText("That's more than the field's 2.00 ac.")).toBeVisible()
  await expect(dialog.getByRole('button', { name: 'Save planting' })).toBeDisabled()

  // "Add the next planting" starts a new one the day after this one ends, the same size
  await dialog.getByRole('button', { name: 'Add the next planting' }).click()
  const next = page.getByRole('dialog', { name: 'Add the next planting on Arlington 525' })
  await expect(next.getByLabel('Length', { exact: true })).toHaveValue('300')
})

test("a new planting's harvest follows the crop and emergence until one is typed", async ({ page }) => {
  const year = new Date().getFullYear()
  await page.goto('/setup')
  await page.getByRole('button', { name: 'Add a planting to Cabbage' }).click()
  const dialog = page.getByRole('dialog', { name: /^Add a \d{4} planting to Cabbage/ })
  const harvest = dialog.getByLabel('Harvest or kill')
  await dialog.getByLabel('Crop').selectOption({ label: 'Soybean' })
  await expect(harvest).toHaveValue(`${year}-08-30`) // May 1 + 121 days
  await expect(dialog.getByText('A soybean season typically runs about 121 days')).toBeVisible()
  await dialog.getByLabel('Emergence').fill(`${year}-05-20`)
  await expect(harvest).toHaveValue(`${year}-09-18`)
  await harvest.fill(`${year}-10-01`)
  await dialog.getByLabel('Emergence').fill(`${year}-05-25`)
  await expect(harvest).toHaveValue(`${year}-10-01`)
})

test('a crop without its own canopy curve follows a generic one, or readings only', async ({ page }) => {
  const year = new Date().getFullYear()
  await page.goto('/setup')
  await page.getByRole('button', { name: 'Add a planting to Cabbage' }).click()
  const dialog = page.getByRole('dialog', { name: /^Add a \d{4} planting to Cabbage/ })
  await dialog.getByLabel('Crop').selectOption({ label: 'Onion' })
  const curves = dialog.getByRole('group', { name: 'Canopy curve' })
  await expect(curves.getByRole('radio', { name: /^Slow, partial cover \(suggested\)/ })).toBeChecked()
  await expect(curves.getByText('An approximation for onion')).toBeVisible()
  await expect(dialog.getByLabel('Harvest or kill')).toHaveValue(`${year}-08-29`) // May 1 + 120 days
  await curves.getByRole('radio', { name: 'No curve: readings only' }).check()
  await expect(curves.getByText('Irrigation scheduling works only if you enter percent cover regularly')).toBeVisible()
  // A crop with its own curve has no choice
  await dialog.getByLabel('Crop').selectOption({ label: 'Soybean' })
  await expect(curves).toBeHidden()
})

test("a perennial's cuttings restart its canopy, and are added and removed on its page", async ({ page }) => {
  await page.goto('/')
  const card = page.locator('main li').filter({ has: page.getByRole('heading', { name: 'Field: Hay north' }) })
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
  await page.getByRole('button', { name: 'Add a planting to Cabbage' }).click()
  const dialog = page.getByRole('dialog', { name: /^Add a \d{4} planting to Cabbage/ })
  // No scroll lock (G.1): the page keeps its scrollbar, so nothing shifts
  await expect(dialog).toBeVisible()
  expect(
    await page.evaluate(() => [getComputedStyle(document.body).overflow, document.body.style.paddingRight]),
  ).toEqual(['visible', ''])
  await expect(dialog.getByRole('radio', { name: /^Whole field/ })).toBeChecked()
  await expect(dialog.getByText('This overlaps: Cabbage')).toBeVisible()
  await dialog.getByLabel('Season start').fill(`${new Date().getFullYear()}-08-01`)
  await expect(dialog.getByRole('checkbox', { name: /^Replace: end Cabbage on Jul 31/ })).toBeVisible()
  // Part of the field leaves the cabbage alone, but can't overlap a planting covering the whole field
  await dialog
    .locator('label')
    .filter({ hasText: /^\s*Part of the field\s*$/ })
    .click()
  await expect(dialog.getByText('This overlaps a planting covering the whole field')).toBeVisible()
})

// Mid-season, so the demo's fields are in season whatever today's date (in November they're collapsed)
const midSeason = `/daily?date=${new Date().getFullYear()}-07-15`

test('daily entry saves rain for a field', async ({ page }) => {
  await page.goto(midSeason)
  const rain = page.getByLabel(/^Rain on /).first()
  await rain.fill('0.3')
  await page.getByRole('button', { name: /^Save / }).click()
  await expect(page.getByText(/^Saved /)).toBeVisible()
  await expect(page.getByLabel(/^Rain on /).first()).toHaveValue('0.3')

  await page
    .getByLabel(/^Rain on /)
    .first()
    .fill('')
  await page.getByRole('button', { name: /^Save / }).click()
  await expect(page.getByLabel(/^Rain on /).first()).toHaveValue('')
})

test('daily entry fills an irrigation group’s rain into its fields, and saves a plot’s irrigation and a cover reading', async ({
  page,
}) => {
  await page.goto(midSeason)
  const rain = (field: string) => page.getByLabel(`Rain on ${field}`, { exact: true })
  const gauge = page.getByLabel('Rain for all fields in River gauge')
  await gauge.fill('0.4')
  await expect(rain('Hay north')).toHaveValue('0.4')
  await expect(rain('River A')).toHaveValue('0.4')
  await rain('River A').fill('0.5')
  await expect(gauge).toHaveValue('')
  await expect(gauge).toHaveAttribute('placeholder', 'varies')

  const plots = page.getByRole('button', { name: 'Plots on Arlington 525' })
  if ((await plots.getAttribute('aria-expanded')) === 'false') await plots.click()
  const drip = page.getByLabel(/^Irrigation on Snap bean, .* on Arlington 525/)
  await drip.fill('0.3')
  const cover = page.getByLabel(/^Percent cover on Hay north/)
  await cover.fill('30')
  await page.getByRole('button', { name: /^Save / }).click()
  await expect(page.getByText(/^Saved /)).toBeVisible()
  await expect(rain('Hay north')).toHaveValue('0.4')
  await expect(rain('River A')).toHaveValue('0.5')
  await expect(drip).toHaveValue('0.3')
  await expect(cover).toHaveValue('30')

  // Collapsing the group is remembered
  await page.getByRole('button', { name: 'Irrigation systems in River gauge' }).click()
  await expect(rain('Hay north')).toBeHidden()
  await page.reload()
  await expect(rain('Hay north')).toBeHidden()
  await page.getByRole('button', { name: 'Irrigation systems in River gauge' }).click()

  // Leave the day as it was for other tests: one value from the group, then clear it from there
  await gauge.fill('0.4')
  await expect(rain('River A')).toHaveValue('0.4')
  await gauge.fill('')
  await drip.fill('')
  await cover.fill('')
  await page.getByRole('button', { name: /^Save / }).click()
  await expect(page.getByText(/^Saved /)).toBeVisible()
  await expect(rain('River A')).toHaveValue('')
})

test('daily entry asks before changing the date with unsaved values', async ({ page }) => {
  await page.goto(midSeason)
  const date = await page.getByLabel('Date', { exact: true }).inputValue()
  await page
    .getByLabel(/^Rain on /)
    .first()
    .fill('0.2')

  page.once('dialog', (dialog) => dialog.dismiss())
  await page.getByRole('button', { name: 'Previous day' }).click()
  await expect(page.getByLabel('Date', { exact: true })).toHaveValue(date)
  await expect(page.getByLabel(/^Rain on /).first()).toHaveValue('0.2')

  page.once('dialog', (dialog) => dialog.accept())
  await page.getByRole('button', { name: 'Previous day' }).click()
  await expect(page.getByLabel('Date', { exact: true })).not.toHaveValue(date)
})

test('adding a pivot irrigation on a date that has one offers to edit it instead', async ({ page }) => {
  await page.goto(await firstPlantingPath(page))
  await page.locator('main a[href*="/pivots/"]').first().click()

  // Add one for today; the form resets to today, which now has an irrigation
  await page.getByLabel('Amount').fill('0.4')
  await page.getByRole('button', { name: 'Save irrigation' }).click()
  await expect(page.getByRole('status').filter({ hasText: 'Saving will replace it' })).toBeVisible()

  await page.getByRole('button', { name: 'Edit that one instead' }).click()
  await expect(page.getByRole('heading', { name: /^Edit / })).toBeVisible()
  await expect(page.getByLabel('Amount')).toHaveValue('0.4')

  page.once('dialog', (dialog) => dialog.accept())
  await page.locator('main table tbody tr').first().getByRole('button', { name: 'Delete' }).click()
  await expect(page.getByText(/No irrigation entered/)).toBeVisible()
})

test('the weather charts follow the page width without overlapping', async ({ page }) => {
  await page.setViewportSize({ width: 1400, height: 900 })
  await page.goto(await firstZonePath(page))
  const card = (name: string) =>
    page
      .getByRole('button', { name: `About the ${name} chart` })
      .locator('xpath=ancestor::div[contains(@class, "rounded-lg")][1]')
  await expect(card('Precipitation').locator('canvas').first()).toBeVisible()

  // Narrower (still two columns), then wide again: the left column's cards end before the right's begin
  for (const width of [900, 1400]) {
    await page.setViewportSize({ width, height: 900 })
    await expect(async () => {
      const left = (await card('Precipitation').boundingBox())!
      const right = (await card('Evapotranspiration').boundingBox())!
      const canvas = (await card('Precipitation').locator('canvas').first().boundingBox())!
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
  await card.getByText('Summary and data').click()
  await expect(card.getByText(/^Last 7 days: Rain /)).toBeVisible()
  const table = card.getByRole('table', { name: /^Precipitation by day/ })
  await expect(table.getByRole('columnheader', { name: 'Rain (in)', exact: true })).toBeVisible()
  await expect(table.getByRole('rowheader', { name: /\(forecast\)$/ }).first()).toBeVisible()

  // Its values download as a CSV, opening with frontmatter (built in the browser)
  const [download] = await Promise.all([
    page.waitForEvent('download'),
    card.getByRole('button', { name: 'Download CSV of the Precipitation data' }).click(),
  ])
  expect(download.suggestedFilename()).toMatch(/^wisp-.+-precipitation\.csv$/)
  const csv = readFileSync(await download.path(), 'utf8')
  expect(csv).toMatch(/^\uFEFF"?WISP weather chart: Precipitation, /)
  expect(csv).toContain('\r\nDate,Forecast,Rain (in)')
  expect(errors).toEqual([])
})

test('setup downloads the season report, and a weather zone its weather', async ({ page }) => {
  await page.goto('/setup')
  const [report] = await Promise.all([
    page.waitForEvent('download'),
    page.getByRole('link', { name: /season report \(CSV\)$/ }).click(),
  ])
  expect(report.suggestedFilename()).toMatch(/^wisp-season-.+\.csv$/)
  const csv = readFileSync(await report.path(), 'utf8')
  expect(csv).toMatch(/^\uFEFF"?WISP season report, \d{4}/)
  expect(csv).toContain('Irrigation by irrigation system')

  await page.goto(await firstZonePath(page))
  const [all] = await Promise.all([
    page.waitForEvent('download'),
    page.getByRole('link', { name: "download all of this zone's weather" }).click(),
  ])
  expect(readFileSync(await all.path(), 'utf8')).toMatch(/^\uFEFF"?WISP weather, /)
})

test('alerts previews today’s email and sends a test, then waits', async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto('/alerts')
  await expect(page.getByLabel('Email frequency')).toBeVisible()

  await page.getByRole('button', { name: 'Preview today’s email' }).click()
  const email = page.frameLocator('iframe[title="Daily email preview"]')
  await expect(email.getByRole('heading', { name: 'Your fields this morning' })).toBeVisible()

  // Both projects sign in as one user, who can send one test per cooldown (reset by e2e/seed.rb)
  if (test.info().project.name !== 'desktop') return
  await page.getByRole('button', { name: 'Send me a test email' }).click()
  await expect(page.getByText('Test email sent to')).toBeVisible()
  await expect(page.getByRole('button', { name: /Send a test email \(again in \d+ min\)/ })).toBeDisabled()
  // The preview stays open across the redirect
  await expect(email.getByRole('heading', { name: 'Your fields this morning' })).toBeVisible()

  // Changes save themselves, rebuilding the open preview in the same request; the preview waits for them
  const status = page.getByRole('status').filter({ hasText: /Saving|save automatically/ })
  await page.getByLabel('Email frequency').selectOption('needed')
  const field = page.getByRole('checkbox', { name: 'North corn' })
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
  // Playwright's trace recorder tries to run its snapshot script in the preview's sandboxed frame
  expect(errors.filter((error) => !error.includes("Blocked script execution in 'about:srcdoc'"))).toEqual([])
})

test('glossary terms explain themselves on hover or tap', async ({ page }) => {
  await page.goto(await firstPlantingPath(page))
  const term = page.getByRole('button', { name: 'allowable depletion', exact: true })
  if (test.info().project.name === 'phone') await term.tap()
  else await term.hover()
  await expect(page.getByText('The water left in the root zone that the crop can use without stress.')).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(page.getByText('The water left in the root zone that the crop can use without stress.')).toBeHidden()
})

test('a field outline is copied from its pivot, a plot pinned, and the outline saved (G.10)', async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto(await researchFieldPath(page))
  await page.getByRole('link', { name: /^(Add an outline|Outline)$/ }).click()
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Outline: Arlington 525')
  await expect(page.locator('.maplibregl-canvas')).toBeVisible()

  // The 600 ft pivot's circle, about 26 acres, offered for the 2 acre field's area (left unticked)
  await expect(page.getByRole('group', { name: 'Outline tools' })).toBeEnabled()
  await page.getByRole('button', { name: 'Same as the pivot' }).first().click()
  await expect(page.getByText(/The outline: 2[56]\.\d ac/)).toBeVisible()
  const useArea = page.getByRole('checkbox', { name: /for the field's area$/ })
  await expect(useArea).not.toBeChecked()

  // A plot pinned by a click on the map
  const plot = page.getByRole('listitem').filter({ hasText: 'Soybean' })
  await plot.getByRole('button', { name: /^(Place|Move) its pin$/ }).click()
  await expect(plot.getByText('Click the map where it is.')).toBeVisible()
  await expect(page.locator('.maplibregl-canvas')).toBeInViewport({ ratio: 0.9 })
  await page.waitForTimeout(500) // the scroll settles
  const box = (await page.locator('.maplibregl-canvas').boundingBox())!
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2)
  await expect(plot.getByRole('button', { name: 'Move its pin', exact: true })).toBeVisible()
  await expect(page.locator('.maplibregl-marker', { hasText: 'Soybean' })).toBeVisible()

  await page.getByRole('button', { name: 'Save' }).click()
  await expect(page.getByText('Saved the outline of Arlington 525')).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Arlington 525', level: 1 })).toBeVisible()
  await expect(page.getByText('2.0 ac ·').first()).toBeVisible() // the area as it was
  await page.goto('/setup')
  await expect(page.getByText(/outline 2[56]\.\d ac/)).toBeVisible()
  // The field's dialog shows the shape; the pin was saved
  await page.getByRole('button', { name: 'Edit Arlington 525' }).click()
  const dialog = page.getByRole('dialog')
  await expect(dialog.getByRole('img', { name: 'The outline of Arlington 525' })).toBeVisible()
  await dialog.getByRole('link', { name: 'Edit shape' }).click()
  await expect(page.locator('.maplibregl-marker', { hasText: 'Soybean' })).toBeVisible()
  expect(errors).toEqual([])
})

test('a field outline is drawn corner by corner, or read from a file (G.10)', async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto('/setup')
  await page.getByRole('button', { name: 'Edit Market garden' }).click()
  await page
    .getByRole('dialog')
    .getByRole('link', { name: /^(Add a shape|Edit shape)$/ })
    .click()
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Outline: Market garden')
  if (await page.getByRole('button', { name: 'Remove the outline' }).isVisible())
    await page.getByRole('button', { name: 'Remove the outline' }).click()

  // Four corners, then the first again to close it: the part is ready to adjust
  await expect(page.getByRole('group', { name: 'Outline tools' })).toBeEnabled()
  await page.getByRole('button', { name: 'Draw the outline' }).click()
  await expect(page.getByText(/Click the map at each corner/)).toBeVisible()
  const box = (await page.locator('.maplibregl-canvas').boundingBox())!
  const at = (x: number, y: number) => [box.x + box.width * x, box.y + box.height * y] as const
  for (const [x, y] of [at(0.4, 0.4), at(0.6, 0.4), at(0.6, 0.6), at(0.4, 0.6), at(0.4, 0.4)]) {
    await page.mouse.click(x, y)
    await page.waitForTimeout(150)
  }
  await expect(page.getByRole('button', { name: 'Edit corners' })).toHaveAttribute('aria-pressed', 'true')
  const drawn = page.getByText(/^The outline: [\d.]+ (ac|ha)\./)
  await expect(drawn).toBeVisible()
  const first = await drawn.textContent()

  // Drawing again asks first, and the new outline replaces the old one: a field is one polygon
  page.once('dialog', (dialog) => dialog.accept())
  await page.getByRole('button', { name: 'Draw a new one' }).click()
  for (const [x, y] of [at(0.45, 0.45), at(0.55, 0.45), at(0.55, 0.55), at(0.45, 0.55), at(0.45, 0.45)]) {
    await page.mouse.click(x, y)
    await page.waitForTimeout(150)
  }
  await expect(page.getByRole('button', { name: 'Edit corners' })).toHaveAttribute('aria-pressed', 'true')
  await expect(drawn).not.toHaveText(first!)

  // A KML file replaces it: one shape, 0.01° by 0.005° at 43.3°N
  await page.getByLabel('Outline file').setInputFiles('spec/fixtures/files/outlines/google_earth.kml')
  await expect(page.getByText(/^The outline: 111\.2 ac\./)).toBeVisible()

  // A shapefile with two fields asks which one
  await page.getByLabel('Outline file').setInputFiles('spec/fixtures/files/outlines/clu_utm.zip')
  await expect(page.getByText('This file has 2 shapes. Which is Market garden?')).toBeVisible()
  await page.getByRole('button', { name: 'Home South' }).click()
  await expect(page.getByText(/^The outline: 10\d\.\d ac\./)).toBeVisible()

  // Leaving asks first; nothing is saved
  page.once('dialog', (dialog) => dialog.accept())
  await page.getByRole('link', { name: 'Cancel' }).click()
  await expect(page.getByRole('heading', { name: 'Setup', level: 1 })).toBeVisible()
  expect(errors).toEqual([])
})

test('field outlines are imported from a shapefile, matched to fields or new ones (G.10)', async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto('/setup')
  await page.getByRole('link', { name: 'Import field outlines' }).click()
  await expect(page.getByRole('heading', { name: 'Import field outlines', level: 1 })).toBeVisible()
  await page.getByLabel('Choose a file').setInputFiles('spec/fixtures/files/outlines/clu_utm.zip')

  // Two shapes, named from FIELD_NAME, far from any system and matching no field: both skipped
  await expect(page.getByText(/^2 shapes\./)).toBeVisible()
  await expect(page.getByLabel('Names from')).toHaveValue('FIELD_NAME')
  const first = page.locator('#shape-0')
  const second = page.locator('#shape-1')
  await expect(first.getByRole('button', { name: '1. Home North' })).toBeVisible()
  await expect(page.locator('#shape-0-field')).toHaveValue('skip')
  await expect(page.getByRole('button', { name: /^Save/ })).toBeDisabled()

  // A new field asks for its system, and offers the outline's name and a soil
  await page.locator('#shape-0-field').selectOption('new')
  await expect(first.getByText('Choose the system that waters it')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Save the outline' })).toBeDisabled()
  await page.locator('#shape-0-system').selectOption({ label: 'Arlington Research › Pivot: Station pivot' })
  await expect(first.getByLabel("New field's name")).toHaveValue('Home North')
  await page.locator('#shape-0-field').selectOption('skip')

  // The second outlines an existing field
  const garden = await page.locator('#shape-1-field option', { hasText: /^Market garden/ }).getAttribute('value')
  await page.locator('#shape-1-field').selectOption(garden!)
  await expect(second.getByRole('combobox', { name: 'Field' })).toHaveValue(/^field:/)
  await page.getByRole('button', { name: 'Save the outline' }).click()
  await expect(page.getByText('Saved an outline')).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Setup', level: 1 })).toBeVisible()
  await page.getByRole('button', { name: 'Edit Market garden' }).click()
  await expect(page.getByRole('dialog').getByRole('img', { name: 'The outline of Market garden' })).toBeVisible()
  await page.keyboard.press('Escape')

  // That shape is near Arlington, nowhere near Market garden's pivot at Coloma: Setup says so
  const issues = page.getByRole('region', { name: 'Outlines to check' })
  await expect(issues).toContainText(/Market garden's outline isn't under Pivot: Home pivot \(\d+\.\d mi away\)/)
  expect(errors).toEqual([])
})

test('the map shades outlined fields instead of badging them, and marks the selected one (G.10)', async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto('/map')
  await expect(page.locator('.maplibregl-canvas')).toBeVisible()
  // North 160's two fields have outlines, so it has no marker; Home pivot's don't
  await expect(page.getByRole('button', { name: /^Pivot Home pivot: / })).toBeAttached()
  await expect(page.getByRole('button', { name: /^Pivot North 160: / })).toHaveCount(0)

  // A field picked from the list (as a click in its outline does) is marked in its system's panel
  const list = page.getByRole('complementary', { name: 'Fields' })
  await list.getByRole('button', { name: /North potatoes.*on the map$/ }).click()
  const panel = page.getByRole('region', { name: 'Pivot: North 160' })
  await expect(panel.locator('li[aria-current="true"]')).toContainText('North potatoes')

  // A click in a field's outline selects that field, not the system drawn over it (G.14). The map
  // flies the pivot to 170 px left of center beside the panel (wide screens), at zoom 13.5 or more,
  // where its 1,300 ft radius is over 80 px: North corn is its east half.
  if (test.info().project.name === 'desktop') {
    await page.waitForTimeout(1500) // the flight ends
    const box = (await page.locator('.maplibregl-canvas').boundingBox())!
    await page.mouse.click(box.x + box.width / 2 - 170 + 40, box.y + box.height / 2)
    await expect(panel.locator('li[aria-current="true"]')).toContainText('North corn')
  }

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
