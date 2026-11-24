import { defineConfig, devices } from '@playwright/test'

import { NOW } from './e2e/clock'

// Browser smoke tests; run with bin/e2e, which prepares the wisp3_e2e database and seeds it
const port = 3200

export default defineConfig({
  testDir: 'e2e',
  // Files side by side, each file's tests in turn on one worker: the tests share one database, and the
  // files that change seed rows (smoke, keyboard) don't read what the others change
  fullyParallel: false,
  workers: 2,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: `http://localhost:${port}`,
    trace: 'retain-on-failure',
  },
  projects: [
    // Signs in once; the others reuse its session (signIn in session.ts)
    { name: 'setup', testMatch: /auth\.setup\.ts/ },
    { name: 'desktop', use: { ...devices['Desktop Chrome'] }, dependencies: ['setup'] },
    // Only the tests tagged @phone: dark mode's accessibility scans, and where touch or the small
    // screen's layout matters
    { name: 'phone', use: { ...devices['Pixel 7'], colorScheme: 'dark' }, grep: /@phone/, dependencies: ['setup'] },
  ],
  webServer: {
    command: `bin/rails server -p ${port}`,
    url: `http://localhost:${port}/up`,
    env: { RAILS_ENV: 'test', E2E: '1', E2E_NOW: NOW },
    reuseExistingServer: false,
    timeout: 120_000,
  },
})
