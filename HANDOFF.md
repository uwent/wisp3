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
  - `MagicLinksController` handles one-time links (`User.generates_token_for(:magic_login)`, invalidated by `current_sign_in_at`).
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

## Next: Phase 2, domain model and calculation engine (PLAN.md §4, §5, §14)

Suggested order:

1. **Reference data:** copy `../wisp/db/plants.yml` and `db/soil_types.yml`. Use plain `plants` / `soil_types` tables, not STI subclasses. Plants get a canopy/LAI model key (Q2: field corn uses the WIS curve; other crops get LAI only from entered observations).
2. **Migrations and models from §4:**
   - farms, pivots (location required, no default; radius/arc)
   - fields, plantings (non-overlapping per field), canopy_observations
   - field_entries, field_groups / members / entries
   - pivot_irrigations (`field_ids` array, run hours → inches)
   - Every group-owned query goes through `Current.group`, with a cross-tenant request spec per controller. Weather tables can wait for Phase 3.
3. **Engine** (`app/services` or `app/lib`, plain Ruby, no ActiveRecord): `WaterBalance`, `CropEt` (A3600 percent-cover table and LAI/Kc), `Canopy` (interpolation, held at the last value until `end_date`). Port from `../wisp/vendor/asigbiophys/lib/{ad_calculator,et_calculator}.rb`, applying fixes C2–C8, C18 from §9, with a unit test per formula, band boundary and clamp, plus the property tests in §10.
4. **`DailyInputs` resolver:** field entry > pivot irrigation > field group entry > model, with provenance tags and `rain_model_in` kept alongside (Q7).
5. **Golden fixtures:** write a read-only export script for the legacy app that dumps about 30 anonymized 2026 fields (inputs + legacy AD series) to JSON. Ben runs it on legacy production. Golden specs go in `spec/fixtures/legacy/` and list each expected difference by fix ID.
6. **Demo seed task:** several farms, multi-field pivots, both ET methods, for dev, staging and the beta.

Phase 2 exit: golden tests pass, and every difference traces to a listed fix. Update the PLAN.md §14 checklists as work lands.
