import { expect, type Page, test } from '@playwright/test'

// Smoke tests over the demo account seeded by e2e/seed.rb: every page renders without script
// errors or sideways scrolling, and the main ways of entering data save.

const EMAIL = 'e2e@example.com'
const PASSWORD = 'e2e-password-1'

/** Uncaught errors and console errors, except resources that failed to load (map tiles in CI) */
function watchErrors(page: Page): string[] {
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(`${page.url()}: ${error.message}`))
  page.on('console', (message) => {
    if (message.type() === 'error' && !message.text().startsWith('Failed to load resource')) {
      errors.push(`${page.url()}: ${message.text()}`)
    }
  })
  return errors
}

async function signIn(page: Page) {
  await page.goto('/account/sign_in')
  await page.getByLabel('Email').fill(EMAIL)
  await page.getByLabel('Password', { exact: true }).fill(PASSWORD)
  await page.getByRole('button', { name: 'Sign in' }).click()
  await expect(page.getByRole('navigation', { name: 'Main' })).toBeVisible()

  // The demo farms are a second group; the user's own (empty) group is the default. The switcher
  // is its own menu on wider screens, and part of the account menu on phones.
  if ((await page.getByRole('heading', { name: 'Dashboard' }).locator('..').textContent())?.includes('Demo farms'))
    return
  const switcher = page.getByRole('button', { name: 'Switch farm operation' })
  await ((await switcher.isVisible()) ? switcher : page.getByRole('button', { name: 'Account menu' })).click()
  await page.getByRole('menuitem', { name: 'Demo farms' }).click()
  await expect(page.getByRole('heading', { name: 'Dashboard' }).locator('..')).toContainText('Demo farms')
}

async function firstFieldPath(page: Page): Promise<string> {
  await page.goto('/')
  const href = await page.locator('main ul li a').first().getAttribute('href')
  return new URL(href!, page.url()).pathname
}

test.beforeEach(async ({ page }) => {
  await signIn(page)
})

test('every page renders without errors or sideways scrolling', async ({ page }) => {
  const errors = watchErrors(page)
  const field = await firstFieldPath(page)
  await page.goto(field)
  const pivot = new URL((await page.locator('main a[href*="/pivots/"]').first().getAttribute('href'))!, page.url())
    .pathname

  await page.goto('/admin/users')
  const user = new URL((await page.locator('main a[href*="/admin/users/"]').first().getAttribute('href'))!, page.url())
    .pathname

  const paths = [
    '/',
    field,
    '/setup',
    '/daily',
    pivot,
    `${pivot}/edit`,
    '/pivots/new',
    '/field_groups',
    '/setup/start',
    '/settings',
    '/alerts',
    '/about',
    '/operation',
    '/admin/weather',
    '/admin/users',
    user,
  ]
  for (const path of paths) {
    await page.goto(path)
    await expect(page.locator('main h1').first()).toBeVisible()
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)
    expect(overflow, `${path} scrolls sideways`).toBeLessThanOrEqual(0)
  }

  await page.goto('/field_groups')
  await page.locator('main a[href*="/field_groups/"]').first().click()
  await expect(page.locator('[data-grid="group-days"]').first()).toBeVisible()

  expect(errors).toEqual([])
})

test('the dashboard shows field cards with a status', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible()
  await expect(page.locator('main ul li').first()).toBeVisible()
  await expect(page.getByText('AD today').first()).toBeVisible()
  await expect(page.getByRole('heading', { name: /^Farm: / }).first()).toBeVisible()
  await expect(page.getByRole('heading', { name: /^Field: / }).first()).toBeVisible()

  // A pivot's View opens its irrigation and weather
  const pivot = page.getByRole('heading', { name: /^Pivot: / }).first()
  const name = (await pivot.textContent())!.replace('Pivot:', '').trim()
  await page.getByRole('link', { name: `View ${name}` }).click()
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(`Pivot: ${name}`)
  await expect(page.getByRole('heading', { name: /^Weather at this pivot/ })).toBeVisible()
})

