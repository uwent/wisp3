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

  // The demo farms are a second group; the user's own (empty) group is the default
  const switcher = page.getByRole('button', { name: 'Switch farm operation' })
  if (!(await switcher.textContent())?.includes('Demo farms')) {
    await switcher.click()
    await page.getByRole('menuitem', { name: 'Demo farms' }).click()
    await expect(switcher).toContainText('Demo farms')
  }
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
  const pivot = new URL((await page.locator('main a[href*="/pivots/"]').first().getAttribute('href'))!, page.url()).pathname

  const paths = ['/', field, '/setup', '/daily', pivot, `${pivot}/edit`, '/pivots/new', '/field_groups', '/setup/start', '/settings']
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

test('daily entry saves rain for a field', async ({ page }) => {
  await page.goto('/daily')
  const rain = page.getByLabel(/^Rain on /).first()
  await rain.fill('0.3')
  await page.getByRole('button', { name: /^Save / }).click()
  await expect(page.getByText(/^Saved /)).toBeVisible()
  await expect(page.getByLabel(/^Rain on /).first()).toHaveValue('0.3')

  await page.getByLabel(/^Rain on /).first().fill('')
  await page.getByRole('button', { name: /^Save / }).click()
  await expect(page.getByLabel(/^Rain on /).first()).toHaveValue('')
})
