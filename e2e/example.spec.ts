import { watchErrors } from './session'
import { expect, test } from './test'

// The public example farm (ExampleMode), signed out: the landing page's link, its bar,
// its pages read-only, and leaving it

test('anyone can look around the example farm, read-only, as of July 20', { tag: '@phone' }, async ({ page }) => {
  const errors = watchErrors(page)
  await page.goto('/')
  await page.getByRole('link', { name: 'See an example farm' }).click()
  const bar = page.getByRole('status').filter({ hasText: "You're viewing an example farm" })
  await expect(bar).toContainText(/as of Jul 20, \d{4}\. Create an account to set up your own\./)
  await expect(page.getByRole('heading', { name: 'Dashboard', level: 1 })).toBeVisible()
  // Its pages only, nothing to edit
  const nav = page.getByRole('navigation', { name: 'Main' })
  await expect(nav.getByRole('link')).toHaveText(['Dashboard', 'Map', 'Weather', 'About'])
  await expect(page.getByRole('link', { name: /^Edit / })).toHaveCount(0)

  // A planting: as of the day, with no other day to pick and no editing
  await page.locator('main a[href*="/plantings/"]').first().click()
  await expect(page).toHaveURL(/\/plantings\/\d+$/)
  await expect(bar).toBeVisible()
  await expect(page.getByRole('link', { name: 'Edit in setup' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'View this field on an earlier date' })).toHaveCount(0)

  // Setup isn't there; going to it comes back
  await page.goto('/setup')
  await expect(
    page.getByText('The example farm can only be viewed. Create an account to set up your own.'),
  ).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Dashboard', level: 1 })).toBeVisible()

  // Leaving it is the landing page again
  await bar.getByRole('button', { name: 'Leave the example' }).click()
  await expect(page.getByRole('link', { name: 'See an example farm' })).toBeVisible()
  await expect(bar).toBeHidden()
  expect(errors).toEqual([])
})
