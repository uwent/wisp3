import { writeFileSync } from 'node:fs'

import AxeBuilder from '@axe-core/playwright'
import { expect, type Page, test } from '@playwright/test'

import { firstFieldPath, firstLinkPath, signIn } from './session'

// WCAG 2.1 A and AA checks (axe) on every page, in light (desktop) and dark (phone). Every page is
// scanned before the test fails, and A11Y_REPORT=path writes the violations found as JSON.

const TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa']

type Finding = { path: string; rule: string; impact: string | null | undefined; help: string; targets: string[] }

const findings: Finding[] = []

async function scan(page: Page, path: string) {
  await page.goto(path)
  await expect(page.locator('main h1').first()).toBeVisible()
  // Charts draw after the first frame
  await page.waitForTimeout(300)
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
      violations.map((violation) => `${violation.id} (${violation.nodes.length}): ${violation.help}`),
      `${path} has accessibility violations`,
    )
    .toEqual([])
}

test.afterAll(() => {
  const report = process.env.A11Y_REPORT
  if (report)
    writeFileSync(report.replace('.json', `-${test.info().project.name}.json`), JSON.stringify(findings, null, 2))
})

test('signed-out pages', async ({ page }) => {
  for (const path of [
    '/',
    '/about',
    '/account/sign_in',
    '/account/sign_up',
    '/account/password/new',
    '/account/confirmation/new',
  ]) {
    await scan(page, path)
  }
})

test('signed-in pages', async ({ page }) => {
  test.setTimeout(120_000)
  await signIn(page)
  const field = await firstFieldPath(page)
  const pivot = await firstLinkPath(page, field, 'a[href*="/pivots/"]')
  const fieldGroup = await firstLinkPath(page, '/field_groups', 'a[href*="/field_groups/"]')
  const user = await firstLinkPath(page, '/admin/users', 'a[href*="/admin/users/"]')

  for (const path of [
    '/',
    '/map',
    field,
    '/setup',
    '/setup/start',
    '/daily',
    pivot,
    `${pivot}/edit`,
    '/pivots/new',
    '/field_groups',
    fieldGroup,
    '/settings',
    '/alerts',
    '/operation',
    '/about',
    '/admin/weather',
    '/admin/users',
    user,
  ]) {
    await scan(page, path)
  }
})

test('every page reflows at 320 px wide and at 200% text', async ({ page }) => {
  test.skip(test.info().project.name !== 'desktop', 'one run covers both sizes')
  test.setTimeout(120_000)
  await signIn(page)
  const field = await firstFieldPath(page)
  const pivot = await firstLinkPath(page, field, 'a[href*="/pivots/"]')
  const paths = ['/', '/map', field, '/setup', '/setup/start', '/daily', pivot, '/field_groups', '/alerts', '/about']
  const overflow = () => page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)

  // WCAG 1.4.10: 320 CSS px wide with no sideways page scroll (grids and tables scroll inside themselves)
  await page.setViewportSize({ width: 320, height: 640 })
  for (const path of paths) {
    await page.goto(path)
    await expect(page.locator('main h1').first()).toBeVisible()
    expect.soft(await overflow(), `${path} scrolls sideways at 320 px`).toBeLessThanOrEqual(0)
  }
  // WCAG 1.4.4: text at 200%
  await page.setViewportSize({ width: 1280, height: 800 })
  for (const path of paths) {
    await page.goto(path)
    await page.addStyleTag({ content: 'html { font-size: 200% !important }' })
    expect.soft(await overflow(), `${path} scrolls sideways with 200% text`).toBeLessThanOrEqual(0)
  }
})
