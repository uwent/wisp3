import { defineConfig, devices } from '@playwright/test'

// Browser smoke tests; run with bin/e2e, which prepares the wisp3_e2e database and seeds it
const port = 3200

export default defineConfig({
  testDir: 'e2e',
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: `http://localhost:${port}`,
    trace: 'retain-on-failure',
  },
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'] } },
    { name: 'phone', use: { ...devices['Pixel 7'], colorScheme: 'dark' } },
  ],
  webServer: {
    command: `bin/rails server -p ${port}`,
    url: `http://localhost:${port}/up`,
    env: { RAILS_ENV: 'test', E2E: '1' },
    reuseExistingServer: false,
    timeout: 120_000,
  },
})
