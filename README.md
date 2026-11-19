# WISP 3

The Wisconsin Irrigation Scheduling Program (WISP) helps growers decide when to irrigate and how much. For each crop in each field it keeps a daily water balance of the root zone (the "checkbook" method): rain and irrigation in, the crop's water use and drainage out. Run forward with the weather forecast, it shows which fields will need water in the next few days, and how much would refill them.

WISP grew out of UW Extension publication A3600's checkbook method of irrigation scheduling and was developed as a web app (WISP 2012) by the Departments of Soil Science and Biological Systems Engineering at the University of Wisconsin–Madison. It is maintained by the [Vegetable Entomology Lab](https://vegento.russell.wisc.edu/) in the UW–Madison Department of Entomology. It is built for Wisconsin and the upper Midwest, and is free to use.

WISP 3 is a rewrite of the [original WISP](https://github.com/uwent/wisp), for the 2027 season. Growers set up their operations fresh; the legacy app stays readable at https://old.wisp.cals.wisc.edu until December 31, 2027.

- **Production:** https://wisp.cals.wisc.edu
- **Staging:** https://dev.wisp.cals.wisc.edu
- **An example farm**, read-only and without an account, at `/example`
- **Documentation for growers:** the app's About page (`/about`)
- **Contact:** agweather@cals.wisc.edu

## How it works

- **The water balance.** A soil's root zone holds the water between field capacity and the wilting point; growers irrigate before the crop has used a set share of it (the management allowable depletion, MAD, 50% by default). Each day WISP subtracts the crop's water use and adds rain and irrigation, and water beyond field capacity counts as deep drainage. The balance is recalculated from its inputs whenever it's viewed, never stored.
- **Crop water use** is reference evapotranspiration (ET) from the weather, scaled by the crop's canopy (percent cover with the A3600 regressions, or leaf area index for field corn) up to the crop's FAO-56 coefficient at full cover, adjusted for each day's wind and humidity. Every crop has a typical canopy curve with its sources, which the grower's cover readings correct.
- **Weather** comes from [Open-Meteo](https://open-meteo.com/) for each irrigation system's grid cell: the past season, a 16-day forecast and a 31-member ensemble. WISP corrects Open-Meteo's solar radiation and humidity against Wisconsin ground stations and computes reference ET itself (FAO-56), using tables from AgWeather v2. There is no dependency on AgWeather.
- **The outlook.** The balance runs on through the forecast and every ensemble member, so each planting gets a status (Full, OK, Caution, Irrigate), an "Irrigate by" date with how much would refill the root zone, and the share of forecast scenarios that agree.
- **Ground truth.** Growers enter what only they know: rain gauge readings, irrigation applied, soil moisture readings now and then, and canopy cover. Each overrides the model for its day.

## What growers get

- **Setup:** farms, irrigation systems (center pivots and linears placed and sized on a map; travelers, solid set, drip and plain locations as points), fields with a soil type suggested from the USDA soil survey, optional field outlines drawn or imported from shapefile, GeoJSON or KML, and plantings: one per field, or several side by side on parts of a field, each with its own balance. A guided first-run setup, and "copy last season".
- **Dashboard and map:** every field's status and outlook by farm and system; a map of the operation with status badges per planting and public layers (radar, recent and forecast rain, the Drought Monitor) whose values show under the pointer.
- **Daily entry:** rain, irrigation, soil moisture and cover for the whole operation on one page, with irrigation groups that share a gauge and irrigation entered once for a system.
- **A page per planting:** its chart through the forecast, every day's values (editable), planned irrigation as a what-if, the season's totals, a CSV export, and its page as it was on any earlier day of the season.
- **Weather:** a tab per weather zone with the week ahead and the year's charts (temperature, rain, ET, degree days, sunshine, humidity, wind, soil), each downloadable.
- **A morning email** listing which fields need water and which readings are due, with each zone's weather.
- **Operations shared** by owners and members, metric or US units, and accessibility to WCAG 2.1 AA.

## Stack

- Rails 8.1 (Ruby 4.0), PostgreSQL, Solid Queue and Solid Cache; the water balance in plain-Ruby services
- Svelte 5 + TypeScript pages served through Inertia.js, built by Vite, styled with Tailwind CSS v4; ECharts for charts, MapLibre for maps
- Devise for accounts, with passwords and one-time sign-in links and codes
- RSpec, Vitest, Playwright (with axe accessibility scans), Standard, ESLint and Prettier

## Development

[DEVELOPMENT.md](DEVELOPMENT.md) walks through setting up a machine (Ruby, Node, PostgreSQL), the day-to-day commands and tests, demo data, credentials, and deployment. In short, once the prerequisites are installed:

```bash
bin/setup          # installs gems and pnpm packages, prepares the database, starts the app
bin/rails demo:seed  # a demo account with farms, fields and a season of entries
bin/dev            # Rails on http://localhost:3000 plus the Vite dev server
bin/ci             # lint, type checks, frontend and Rails tests (a few minutes)
bin/e2e            # browser tests (about 3 minutes; CI runs them as a separate job)
```

Where to read next:

| Document | What's in it |
|---|---|
| [DEVELOPMENT.md](DEVELOPMENT.md) | Setting up, commands, tests, secrets, troubleshooting |
| [CLAUDE.md](CLAUDE.md) | Conventions for working in the code: tenancy, units, the engine, forms, gotchas (read by Claude Code, and useful to people) |
| [docs/architecture.md](docs/architecture.md) | How each area works and where its code is |
| [PLAN.md](PLAN.md) | The design, decisions and phased plan; its handoff at the top says where work stands |
| [docs/deployment.md](docs/deployment.md) | Staging (Capistrano) and production (Docker on AWS) |
| [docs/](docs/) | The accessibility audit, and the research behind the canopy curves and weather corrections |

## Deployment

Staging (`dev.wisp.cals.wisc.edu`) deploys with Capistrano; production runs on AWS (EC2 and RDS) with Docker Compose, its image built on the server from the pushed commit (`bin/production deploy`). See [docs/deployment.md](docs/deployment.md).

## License

Copyright (C) 2026 Board of Regents of the University of Wisconsin System.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See [LICENSE](LICENSE) for the full terms. If you run a modified version for others over a network, the license requires you to offer them its source.

Weather data from [Open-Meteo](https://open-meteo.com/) is licensed CC BY 4.0.
