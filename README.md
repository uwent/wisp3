# WISP 3

The Wisconsin Irrigation Scheduling Program (WISP) helps growers schedule irrigation by tracking the daily root-zone water balance of each field (the "checkbook" method), now driven by Open-Meteo weather forecasts. It was developed by the Departments of Biological Systems Engineering and Soil Science at the University of Wisconsin–Madison.

WISP 3 is a rewrite of the [original WISP](https://github.com/uwent/wisp). See [PLAN.md](PLAN.md) for the design and the phased rollout. The app's own documentation, for growers, is its About page (`/about`).

## What it does

- **Water balance** for each field, recalculated from its plantings, entries and the weather whenever it's viewed, and run through the 16-day forecast and its ensemble to say when to irrigate and how much.
- **Dashboard** of every field's status and outlook, and a **map** of the pivots colored by status, with a field list and optional public layers (radar, recent and forecast rain, the Drought Monitor) whose values show under the pointer.
- **Daily entry** of rain, irrigation and soil moisture for the whole operation, field groups that share a gauge, and each field's page with its chart, editable days and weather.
- **Setup** of farms, pivots (placed on a map), fields and crops, with a soil type suggested from the USDA soil survey under the pivot; crop canopy curves and soil types are reference data with their sources (`db/reference/`).
- **Daily email** of what needs irrigating and which readings are due.

## Stack

- Rails 8.1 (Ruby 4.0), PostgreSQL, Solid Queue and Solid Cache
- Svelte 5 + TypeScript pages served through Inertia.js, built by Vite, styled with Tailwind CSS v4
- Devise for accounts, with one-time sign-in links
- RSpec, Vitest, Standard

## Development setup

Requirements: Ruby 4.0.5 (rbenv), Node 24, PostgreSQL 16+.

```bash
bin/setup          # installs gems and pnpm packages, prepares the database, starts the app
bin/dev            # Rails on http://localhost:3000 plus the Vite dev server
```

The database connects to `localhost` as `postgres`/`password` by default; override with `DB_HOST`, `DB_USER`, `DB_PWD`. Mail sent in development opens at http://localhost:3000/letter_opener.

## Common commands

```bash
bin/ci                            # everything CI runs: lint, type checks, frontend and Rails tests
bundle exec rspec                 # Rails tests
pnpm test                         # frontend component tests (Vitest)
pnpm check                      # svelte-check + TypeScript
bundle exec standardrb            # Ruby lint
bin/rails typelizer:generate      # regenerate TS types (app/frontend/types/serializers) and route helpers (app/frontend/routes)
```

Generated types and route helpers are committed; CI fails if they are out of date.

## Deployment

Capistrano deploys to staging (dev.wisp.cals.wisc.edu) and, from the 2027 season, a new production server. See [docs/deployment.md](docs/deployment.md).
