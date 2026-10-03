# Handoff: WISP 3, end of Phase 4 (2026-10-03)

Read [PLAN.md](PLAN.md) (design, decisions D1–D11, legacy bug audit §9, phases §14, open questions §15) and [CLAUDE.md](CLAUDE.md) (conventions) first. Ben's own action items are in [TODO.md](TODO.md).

## Where things stand

- **Repo:** https://github.com/uwent/wisp3 (public), branch `main`. `bin/ci` runs the same checks as GitHub Actions. Ben pushes; check `git status` / `git log origin/main..` for unpushed commits.
- **Phase 0 (legacy `../wisp`):** done and deployed; precipitation backfill run.
- **Phase 1 (foundation):** done. Staging live at https://dev.wisp.cals.wisc.edu (Puma on `127.0.0.1:3100`, nginx `sites-available/wisp3`, systemd user units `wisp3-web` / `wisp3-jobs`). Redeploy: `bundle exec cap staging deploy` from pushed `main`.
- **Phase 2 (domain + engine):** done. Golden tests against 30 legacy production fields passed, then were retired with the legacy data; `spec/support/legacy_engine.rb` and its synthetic spec remain as the record of each fix (C2, C3, C4, C7, C8, C19).
- **Phase 3 (weather):** done, and deployed to staging with the API key (TODO.md).
- **Phase 4 (core UI):** done locally and verified in a headless browser; **uncommitted** at the end of this session, and not yet on staging. See the summary below.
- **Next: Phase 5, forecast projection** (PLAN.md §14): run the balance through the 16-day forecast, then the ensemble spike. The field chart (`lib/charts/fieldChart.ts`) and dashboard cards are where the projection shows; `PlantingStatus` is the place to add it on the server. Also still open from Phase 4: Playwright smoke tests in CI.

## Phase 4 summary (core UI)

