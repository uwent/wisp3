# Handoff: WISP 3, end of Phase 1 (2026-10-02)

Read [PLAN.md](PLAN.md) (design, decisions D1–D11, legacy bug audit §9, phases §14, open questions §15) and [CLAUDE.md](CLAUDE.md) (conventions) first. Ben's own action items are in [TODO.md](TODO.md).

## Where things stand

- **Repo:** https://github.com/uwent/wisp3 (public), branch `main`, GitHub Actions CI green. `bin/ci` runs the same checks locally.
- **Phase 0 (legacy `../wisp`):** done and deployed by Ben. That covered tenant scoping (S1), the rainfall toggle fix (C1), `rake precip:backfill`, and disabling the Feb 15 wipe. Ben may or may not have run the backfill yet.
- **Phase 1:** done. Staging has been live at https://dev.wisp.cals.wisc.edu since 2026-10-03:
  - Puma on `127.0.0.1:3100` behind nginx; nginx config is `sites-available/wisp3`, and the legacy site's config is kept.
  - `wisp3-web` and `wisp3-jobs` are systemd user services, enabled.
  - Redeploy with `cap staging deploy`, from the pushed `main` branch.
  - Still open (Ben): sign up on staging and check the confirmation and sign-in-link emails arrive.

## What exists

- Auth:
  - Devise controllers in `app/controllers/users/` render Inertia pages via `InertiaDeviseResponses`.
  - `MagicLinksController` emails a one-time link (`User.generates_token_for(:magic_login)`) and a six-digit code (`User#generate_sign_in_code!`); both are invalidated by `current_sign_in_at`. Email confirmation links also land on a button page, so link scanners can't use them up.
  - Settings at `/settings`.
- Tenancy: `AuthenticatedController` sets `Current.user` / `Current.group` (validated against memberships); `CurrentGroupsController` switches groups. Users get a personal group on sign-up.
- Frontend:
  - `app/frontend/` contains `entrypoints/inertia.ts` (chooses the layout by page name), `layouts/`, `lib/components/` (Button, TextField, FlashMessages, Logo), `pages/Auth|Dashboard|Settings`.
  - Design tokens (brand, status colors, surfaces, dark mode) are in `entrypoints/application.css`.
- Types and route helpers: Typelizer generates `app/frontend/types/serializers` and `app/frontend/routes` from Alba serializers and the Rails routes. They are committed, and CI checks they're current.
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

## Phase 2 status (domain model and calculation engine)

Done (see PLAN.md §14 Phase 2):

- Schema and models for §4 (no weather tables yet), reference data in `db/reference/*.yml`.
- Engine in `app/services`: `CropEt`, `Canopy` + `CanopyModel`, `WaterBalance`, `DailyInputs`, `PlantingBalance`.
- `spec/support/legacy_engine.rb`: legacy's balance with fixes C2, C7, C8 switchable; `spec/golden` compares fixtures and attributes differences (C3/C4 come from the canopy series).
- `bin/rails demo:seed`.

Remaining: Ben runs `script/legacy/export_golden_fixtures.rb` on legacy production (TODO.md); then `bin/rails golden:import FILE=…` and work through failures. A failure of "is reproduced by LegacyEngine" means `LegacyEngine` doesn't yet match legacy (fix `LegacyEngine`); a failure of "differs … only where a listed fix explains it" means an unexplained change (fix the engine, or add a fix ID to §9 with a `LegacyEngine` switch). Watch for legacy's first day: its AD is recomputed on top of its own stored value, so both runs start from the fixture's day-1 AD.

Next after that: Phase 3, weather (PLAN.md §8, §14). `PlantingBalance` takes `weather: {date => {et0:, precip:}}`; Phase 3 supplies it from `weather_days`.
