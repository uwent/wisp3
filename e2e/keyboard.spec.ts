import { expect, test } from '@playwright/test'

import { firstFieldPath, signIn } from './session'

// Keyboard use (WCAG 2.1.1, 2.4.1, 2.4.3): skipping the nav, grids as one tab stop, and focus moving
// into the map's pivot panel, the layers panel, dialogs and menus and back out again

test.beforeEach(async ({ page }) => {
  await signIn(page)
})

test('the first Tab offers a skip link to the main content', async ({ page }) => {
  await page.goto('/setup')
  await page.keyboard.press('Tab')
  const skip = page.getByRole('link', { name: 'Skip to main content' })
  await expect(skip).toBeFocused()
  await expect(skip).toBeVisible()
  await page.keyboard.press('Enter')
  await page.keyboard.press('Tab')
  await expect(page.getByLabel('Season')).toBeFocused()
})

test('a grid is one tab stop: arrows move inside it, Tab moves past it', async ({ page }) => {
  await page.goto(await firstFieldPath(page))
  const cells = page.locator('button[data-grid="days"]')
  await cells.first().waitFor()
  expect(await cells.count()).toBeGreaterThan(10)
  await expect(page.locator('button[data-grid="days"][tabindex="0"]')).toHaveCount(1)

  const first = page.locator('button[data-grid="days"][data-row="0"][data-col="0"]')
  await first.focus()
  await page.keyboard.press('ArrowDown')
  const below = page.locator('button[data-grid="days"][data-row="1"][data-col="0"]')
  await expect(below).toBeFocused()
  await expect(below).toHaveAttribute('tabindex', '0')

  // Tab while editing saves and moves along the row; Escape there leaves the next cell unchanged
  await page.keyboard.press('Enter')
  await expect(page.getByRole('textbox', { name: /^Rain, / })).toBeFocused()
  await page.keyboard.press('Tab')
  await expect(page.locator('button[data-grid="days"][data-row="1"][data-col="1"]')).toBeFocused()

  await page.keyboard.press('Tab')
  expect(await page.evaluate(() => document.activeElement?.getAttribute('data-grid'))).not.toBe('days')
})

test('selecting a pivot from the keyboard moves to its panel, and Escape comes back', async ({ page }) => {
  await page.goto('/map')
  const show = page.getByRole('button', { name: /on the map$/ }).first()
  await show.focus()
  await page.keyboard.press('Enter')
  const panel = page.locator('[data-pivot-panel]')
  await expect(panel).toBeFocused()
  await page.keyboard.press('Tab')
  await expect(page.getByRole('link', { name: 'View pivot' })).toBeFocused()
  await page.keyboard.press('Escape')
  await expect(panel).toBeHidden()
  await expect(show).toBeFocused()
})

test('the map layers panel opens from the keyboard and Escape closes it', async ({ page }) => {
  await page.goto('/map')
  const layers = page.getByRole('button', { name: 'Layers' })
  await layers.focus()
  await page.keyboard.press('Enter')
  await page.keyboard.press('Tab')
  await expect(page.getByRole('group', { name: 'Map layers' }).locator(':focus')).toHaveCount(1)
  await page.keyboard.press('Escape')
  await expect(page.getByRole('group', { name: 'Map layers' })).toBeHidden()
  await expect(layers).toBeFocused()
})

test('setup dialogs and the account menu work from the keyboard', async ({ page }) => {
  await page.goto('/setup')
  const edit = page.getByRole('button', { name: /^Edit / }).first()
  await edit.focus()
  await page.keyboard.press('Enter')
  const dialog = page.getByRole('dialog')
  await expect(dialog).toBeVisible()
  await expect(dialog.locator(':focus')).toHaveCount(1)
  await page.keyboard.press('Escape')
  await expect(dialog).toBeHidden()
  await expect(edit).toBeFocused()

  const account = page.getByRole('button', { name: /account menu$/ })
  await account.focus()
  await page.keyboard.press('Enter')
  await expect(page.getByRole('menu')).toBeVisible()
  await page.keyboard.press('ArrowDown')
  await expect(page.getByRole('menuitem').locator('visible=true').and(page.locator(':focus'))).toHaveCount(1)
  await page.keyboard.press('Escape')
  await expect(page.getByRole('menu')).toBeHidden()
  await expect(account).toBeFocused()
})

test('a glossary term opens from the keyboard, and describes itself by its definition', async ({ page }) => {
  await page.goto(await firstFieldPath(page))
  const term = page.getByRole('button', { name: 'allowable depletion' }).first()
  await term.focus()
  await page.keyboard.press('Enter')
  await expect(term).toHaveAccessibleDescription(/allowable depletion/i)
  await page.keyboard.press('Escape')
  await expect(page.getByRole('tooltip')).toBeHidden()
  await expect(term).toBeFocused()
})
