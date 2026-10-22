import { expect, test } from '@playwright/test'

import { firstFieldPath, GROWER_EMAIL, impersonateGrower } from './session'

// An admin signed in as a grower for support (PLAN.md Phase 8 B): the bar on every page, and back

test('an admin signs in as a grower, sees the bar on every page, and returns to admin', async ({ page }) => {
  await impersonateGrower(page)
  const bar = page.getByRole('status').filter({ hasText: 'for support' })
  await expect(bar).toContainText(`Signed in as Jane Grower (${GROWER_EMAIL}) for support`)
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible()
  await expect(page).toHaveTitle(new RegExp(`^As ${GROWER_EMAIL} · `))
  // Her nav has no admin pages
  await expect(page.getByRole('navigation', { name: 'Main' }).getByRole('link', { name: 'Users' })).toHaveCount(0)

  // The skip link is still the first stop, before the bar's button
  await page.goto('/')
  await page.keyboard.press('Tab')
  await expect(page.getByRole('link', { name: 'Skip to main content' })).toBeFocused()

  await page.goto(await firstFieldPath(page))
  await expect(bar).toBeVisible()
  await expect(page).toHaveTitle(new RegExp(`^As ${GROWER_EMAIL} · `))

  // On the map's full-height layout the bar takes its own height, so the page doesn't scroll
  await page.goto('/map')
  await expect(bar).toBeVisible()
  const overflow = await page.evaluate(() => document.documentElement.scrollHeight - window.innerHeight)
  expect(overflow).toBeLessThanOrEqual(0)

  // Her email and password can't be changed from here
  await page.goto('/settings')
  await expect(page.getByText("turned off while you're signed in as someone else")).toBeVisible()
  await expect(page.getByLabel('Current password')).toHaveCount(0)

  await page.getByRole('button', { name: 'Return to admin' }).click()
  await expect(page.getByRole('heading', { name: GROWER_EMAIL })).toBeVisible()
  await expect(bar).toHaveCount(0)
  await expect(page).not.toHaveTitle(/^As /)
})
