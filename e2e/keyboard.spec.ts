import { firstPlantingPath, signIn } from './session'
import { expect, test } from './test'

// Keyboard use (WCAG 2.1.1, 2.4.1, 2.4.3): skipping the nav, grids as one tab stop, and focus moving
// into the map's pivot panel, the layers panel, dialogs and menus and back out again

test.beforeEach(async ({ page }) => {
  await signIn(page)
})

test('the first Tab offers a skip link to the main content', async ({ page }) => {
  await page.goto('/setup')
  // Once the page is drawn: a Tab during loading lands wherever focus is then
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible()
  await page.keyboard.press('Tab')
  const skip = page.getByRole('link', { name: 'Skip to main content' })
  await expect(skip).toBeFocused()
  await expect(skip).toBeVisible()
  await page.keyboard.press('Enter')
  await page.keyboard.press('Tab')
  await expect(page.getByLabel('Season')).toBeFocused()
})

test('a grid is one tab stop: arrows move inside it, Tab moves past it', async ({ page }) => {
  await page.goto(await firstPlantingPath(page))
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
  // First the pivot's name, which links to its page
  await expect(panel.getByRole('heading').getByRole('link')).toBeFocused()
  await page.keyboard.press('Escape')
  await expect(panel).toBeHidden()
  await expect(show).toBeFocused()
})

test("the map list's cards select from the keyboard, and Escape clears the selection (G.14)", async ({ page }) => {
  await page.goto('/map')
  const farm = page.getByRole('button', { name: /^Zoom the map to the farm / }).first()
  await farm.focus()
  await page.keyboard.press('Enter')
  await expect(farm).toHaveAttribute('aria-pressed', 'true')
  await expect(farm).toBeFocused() // no panel to move to
  await page.keyboard.press('Escape')
  await expect(farm).toHaveAttribute('aria-pressed', 'false')
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

  // With a change, Escape moves focus into the prompt (G.13); Keep editing returns it to the change
  await page.keyboard.press('Enter')
  const name = dialog.getByRole('textbox').first()
  await name.focus()
  await page.keyboard.type(' 2')
  await page.keyboard.press('Escape')
  await expect(dialog.getByRole('heading', { name: 'Save your changes?' })).toBeFocused()
  await page.keyboard.press('Tab')
  await expect(dialog.getByRole('button', { name: 'Keep editing' })).toBeFocused()
  await page.keyboard.press('Enter')
  await expect(name).toBeFocused()
  await page.keyboard.press('Escape')
  await dialog.getByRole('button', { name: 'Discard' }).focus()
  await page.keyboard.press('Enter')
  await expect(dialog).toBeHidden()

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

test("a planting bar's menu works from the keyboard (G.13 part 3)", async ({ page }) => {
  await page.goto('/setup')
  const bar = page.getByRole('list', { name: /^Plantings on Arlington 525/ }).getByRole('button', { name: /^Soybean/ })
  await bar.focus()
  await page.keyboard.press('Enter')
  const menu = page.getByRole('menu')
  await expect(menu).toBeVisible()
  // From the keyboard it opens under the bar's start
  const [barBox, menuBox] = [(await bar.boundingBox())!, (await menu.boundingBox())!]
  expect(Math.abs(menuBox.x - barBox.x)).toBeLessThan(4)
  await page.keyboard.press('Escape')
  await expect(menu).toBeHidden()
  await expect(bar).toBeFocused()
  await page.keyboard.press('Enter')
  await expect(menu).toBeVisible()
  await page.keyboard.press('End')
  await expect(page.getByRole('menuitem', { name: 'Edit planting' })).toBeFocused()
  await page.keyboard.press('Enter')
  await expect(page.getByRole('dialog', { name: /^Edit Soybean on Arlington 525/ })).toBeVisible()
})

test('a glossary term opens from the keyboard, and describes itself by its definition', async ({ page }) => {
  await page.goto(await firstPlantingPath(page))
  const term = page.getByRole('button', { name: 'allowable depletion' }).first()
  await term.focus()
  await page.keyboard.press('Enter')
  await expect(term).toHaveAccessibleDescription(/allowable depletion/i)
  await page.keyboard.press('Escape')
  await expect(page.getByRole('tooltip')).toBeHidden()
  await expect(term).toBeFocused()
})

test("a form's info tip opens from the keyboard, and Escape closes it before the dialog's prompt (G.13)", async ({
  page,
}) => {
  await page.goto('/setup')
  await page.getByRole('button', { name: 'Edit Arlington 525' }).click()
  const dialog = page.getByRole('dialog')
  await dialog.getByRole('textbox', { name: 'Field area' }).fill('12.5')
  // The (i) follows the Name box in tab order, outside the select's label
  await dialog.getByRole('textbox', { name: 'Name' }).focus()
  await page.keyboard.press('Tab')
  const info = dialog.getByRole('button', { name: 'About Irrigation system' })
  await expect(info).toBeFocused()
  await page.keyboard.press('Enter')
  await expect(page.getByRole('tooltip')).toBeVisible()
  await expect(info).toHaveAccessibleDescription(/waters this field/)
  // Escape closes the tip only: the dialog stays, without asking about the change
  await page.keyboard.press('Escape')
  await expect(page.getByRole('tooltip')).toBeHidden()
  await expect(info).toBeFocused()
  await expect(dialog.getByRole('heading', { name: 'Save your changes?' })).toBeHidden()
  // The next Escape is the dialog's
  await page.keyboard.press('Escape')
  await expect(dialog.getByRole('heading', { name: 'Save your changes?' })).toBeVisible()
  await dialog.getByRole('button', { name: 'Discard' }).click()
  await expect(dialog).toBeHidden()
})