test('a grid cell saves on Enter, and Escape cancels without saving', async ({ page }) => {
  await page.goto(await firstFieldPath(page))
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
  await page.goto(await firstFieldPath(page))
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
  await page.goto(await firstFieldPath(page))
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

test('a field switches to entered rain only and back', async ({ page }) => {
  await page.goto(await firstFieldPath(page))
  const details = page.locator('#season-details')
  await expect(details.getByRole('heading', { name: 'Season details and settings' })).toBeVisible()
  await expect(details).toContainText('Your gauge and the model')
  const setting = (name: RegExp) => details.getByRole('radio', { name })
  const note = page.getByText("Rain: only what you enter, and the forecast's ahead")

  await setting(/^Only the rain you enter/).check()
  await details.getByRole('button', { name: 'Save' }).click()
  await expect(note).toBeVisible()
  await expect(details).toContainText('Modeled, left out of the balance')

  // Back to following the operation, as the seed had it
  await setting(/^The operation's setting/).check()
  await details.getByRole('button', { name: 'Save' }).click()
  await expect(note).toBeHidden()
  await expect(setting(/^The operation's setting/)).toBeChecked()
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
  await page.goto(await firstFieldPath(page))
  await page.locator('main a[href*="/pivots/"]').first().click()

  // Add one for today; the form resets to today, which now has an irrigation
  await page.getByLabel('Amount').fill('0.4')
  await page.getByRole('button', { name: 'Save irrigation' }).click()
  await expect(page.getByRole('status').filter({ hasText: 'saving replaces it' })).toBeVisible()

  await page.getByRole('button', { name: 'Edit that one instead' }).click()
  await expect(page.getByRole('heading', { name: /^Edit / })).toBeVisible()
  await expect(page.getByLabel('Amount')).toHaveValue('0.4')

  page.once('dialog', (dialog) => dialog.accept())
  await page.locator('main table tbody tr').first().getByRole('button', { name: 'Delete' }).click()
  await expect(page.getByText(/No irrigation entered/)).toBeVisible()
})

test('a weather chart explains itself, and resets after zooming', async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto(await firstFieldPath(page))
  const weather = page.getByRole('heading', { name: 'Weather at this pivot' }).locator('..').getByRole('button')
  if ((await weather.getAttribute('aria-expanded')) === 'false') await weather.click()

  const info = page.getByRole('button', { name: 'About the Precipitation chart' })
  await info.click()
  await expect(page.getByRole('tooltip')).toContainText('rain plus the water in snow')
  await info.click()
  await expect(page.getByRole('tooltip')).toBeHidden()

  const card = info.locator('xpath=ancestor::div[contains(@class, "rounded-lg")][1]')
  const reset = page.getByRole('button', { name: 'Reset Precipitation chart' })
  await expect(reset).toBeHidden()
  const box = (await card.locator('canvas').first().boundingBox())!
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 3)
  await page.mouse.wheel(0, -400)
  await expect(reset).toBeVisible()
  await reset.click()
  await expect(reset).toBeHidden()
  expect(errors).toEqual([])
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

  // Saving rebuilds the open preview in the same request
  await page.getByLabel('Email frequency').selectOption('needed')
  await page.getByRole('button', { name: 'Save alert settings' }).click()
  await expect(page.getByText('Alert settings saved')).toBeVisible()
  await expect(email.getByRole('heading', { name: 'Your fields this morning' })).toBeVisible()
  await expect(page.getByLabel('Email frequency')).toHaveValue('needed')
  // Playwright's trace recorder tries to run its snapshot script in the preview's sandboxed frame
  expect(errors.filter((error) => !error.includes("Blocked script execution in 'about:srcdoc'"))).toEqual([])
})

test('glossary terms explain themselves on hover or tap', async ({ page }) => {
  await page.goto(await firstFieldPath(page))
  const term = page.getByRole('button', { name: 'allowable depletion', exact: true })
  if (test.info().project.name === 'phone') await term.tap()
  else await term.hover()
  await expect(page.getByText('The water left in the root zone that the crop can use without stress.')).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(page.getByText('The water left in the root zone that the crop can use without stress.')).toBeHidden()
})
