import clock from './clock.json' with { type: 'json' }

// The browser tests' day. bin/e2e gives it to the seed and the server as E2E_NOW
// (config/initializers/e2e_clock.rb), whose clocks start there and run on, so the demo's season,
// its weather and "today" are the same whenever the tests run. The browser keeps the real time:
// pages take today from the server. E2E_NOW=… bin/e2e tries another day.
export const NOW: string = process.env.E2E_NOW || clock.now

/** The demo's season: the tests' dates are days in it */
export const YEAR = Number(NOW.slice(0, 4))
