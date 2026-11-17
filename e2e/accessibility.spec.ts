import { writeFileSync } from 'node:fs'

import AxeBuilder from '@axe-core/playwright'
import { type Page } from '@playwright/test'

import { DEMO, literal } from './demo'
import { firstPlantingPath, firstZonePath, impersonateGrower, signedInPages, signIn, watchErrors } from './session'
import { expect, test } from './test'

// WCAG 2.1 A and AA checks (axe) on every page, in light (desktop) and dark (phone), which also fail
// on script errors, and on desktop each page's reflow (320 px wide, 200% text). Every page is
// scanned before the test fails, and A11Y_REPORT=path writes the violations found as JSON.

const TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa']

type Finding = { path: string; rule: string; impact: string | null | undefined; help: string; targets: string[] }

const findings: Finding[] = []

async function scan(page: Page, path: string) {
  await page.goto(path)
  await expect(page.locator('main h1').first()).toBeVisible()
  // Open the collapsed sections (CollapsibleSection) so what's in them is checked too
  const closed = page.locator('[data-section-toggle][aria-expanded="false"]')
  while ((await closed.count()) > 0) await closed.first().click()
  // A shape page's tools once its map is ready: until then their fieldset is disabled, which axe
  // doesn't count as disabled for contrast, though WCAG exempts it
  const tools = page.getByRole('group', { name: 'Shape tools' })
  if (await tools.count()) await expect(tools).toBeEnabled()
  // Nothing hovered where the last click left the pointer
  await page.mouse.move(0, 0)
  // Charts draw after ECharts loads
  for (const chart of await page.locator('[data-chart]').all()) await expect(chart.locator('canvas')).toBeAttached()
  const { violations } = await new AxeBuilder({ page }).withTags(TAGS).analyze()
  for (const violation of violations) {
    findings.push({
      path,
      rule: violation.id,
      impact: violation.impact,
      help: violation.help,
      targets: violation.nodes.map((node) => node.target.join(' ')),
    })
  }
  expect
    .soft(
      violations.map(
        (violation) =>
          `${violation.id} (${violation.nodes.length}): ${violation.help} at ${violation.nodes.map((node) => node.target.join(' ')).join(', ')}${violation.nodes[0]?.failureSummary ? ` (${violation.nodes[0].failureSummary.replace(/\s+/g, ' ')})` : ''}`,
      ),
      `${path} has accessibility violations`,
    )
    .toEqual([])

  if (test.info().project.name === 'desktop') await reflows(page, path)
}

// WCAG 1.4.10: 320 CSS px wide with no sideways page scroll (grids and tables scroll inside
// themselves); WCAG 1.4.4: text at 200%. Checked on the page as scanned, its sections open.
async function reflows(page: Page, path: string) {
  const overflow = () => page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)
  const size = page.viewportSize()!
  await page.setViewportSize({ width: 320, height: 640 })
  await page.waitForFunction(() => window.innerWidth === 320)
  expect.soft(await overflow(), `${path} scrolls sideways at 320 px`).toBeLessThanOrEqual(0)
  await page.setViewportSize(size)
  await page.waitForFunction((width) => window.innerWidth === width, size.width)
  const larger = await page.addStyleTag({ content: 'html { font-size: 200% !important }' })
  expect.soft(await overflow(), `${path} scrolls sideways with 200% text`).toBeLessThanOrEqual(0)
  await larger.evaluate((element) => (element as HTMLElement).remove())
}

test.afterAll(() => {
  const report = process.env.A11Y_REPORT
  if (report)
    writeFileSync(report.replace('.json', `-${test.info().project.name}.json`), JSON.stringify(findings, null, 2))
})

test('signed-out pages', { tag: '@phone' }, async ({ page }) => {
  const errors = watchErrors(page)
  for (const path of [
    '/',
    '/about',
    '/account/sign_in',
    '/account/sign_up',
    '/account/password/new',
    '/account/confirmation/new',
    // Pages reached from an email's link, here with a token that doesn't work (their other states
    // share the layout)
    '/account/sign_in_link/open?token=e2e',
    '/account/password/edit?reset_password_token=e2e',
    '/account/confirmation?confirmation_token=e2e',
    '/digest/unsubscribe?token=e2e',
  ]) {
    await scan(page, path)
  }
  expect(errors).toEqual([])
})

test('the example farm, signed out (G.8)', { tag: '@phone' }, async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto('/example')
  await expect(page.getByRole('status').filter({ hasText: "You're viewing an example farm" })).toBeVisible()
  const link = (selector: string) => page.locator(`main ${selector}`).first().getAttribute('href')
  const planting = (await link('a[href*="/plantings/"]'))!
  await page.goto(planting)
  const field = (await link('a[href*="/fields/"]'))!
  const pivot = (await link('a[href*="/pivots/"]'))!
  for (const path of ['/', '/map', planting, field, pivot, '/weather']) {
    await scan(page, path)
  }
  expect(errors).toEqual([])
})

test('signed-in pages', { tag: '@phone' }, async ({ page }) => {
  test.setTimeout(120_000)
  await signIn(page)
  const paths = await signedInPages(page)
  const errors = watchErrors(page)
  for (const path of paths) {
    await scan(page, path)
  }
  expect(errors).toEqual([])
})

