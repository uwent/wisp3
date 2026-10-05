import { expect, test } from '@playwright/test'

// Signed-out visitors: the landing page and the About page, without errors or sideways scrolling

test('the landing page introduces WISP and leads to the About page and sign-up', async ({ page }) => {
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error.message))

  await page.goto('/')
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Irrigate when your fields need it, not before')
  await expect(page.getByRole('link', { name: 'Create a free account' })).toBeVisible()
  if (process.env.SHOT_DIR) await page.screenshot({ path: `${process.env.SHOT_DIR}/home-${test.info().project.name}.png`, fullPage: true })

  await page.getByRole('link', { name: /Step 1/ }).click()
  await expect(page).toHaveURL(/\/about#getting-started$/)
  await expect(page.getByRole('heading', { name: 'Getting started' })).toBeInViewport()
  await expect(page.getByRole('row', { name: /Field Corn/ })).toContainText('from a growth curve or readings')
  if (process.env.SHOT_DIR) await page.screenshot({ path: `${process.env.SHOT_DIR}/about-${test.info().project.name}.png`, fullPage: true })

  for (const path of ['/', '/about']) {
    await page.goto(path)
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)
    expect(overflow, `${path} scrolls sideways`).toBeLessThanOrEqual(0)
  }

  await page.getByRole('link', { name: 'Sign in' }).first().click()
  await expect(page).toHaveURL(/\/account\/sign_in$/)
  expect(errors).toEqual([])
})
