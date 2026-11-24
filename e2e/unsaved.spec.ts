import { YEAR } from './clock'
import { firstPlantingPath, signIn } from './session'
import { expect, test } from './test'

// What's typed is never dropped silently: the browser's Back asks first, and a save that can't
// reach WISP, or finds its session ended, says so and leaves the page as it was. Nothing here is
// saved, so these read and write no rows the other files use.

test.beforeEach(async ({ page }) => {
  await signIn(page)
})

const midSeason = `/daily?date=${YEAR}-07-15`

test("the browser's Back asks before leaving unsaved entries, and staying keeps them", async ({ page }) => {
  await page.goto(midSeason)
  // Reached by a link, so Back stays in the app (Inertia shows the page from the browser's history)
  await page.getByRole('link', { name: 'Week', exact: true }).click()
  await expect(page).toHaveURL(/\/daily\/week\?date=/)
  const cell = page.locator('main table input:not([disabled])').first()
  await cell.fill('0.7')

  let asked = ''
  page.once('dialog', (dialog) => {
    asked = dialog.message()
    void dialog.dismiss()
  })
  await page.goBack()
  await expect.poll(() => asked).toContain('unsaved changes')
  await expect(page).toHaveURL(/\/daily\/week\?date=/)
  await expect(page.getByRole('link', { name: 'Day', exact: true })).toBeVisible()
  await expect(cell).toHaveValue('0.7')

  // Asked again, and leaving goes back
  page.once('dialog', (dialog) => void dialog.accept())
  await page.goBack()
  await expect(page).toHaveURL(/\/daily\?date=/)
  await expect(page.getByLabel('Date', { exact: true })).toBeVisible()
})

test('Back with nothing typed goes back without asking', async ({ page }) => {
  await page.goto(midSeason)
  await page.getByRole('link', { name: 'Week', exact: true }).click()
  await expect(page).toHaveURL(/\/daily\/week\?date=/)
  let asked = false
  page.once('dialog', (dialog) => {
    asked = true
    void dialog.accept()
  })
  await page.goBack()
  await expect(page).toHaveURL(/\/daily\?date=/)
  expect(asked).toBe(false)
})

test("a grid cell's save with no connection says so and keeps what was typed", async ({ page, context }) => {
  await page.goto(await firstPlantingPath(page))
  const first = page.locator('button[data-grid="days"][data-row="0"][data-col="0"]')
  await first.focus()
  await page.keyboard.press('Enter')
  const input = page.getByRole('textbox', { name: /^Rain, / })
  await input.fill('0.33')

  await context.setOffline(true)
  await page.keyboard.press('Enter')
  await expect(page.getByText("Couldn't reach WISP, so this wasn't saved.")).toBeVisible()
  await expect(input).toBeEnabled()
  await expect(input).toHaveValue('0.33')

  await context.setOffline(false)
  await page.keyboard.press('Escape')
})

test(
  'a form saved with no connection says so and keeps what was typed',
  { tag: '@phone' },
  async ({ page, context }) => {
    await page.goto(midSeason)
    const rain = page.getByLabel(/^Rain on /).first()
    await rain.fill('0.3')
    await context.setOffline(true)
    await page.getByRole('button', { name: /^Save / }).click()
    await expect(page.getByRole('alert').filter({ hasText: "Couldn't reach WISP" })).toBeVisible()
    await expect(rain).toHaveValue('0.30')
    await expect(page.getByText('You have unsaved changes')).toBeVisible()
    await context.setOffline(false)
  },
)

test('a save after the session has ended says so and keeps what was typed', async ({ page, context }) => {
  await page.goto(midSeason)
  const rain = page.getByLabel(/^Rain on /).first()
  await rain.fill('0.3')
  await context.clearCookies()
  await page.getByRole('button', { name: /^Save / }).click()
  await expect(
    page.getByRole('alert').filter({ hasText: "You've been signed out, so that wasn't saved" }),
  ).toBeVisible()
  await expect(page).toHaveURL(/\/daily\?date=/)
  await expect(rain).toHaveValue('0.30')
})
