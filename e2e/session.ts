import { expect, type Page } from '@playwright/test'

// The demo account seeded by e2e/seed.rb, and getting around it

export const EMAIL = 'e2e@example.com'
export const PASSWORD = 'e2e-password-1'
// A grower in the demo farms, not an admin, for signing in as someone else
export const GROWER_EMAIL = 'jane@example.com'

export async function signIn(page: Page) {
  await page.goto('/account/sign_in')
  await page.getByLabel('Email').fill(EMAIL)
  await page.getByLabel('Password', { exact: true }).fill(PASSWORD)
  await page.getByRole('button', { name: 'Sign in' }).click()
  await expect(page.getByRole('navigation', { name: 'Main' })).toBeVisible()

  // The demo farms are a second group; the user's own (empty) group is the default. The switcher
  // is its own menu on wider screens, and part of the account menu on phones.
  if ((await page.getByRole('heading', { name: 'Dashboard' }).locator('..').textContent())?.includes('Demo farms'))
    return
  const switcher = page.getByRole('button', { name: 'Switch operation' })
  await ((await switcher.isVisible()) ? switcher : page.getByRole('button', { name: 'Account menu' })).click()
  await page.getByRole('menuitem', { name: 'Demo farms' }).click()
  await expect(page.getByRole('heading', { name: 'Dashboard' }).locator('..')).toContainText('Demo farms')
}

export async function firstFieldPath(page: Page): Promise<string> {
  await page.goto('/')
  const href = await page.locator('main ul li a').first().getAttribute('href')
  return new URL(href!, page.url()).pathname
}

/** The path of the first link in main matching a selector, on the page at `from` */
export async function firstLinkPath(page: Page, from: string, selector: string): Promise<string> {
  await page.goto(from)
  return new URL((await page.locator(`main ${selector}`).first().getAttribute('href'))!, page.url()).pathname
}

/** Signs in as the admin, then as the demo grower from her admin page (PLAN.md Phase 8 B) */
export async function impersonateGrower(page: Page) {
  await signIn(page)
  await page.goto('/admin/users')
  await page.getByRole('link', { name: GROWER_EMAIL }).first().click()
  await expect(page.getByRole('heading', { name: GROWER_EMAIL })).toBeVisible()
  page.once('dialog', (dialog) => dialog.accept())
  await page.getByRole('button', { name: 'Sign in as this user' }).click()
  await expect(page.getByRole('status').filter({ hasText: 'for support' })).toBeVisible()
}

/** Uncaught errors and console errors, except resources that failed to load (map tiles in CI) */
export function watchErrors(page: Page): string[] {
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(`${page.url()}: ${error.message}`))
  page.on('console', (message) => {
    if (message.type() === 'error' && !message.text().startsWith('Failed to load resource')) {
      errors.push(`${page.url()}: ${message.text()}`)
    }
  })
  return errors
}

/** Every signed-in page, with the demo account's first field, pivot, field group and user */
export async function signedInPages(page: Page): Promise<string[]> {
  const field = await firstFieldPath(page)
  const pivot = await firstLinkPath(page, field, 'a[href*="/pivots/"]')
  const fieldGroup = await firstLinkPath(page, '/field_groups', 'a[href*="/field_groups/"]')
  const user = await firstLinkPath(page, '/admin/users', 'a[href*="/admin/users/"]')
  return [
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
  ]
}