test('a field viewed on an earlier date (time travel)', { tag: '@phone' }, async ({ page }) => {
  await signIn(page)
  await page.goto(await firstPlantingPath(page))
  const rewind = page.getByRole('button', { name: 'View this field on an earlier date' })
  // Once the page is drawn, or the button's absence means nothing
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible()
  test.skip(!(await rewind.isVisible()), "the field's season has no earlier days on this date")
  await rewind.click()
  await page.getByRole('button', { name: 'View', exact: true }).click()
  await expect(page).toHaveURL(/as_of=/)
  const url = new URL(page.url())
  const errors = watchErrors(page)
  await scan(page, url.pathname + url.search)
  expect(errors).toEqual([])
})

test('the bar shown while signed in as someone else', { tag: '@phone' }, async ({ page }) => {
  await impersonateGrower(page)
  const errors = watchErrors(page)
  await scan(page, '/')
  expect(errors).toEqual([])
})

test("a weather zone's table of all its weather, in a dialog", { tag: '@phone' }, async ({ page }) => {
  await signIn(page)
  const errors = watchErrors(page)
  await page.goto(await firstZonePath(page))
  await page.getByRole('button', { name: "all of this zone's weather" }).click()
  const dialog = page.getByRole('dialog', { name: "All of this zone's weather" })
  await expect(dialog.getByRole('table')).toBeVisible()
  const { violations } = await new AxeBuilder({ page }).include('[role="dialog"]').withTags(TAGS).analyze()
  expect(violations.map((violation) => `${violation.id}: ${violation.help}`)).toEqual([])
  // The table scrolls inside the dialog; the page doesn't scroll sideways at 320 px
  await page.setViewportSize({ width: 320, height: 640 })
  expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(0)
  expect(errors).toEqual([])
})

test("Setup's field dialog, with its shape (G.14)", { tag: '@phone' }, async ({ page }) => {
  await signIn(page)
  const errors = watchErrors(page)
  await page.goto('/setup')
  await page.getByRole('button', { name: `Edit ${DEMO.researchField}` }).click()
  const dialog = page.getByRole('dialog')
  await expect(dialog.getByLabel('Field area', { exact: true })).toBeVisible()
  const { violations } = await new AxeBuilder({ page }).include('[role="dialog"]').withTags(TAGS).analyze()
  expect(violations.map((violation) => `${violation.id}: ${violation.help}`)).toEqual([])
  // An open info tip (G.13), portalled outside the dialog
  await dialog.getByRole('button', { name: 'About Irrigation system' }).click()
  await expect(page.getByRole('tooltip')).toBeVisible()
  const tip = await new AxeBuilder({ page })
    .include('[role="dialog"]')
    .include('[role="tooltip"]')
    .withTags(TAGS)
    .analyze()
  expect(tip.violations.map((violation) => `${violation.id}: ${violation.help}`)).toEqual([])
  await page.keyboard.press('Escape')
  await expect(page.getByRole('tooltip')).toBeHidden()
  // Its prompt before dropping a change (G.13)
  await dialog.getByLabel('Field area', { exact: true }).fill('12.5')
  await page.keyboard.press('Escape')
  await expect(dialog.getByRole('heading', { name: 'Save your changes?' })).toBeVisible()
  const prompt = await new AxeBuilder({ page }).include('[role="dialog"]').withTags(TAGS).analyze()
  expect(prompt.violations.map((violation) => `${violation.id}: ${violation.help}`)).toEqual([])
  await dialog.getByRole('button', { name: 'Keep editing' }).click()
  // WCAG 1.4.10: the dialog fits 320 px with no sideways scroll
  await page.setViewportSize({ width: 320, height: 640 })
  expect(await dialog.evaluate((element) => element.scrollWidth - element.clientWidth)).toBeLessThanOrEqual(0)
  expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(0)
  expect(errors).toEqual([])
})

test(
  "Setup's planting dialog in sections, and a planting bar's menu (G.13 part 3)",
  { tag: '@phone' },
  async ({ page }) => {
    await signIn(page)
    const errors = watchErrors(page)
    await page.goto('/setup')
    const axe = async () => {
      const { violations } = await new AxeBuilder({ page })
        .include('[role="dialog"], [role="menu"]')
        .withTags(TAGS)
        .analyze()
      expect(violations.map((violation) => `${violation.id}: ${violation.help}`)).toEqual([])
    }
    // A new planting: only the crop (required, still empty) until one is chosen
    await page.getByRole('button', { name: `Add a planting to ${DEMO.firstField}` }).click()
    const dialog = page.getByRole('dialog')
    await expect(dialog.getByText('Choose a crop')).toHaveCount(2) // the option and the hint
    await axe()
    // Its sections, with Settings open
    await dialog.getByLabel('Crop', { exact: true }).selectOption({ label: 'Onion' })
    await dialog.locator('summary').click()
    await expect(dialog.getByRole('group', { name: 'Canopy curve' })).toBeVisible()
    await axe()
    await page.keyboard.press('Escape')
    await dialog.getByRole('button', { name: 'Discard' }).click()
    await expect(dialog).toBeHidden()
    // A bar's menu: view or edit
    await page
      .getByRole('list', { name: new RegExp(`^Plantings on ${literal(DEMO.researchField)}`) })
      .getByRole('button')
      .first()
      .click()
    await expect(page.getByRole('menu')).toBeVisible()
    await axe()
    expect(errors).toEqual([])
  },
)
