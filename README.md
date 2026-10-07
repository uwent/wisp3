# WISP 3

The Wisconsin Irrigation Scheduling Program (WISP) helps growers schedule irrigation by tracking the daily root-zone water balance of each field (the "checkbook" method), now driven by Open-Meteo weather forecasts. It was developed by the Departments of Biological Systems Engineering and Soil Science at the University of Wisconsin–Madison.

WISP 3 is a rewrite of the [original WISP](https://github.com/uwent/wisp). See [PLAN.md](PLAN.md) for the design and the phased rollout.

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
