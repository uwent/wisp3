# Handoff: WISP 3, end of Phase 3 (2026-10-03)

Read [PLAN.md](PLAN.md) (design, decisions D1–D11, legacy bug audit §9, phases §14, open questions §15) and [CLAUDE.md](CLAUDE.md) (conventions) first. Ben's own action items are in [TODO.md](TODO.md).

## Where things stand

- **Repo:** https://github.com/uwent/wisp3 (public), branch `main`. `bin/ci` runs the same checks as GitHub Actions. Ben pushes; check `git status` / `git log origin/main..` for unpushed commits.
- **Phase 0 (legacy `../wisp`):** done and deployed; precipitation backfill run.
- **Phase 1 (foundation):** done. Staging live at https://dev.wisp.cals.wisc.edu (Puma on `127.0.0.1:3100`, nginx `sites-available/wisp3`, systemd user units `wisp3-web` / `wisp3-jobs`). Redeploy: `bundle exec cap staging deploy` from pushed `main`.
- **Phase 2 (domain + engine):** done. Golden tests against 30 legacy production fields passed, then were retired with the legacy data; `spec/support/legacy_engine.rb` and its synthetic spec remain as the record of each fix (C2, C3, C4, C7, C8, C19).
- **Phase 3 (weather):** done locally on the free API (see below). Not yet on staging: Phase 2 and 3 need a push and `cap staging deploy`, plus the API key in staging credentials (TODO.md).
- **Next: Phase 4, core UI** (PLAN.md §14): setup pages with the pivot map picker, the field status page (chart, daily grid, weather panels), dashboard, pivot irrigation entry, units. Nothing in the UI shows farms or weather yet.

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
- Deploy: `Capfile`, `config/deploy*.rb`, `config/systemd/*.service.erb`, `lib/capistrano/tasks/systemd.rake`, `config/deploy/nginx.conf.example`, `docs/deployment.md`. Production stage needs `PRODUCTION_HOST` (new server, D11).

## Gotchas learned this session

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
