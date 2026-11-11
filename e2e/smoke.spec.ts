import { readFileSync } from 'node:fs'

import { expect, type Page, test } from '@playwright/test'

import { firstPlantingPath, signIn, watchErrors } from './session'

// Smoke tests over the demo account seeded by e2e/seed.rb: the main ways of entering data save, and
// the map and charts work. accessibility.spec.ts visits every page, failing on script errors too.

test.beforeEach(async ({ page }) => {
  await signIn(page)
})

test("a field group's page shows its grid", async ({ page }) => {
  await page.goto('/field_groups')
  await page.locator('main a[href*="/field_groups/"]').first().click()
  await expect(page.locator('[data-grid="group-days"]').first()).toBeVisible()
})

test('the dashboard shows field cards with a status', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible()
  await expect(page.locator('main ul li').first()).toBeVisible()
  await expect(page.getByText('AD today').first()).toBeVisible()
  await expect(page.getByRole('heading', { name: /^Farm: / }).first()).toBeVisible()
  await expect(page.getByRole('heading', { name: /^Field: / }).first()).toBeVisible()

  // A pivot's name links to its page: its irrigation and weather
  const pivot = page.getByRole('heading', { name: /^Pivot: / }).first()
  const name = (await pivot.textContent())!.replace('Pivot:', '').trim()
  await expect(page.getByRole('link', { name: `Irrigation on ${name}` })).toBeVisible()
  await pivot.getByRole('link', { name }).click()
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(`Pivot: ${name}`)
  await expect(page.getByRole('heading', { name: /^Weather at this pivot/ })).toBeVisible()
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
  const map = page.getByRole('application', { name: /click to place the pivot/ })
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
  await page.getByLabel('Name').fill(name)
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
  await page.getByRole('button', { name: 'Add pivot' }).click()
  const row = page.getByRole('heading', { name }).locator('../..')
  await expect(row).toContainText(/linear move, 1,300 ft long, travels [\d,]+ ft at \d+° from north/)

  // Delete it again: a new pivot sorts first on the dashboard, and its weather cell has no seeded
  // weather, so leaving it would change what later tests open
  page.once('dialog', (dialog) => dialog.accept())
  await row.getByRole('button', { name: 'Delete' }).click()
  await expect(page.getByRole('heading', { name })).toHaveCount(0)
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

  // Once the card scrolls away, a bar across the top keeps the date in view, and the weather charts'
  // range bar sticks below it rather than under it
  const topBar = page.getByTestId('time-travel-bar')
  await expect(topBar).toHaveCount(0)
  const range = page.locator('div.sticky', { hasText: 'Weather data range:' })
  const weather = page.locator('#weather [data-section-toggle]')
  if ((await weather.getAttribute('aria-expanded')) === 'false') await weather.click()
  await range.scrollIntoViewIfNeeded()
  await page.mouse.wheel(0, 600)
  await expect(topBar).toBeVisible()
  await expect(topBar).toContainText('as of')
  await expect
    .poll(async () => (await range.boundingBox())!.y - (await topBar.boundingBox())!.height)
    .toBeGreaterThanOrEqual(-0.5)
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

  // Setup: the field's plantings on a timeline, each opening its form, with its size
  await page.goto('/setup')
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

test('a new whole-field planting over another offers to replace it', async ({ page }) => {
  await page.goto('/setup')
  await page.getByRole('button', { name: 'Add a planting to Cabbage' }).click()
  const dialog = page.getByRole('dialog', { name: /^Add a \d{4} planting to Cabbage/ })
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

test('daily entry saves rain for a field', async ({ page }) => {
  await page.goto('/daily')
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

test('daily entry asks before changing the date with unsaved values', async ({ page }) => {
  await page.goto('/daily')
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
  await page.goto(await firstPlantingPath(page))
  const weather = page.getByRole('button', { name: 'Weather at this pivot' })
  if ((await weather.getAttribute('aria-expanded')) === 'false') await weather.click()
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
  await page.goto(await firstPlantingPath(page))
  const weather = page.getByRole('button', { name: 'Weather at this pivot' })
  if ((await weather.getAttribute('aria-expanded')) === 'false') await weather.click()

  const info = page.getByRole('button', { name: 'About the Precipitation chart' })
  await info.click()
  await expect(page.getByRole('tooltip')).toContainText('rain plus the water in snow')
  await info.click()
  await expect(page.getByRole('tooltip')).toBeHidden()

  const card = info.locator('xpath=ancestor::div[contains(@class, "rounded-lg")][1]')
  // Zooming one chart moves the season slider (and the other charts) with it, whose reset puts them all back
  const reset = page.getByRole('button', { name: 'Reset', exact: true })
  await expect(reset).toBeHidden()
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

test('setup downloads the season report, and a pivot its weather', async ({ page }) => {
  await page.goto('/setup')
  const [report] = await Promise.all([
    page.waitForEvent('download'),
    page.getByRole('link', { name: /season report \(CSV\)$/ }).click(),
  ])
  expect(report.suggestedFilename()).toMatch(/^wisp-season-.+\.csv$/)
  const csv = readFileSync(await report.path(), 'utf8')
  expect(csv).toMatch(/^\uFEFF"?WISP season report, \d{4}/)
  expect(csv).toContain('Irrigation by pivot')

  await page.goto(await firstPlantingPath(page))
  const weather = page.getByRole('button', { name: 'Weather at this pivot' })
  if ((await weather.getAttribute('aria-expanded')) === 'false') await weather.click()
  const [all] = await Promise.all([
    page.waitForEvent('download'),
    page.getByRole('link', { name: "download all of this pivot's weather" }).click(),
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