- Pages (`app/frontend/pages`): `Dashboard/Show` (field cards), `Setup/Show` (farms → pivots → fields → crops, season picker, rainfall setting, "copy last season"), `Setup/Start` (guided first run), `Pivots/Form` (map picker), `Pivots/Show` (pivot irrigation log), `Fields/Show` (summary, chart, editable daily grid, weather panels, CSV), `DailyEntries/Show` (one date, whole operation), `FieldGroups/Index|Show`. Nav: Dashboard, Daily entry, Setup.
- Controllers: one per resource, all scoped through `Current.group`; `spec/requests/tenant_isolation_spec.rb` covers every new route. `FieldDaysController` and `FieldGroupDaysController` save one day; `DailyEntriesController` saves a whole date in one transaction (errors keyed `pivots.<id>.<attr>` / `fields.<id>.<attr>`); `QuickSetupsController` errors are keyed by input path (`fields.1.area_acres`).
- Services: `PlantingStatus` (a planting's season so far, status, last rain and irrigation, totals with entered vs modeled rain), `WeatherPanel`, `QuickSetup`, `SeasonCopy`, `PlantingCsv`.
- Frontend library: `lib/units.ts`, `lib/dates.ts`, `lib/geo.ts` (pivot circles and arcs), `lib/save.ts`, `lib/charts/*`, components `EditableCell`, `NumberField`, `SelectField`, `Dialog`, `PivotMap`, `Sparkline`, `StatusBadge`, `FieldPicker`; `lib/setup/FieldForm|PlantingForm`. Conventions are in CLAUDE.md.
- New dependencies: `echarts`, `maplibre-gl` (npm), `csv` (gem; no longer a default gem in Ruby 4).
- Choices worth knowing:
  - CSV export is always in inches, whatever the user's units (conversion stays in the frontend, CLAUDE.md).
  - Any member of a group can change its name and rainfall setting (membership admin isn't checked yet).
  - The field chart opens on the last 30 days; there's no forecast region until Phase 5.
  - Light/dark: the system setting, unless the toggle in the red UW bar picked the other one (`lib/theme.ts`, `data-theme` on `<html>`, remembered per browser in localStorage; an inline script in `application.html.erb` applies it before paint). Dark token values are listed twice in `application.css` (system and explicit).
  - The pivot map's place search calls OpenStreetMap's Nominatim from the browser, only on Enter/Go (its usage policy forbids search-as-you-type), biased to the current view. If usage grows, proxy it or switch providers.
  - `confirmUnsavedChanges` (`lib/unsaved.svelte.ts`) guards the pivot form and guided setup; the guided setup allows a pivot with no fields after a confirm.
  - `spec/rails_helper.rb` now clears `OPEN_METEO_API_KEY`, so specs don't depend on a developer's `.env` (the admin weather spec failed once the key was in `.env`).

## Phase 3 summary (weather)

- `app/services/weather/`: `Grid` (ECMWF O1280 cells, ported from Ben's R client `tmp/api_openmeteo.R`), `OpenMeteo` (client), `RateLimiter`, `Daily` (hourly → local days, unit conversion, model fallback), `Fetcher` (store days and forecasts), `DegreeDays`, `Comparison` (+ `WeatherComparisonReport`).
- Models: daily values from NBM, then best_match (`OPEN_METEO_MODELS`); soil from `ecmwf_ifs`. Why: `docs/weather-comparison.md`, PLAN.md §8.2 and §8.4.
- Jobs (`app/jobs`, `config/recurring.yml`, production and staging only): `WeatherRefreshJob` 3×/day, `WeatherBackfillJob` (on pivot create/move and after refresh), `WeatherFinalizeJob`, `ForecastPruneJob`. Dev has no recurring jobs: use `bin/rails weather:refresh`.
- `PlantingBalance.new(planting).days` now reads stored weather for the field's cell.
- Admin page `/admin/weather` (users with `admin: true`); "Weather" appears in the nav for admins.
- Key: `OPEN_METEO_API_KEY` in `.env` (development, via dotenv; see `.env.example`) or `open_meteo.api_key` in Rails credentials (servers). Not yet tested with a real key.
- Local dev data: `bin/rails demo:seed` then `bin/rails weather:refresh` gives the demo account a season of weather (the local demo user is an admin, password `demo-password-1`).

## What exists

- Auth:
  - Devise controllers in `app/controllers/users/` render Inertia pages via `InertiaDeviseResponses`.
  - `MagicLinksController` emails a one-time link (`User.generates_token_for(:magic_login)`) and a six-digit code (`User#generate_sign_in_code!`); both are invalidated by `current_sign_in_at`. Email confirmation links also land on a button page, so link scanners can't use them up.
  - Settings at `/settings`.
- Tenancy: `AuthenticatedController` sets `Current.user` / `Current.group` (validated against memberships); `CurrentGroupsController` switches groups. Users get a personal group on sign-up.
- Frontend:
  - `app/frontend/` contains `entrypoints/inertia.ts` (chooses the layout by page name), `layouts/`, `lib/components/` (Button, TextField, FlashMessages, Logo), `pages/Auth|Dashboard|Settings|Admin`.
  - Design tokens (brand, status colors, surfaces, dark mode) are in `entrypoints/application.css`.
- Types and route helpers: Typelizer generates `app/frontend/types/serializers` and `app/frontend/routes` from Alba serializers and the Rails routes. They are committed, and CI checks they're current.
- Domain and engine (Phase 2): models for farms, pivots, fields, plantings, canopy observations, field/group entries and pivot irrigations; plain-Ruby engine in `app/services` (`WaterBalance`, `CropEt`, `Canopy`, `DailyInputs`, `PlantingBalance`); reference data in `db/reference/*.yml` (loaded on seed and every deploy); `bin/rails demo:seed`.
- Weather (Phase 3): see the summary above.
- Core UI (Phase 4): see the summary above.
- Deploy: `Capfile`, `config/deploy*.rb`, `config/systemd/*.service.erb`, `lib/capistrano/tasks/systemd.rake`, `config/deploy/nginx.conf.example`, `docs/deployment.md`. Production stage needs `PRODUCTION_HOST` (new server, D11).

## Gotchas learned this session

- **Tailwind v4 only emits theme variables some class uses.** The chart colors are read from JavaScript, so they're in an `@theme static` block in `application.css`; without it they're missing from `:root` and charts fall back to gray.
- **MapLibre** sets `position: relative` on its container, so size the container (`h-full w-full`) rather than positioning it absolutely. Its worker URL is computed at run time, which breaks under Vite; `PivotMap` imports `maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url` and calls `setWorkerUrl` (`worker.format: 'es'` in `vite.config.ts`).
- **ECharts can't parse `oklch()`.** `lib/charts/palette.ts` converts the design tokens to rgb by painting them on a canvas.
- **Svelte trims whitespace at the start of `{#if}` blocks**, so "Pivot{#if x} · Crop{/if}" renders "Pivot· Crop". Put the separator in an expression: ``{` · ${crop}`}``.
- **`Object#blank?` calls `empty?`** when it exists, so don't define `empty?` on a model (`DailyEntry#nothing_entered?`).
- **Checkbox lists:** a form with every box unchecked sends nothing, which Rails can't tell from "not sent". The field checkboxes send a blank sentinel (`name="…[field_ids][]" value=""`), and `PivotIrrigation.normalize_field_ids` treats `[]` as invalid and "not sent" as all fields.
- **Inertia `<Form>` errors** come back keyed exactly as the server sends them, so nested forms read `errors['fields.0.name']`.
- **Playwright smoke script:** the one used this session signed in as the demo user, switched to "Demo farms" (the demo user's default group is their empty personal one), and walked every page. It lived in the session scratchpad; a version of it belongs in `spec/` or `e2e/` with CI.

## Earlier gotchas

- **Inertia v3** is newer than training data. Check `node_modules/@inertiajs/svelte/dist/*.d.ts` and `@inertiajs/core/types/types.d.ts` instead of guessing:
  - `createInertiaApp({ pages, layout })` sets the pages path and layout.
  - Flash is `page.flash`.
  - `<Form action={{url, method}}>` passes `{errors, processing}` to its children.
  - `onBefore` returning false cancels the request.
- **Typelizer** only records `typelize` hints in development unless `TYPELIZER=1` is set. `config/ci.rb` sets it for the freshness check.
- **Devise test `sign_in`** takes effect on the next request. If that request raises (e.g. a 404 spec), the session isn't saved, so make a normal request first.
- **Rate limits** use `Rails.cache`. The test env uses `:memory_store`, cleared before each example in `spec/rails_helper.rb`.
- **Rack::Attack** safelists localhost, so request specs aren't throttled by it.
- `production.rb` defaults `APP_HOST` to `localhost` so local commands boot. Servers get it from Capistrano `default_env` and the systemd units.
- **`systemctl --user` over SSH** needs `XDG_RUNTIME_DIR`. Without it you get "Failed to connect to bus: No medium found". `lib/capistrano/tasks/systemd.rake` sets it, so run `XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user ...` for manual checks.
- **Assets** are built by Vite Ruby into `public/vite` (manifest in `.vite/`). `config/deploy.rb` points capistrano-rails there instead of its `public/assets` default.
- **Capistrano** loads `deploy.rb` before the stage file, so per-stage `linked_files` go in `config/deploy/<stage>.rb`.
- **Browser smoke testing:** Playwright browsers are cached in `~/.cache/ms-playwright`. Install `playwright` (1.63 works) in the scratchpad rather than the project. Letter Opener writes mail to `tmp/letter_opener/*/plain.html` (Devise mails only have `rich.html`, with HTML-escaped content).
- **`pkill -f` on a pattern** that appears in the same command line kills the shell. Stop dev servers by port/PID instead.
- **Harmless CI noise:** svelte-check logs "Error while loading config" for a Vite template inside `vendor/bundle`; the step still passes.
- **Open-Meteo:** the forecast API only reaches ~92 days back; older days need the historical-forecast API (same models) or the archive (ERA5). best_match, GFS and NBM have **no soil variables** over North America; ECMWF IFS does. Multi-model requests suffix each variable with the model name; multi-location requests return a JSON list (one location returns an object). Coastal points snap to a land cell (`cell_selection=land`), so the API's coordinates can differ from `Weather::Grid` there.
- **Zeitwerk:** one constant per file, including error classes (`weather/error.rb`, `transient_error.rb`, `rate_limited.rb`).
- **Development cache is a null store**, so rate-limit and usage counters don't persist in dev (the admin page shows 0). Staging/production use Solid Cache.
- **AgWeather's public API** (`https://agweather.cals.wisc.edu/api/evapotranspirations|precips?lat=&long=&start_date=&end_date=&units=in`) is only used by the comparison report, never at runtime.
