import { test as setup } from './test'
import { AUTH_STATE, signInWithForm } from './session'

// Signs in once through the form, with the demo farms chosen, and keeps the session for every test
// (signIn adds its cookie): signing in through the form for each test cost about a second and a half
setup('sign in', async ({ page }) => {
  await signInWithForm(page)
  await page.context().storageState({ path: AUTH_STATE })
})
