# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

WISP 3: a rewrite of the Wisconsin Irrigation Scheduling Program (legacy app in `../wisp`). The design, decisions (D1–D11) and phases are in `PLAN.md`; check it before starting a phase, and update its checklists as work lands.

## Commands

```bash
bin/dev                          # Rails :3000 + Vite dev server
bin/ci                           # full CI: standardrb, svelte-check/tsc, typelizer freshness, vitest, rspec
bundle exec rspec spec/path_spec.rb
pnpm test                       # vitest
pnpm check                      # svelte-check + tsc
bin/e2e                          # Playwright smoke tests on their own database (args go to playwright test)
bin/rails typelizer:generate     # after changing serializers or routes; commit the output
bin/rails demo:seed              # demo account with farms, fields and entries (EMAIL, PASSWORD, YEAR)
bin/rails weather:refresh        # fetch weather for active cells now (needs network; OPEN_METEO_API_KEY in .env optional)
bin/rails weather:compare        # AgWeather vs Open-Meteo report → docs/weather-comparison.md
```

## Architecture

- Public pages (Phase 6.5): signed out, `/` is the landing page (`PagesController#home`), signed in the dashboard (Devise `authenticated` route); `/about` is the documentation, public. Both use `AppLayout`, whose nav is just About when signed out. The landing page and About share `lib/docs/Introduction.svelte`.
- Rails controllers render Svelte pages with Inertia: `render inertia: "Folder/Page", props: {...}` maps to `app/frontend/pages/Folder/Page.svelte`. Pages under `Auth/` use `AuthLayout`; everything else uses `AppLayout` (`app/frontend/entrypoints/inertia.ts`), which goes full width with no footer for `Map/` pages.
- Shared props (`auth.user`, `auth.group`, `auth.owner`, `auth.groups`, and `auth.impersonator` while an admin is signed in as someone else) come from `InertiaController`; `page.flash` carries `notice` and `alert`.
- Page props are built with Alba serializers in `app/serializers`; Typelizer generates their TypeScript types (`@/types/serializers`) and typed route helpers (`@/routes`, returning `{url, method}` for `<Form action>` and `<Link href>`).
- Forms: use Inertia's `<Form>` component with Rails-style input names (`user[email]`). On validation failure, controllers redirect back with `redirect_with_errors(path, record)`.
- Units: format and parse every quantity through `app/frontend/lib/units.ts` (`units(user.unit_system)`); form inputs in user units use `NumberField`, which submits the stored unit in a hidden input. Dates from Rails are ISO strings; use `lib/dates.ts`.
- Grids: `EditableCell` saves one value through `lib/save.ts` (an Inertia visit that keeps scroll and state, resolving with an error message or null). Daily entries are written with `FieldEntry.record` / `FieldGroupEntry.record` (blank clears a value; an empty entry is deleted); canopy readings with `CanopyObservation.record`.
- Canopy (Phase 6.7): each crop's default percent cover curve is in `db/reference/canopy_curves.yml` (`CanopyCurve`; LAI curves in `CanopyModel`, field corn only, and only crops with one can use LAI). `Canopy` follows it with no readings and scales it through readings (`plantings.canopy_interpolation`: `curve`, or `linear` for straight lines), and `Canopy#check` warns when readings disagree. The About page's crop cards are built from the YAML, so change a curve there with its sources and notes; the research is in `docs/canopy/`.
- Soil types: `db/reference/soil_types.yml` (field capacity and wilting point; comments give each value's sources, and `basis` feeds the About page's soil table). Change a value there with its source; it moves every field on that soil that doesn't set its own. `lib/soils.ts` maps soil survey textures to these types for the setup suggestion and the picker's Soil types layer.
- Guidance text (how a crop is modeled, which readings to enter and how often) is in `lib/guidance.ts`, worded from the legacy user guide; it describes `Canopy`/`CanopyModel`, so change it with them. Crop-specific notes go in its `CROP_NOTES`.
- Glossary: terms and definitions in `lib/glossary.ts`. Mark a term by hand with `<Term id="lai">LAI</Term>`; for paragraphs of prose, `<GlossaryText paragraphs={…}>` marks each term's first appearance in the block. Keep it to running text, not every label.
- Charts: ECharts through `lib/charts/Chart.svelte`, given a `build(palette)` function; option builders are pure (`fieldChart.ts`, `weatherCharts.ts`) and unit tested. Colors come from the `--color-chart-*` tokens (validated for color blindness, light and dark). No dual-axis charts: stack grids or use small multiples.
- Tables: `DataTable.svelte` sorts and searches rows in the browser from column definitions (`lib/table.ts`).
- Pivot shapes: a pivot is a center pivot (`radius_ft`, optionally an arc) or a linear move (`kind: linear`: a machine `length_ft` long traveling `travel_ft` along `travel_bearing_deg`, whole degrees 0–179; a rectangle centered on its location). Draw and measure either with `pivotOutline` and `shapeAcres` (`lib/geo.ts`); forms edit a `ShapeDraft` through `PivotShapeFields`. Size limits are in `Pivot` (validations and check constraints) and mirrored in `lib/geo.ts`; change both together.
- Maps: MapLibre through `lib/map/` (`loadMapLibre` loads it on demand and sets its Vite-bundled worker; `basemaps.ts`, `BasemapToggle`, `PlaceSearch`). `PivotMap.svelte` is the setup picker, with a Soil types layer from the soil survey. The Map tab (Phase 7, `MapController`) shares the dashboard's data through `OperationOverview`: `OverviewMap` draws the pivots (`lib/map/pivots.ts`) and their badges, and `lib/overview.ts` orders and picks fields. Its optional public layers are listed in `lib/map/overlays.ts`, each with `valueAt` for the tooltip, and applied by `MapOverlays` (loaded in the browser; a failing provider marks its layer unavailable and the map carries on). Radar values are read from the IEM tile's colors (`lib/map/radar.ts`); MRMS values are millimeters.
- Devise controllers live in `app/controllers/users/` and render Inertia pages through `InertiaDeviseResponses`. Passwordless sign-in (`MagicLinksController`) emails a one-time link (`User.generates_token_for(:magic_login)`) and a six-digit code (`User#generate_sign_in_code!`). Wrap links in emails with `email_link_to` (adds `ses:no-track`); links to a group's record add `operation: group.id`, which switches to that group if the user belongs to it.
- Rainfall setting (Phase 6.6, Q7): `fields.use_model_precip` overrides the group's (NULL follows it; `Field#effective_use_model_precip`). Entered-only applies through today; `DailyInputs` still takes forecast rain after `today:`, and `PlantingStatus#dry_projection` adds the no-rain case. The field page's season details are computed in the browser (`lib/seasonStats.ts`).
- Tasks (Phase 6.7): `PlantingTasks` (via `PlantingStatus#tasks`, `summary.tasks`) lists the readings due and the canopy check for a planting in season, worded once for the field page, dashboard cards and digest; `lib/guidance.ts` explains the advice in prose.
- Daily digest (Phase 6): `DailyDigestJob` (6 am) → `DailyDigest` (a user's included fields in season, by operation, farm, weather zone (grid cell), pivot and field, with `WeatherSummary` per zone and each field's due tasks; `users.digest_scope` picks which included fields are listed; `users.digest_frequency` decides whether it's sent) → `DigestMailer`. Settings, preview and test send are on the Alerts page (`AlertsController`). Its outlook wording (`Outlook`) mirrors `lib/outlook.ts`; change both together.
- Health check (Phase 8 B): `HealthCheck` reports failed Solid Queue jobs since the previous check and missing weather for active cells (the state of the data, which clears itself); `HealthCheckJob` (7 am) stores the result (`HealthCheck.run`/`.last`, in `Rails.cache`) and emails the confirmed admins when there are problems (`AdminMailer.health`). The admin weather page shows the stored result with a re-run; `/up` (`HealthController`) gives public JSON (status, version, database, the last check's counts). `DailyDigestJob` fails at the end if any user's digest failed, so it shows as a failed job. Failed jobs are read only under the `:solid_queue` adapter (its tables are only on the servers); specs stub `SolidQueue::FailedExecution`.
- Impersonation (Phase 8 B): an admin signs in as a non-admin from their admin page (`Admin::ImpersonationsController`, session keys `impersonator_id`/`impersonated_id`, trackable skipped) and returns with `DELETE /impersonation`. `impersonator` (`ApplicationController`) is the admin only while the keys match the signed-in user; pages get `auth.impersonator`, and `AppLayout` shows the violet bar and prefixes the tab title. Actions that mustn't be taken on someone's behalf use `before_action :forbid_while_impersonating`.

## Rules

- **Tenancy:** every signed-in controller inherits `AuthenticatedController`. Load group-owned records only through `Current.group` (e.g. `Current.group.farms.find(params[:id])`), never `Model.find(params[:id])`. The legacy app's worst bug was unscoped lookups. Actions only a group's owners may take (Q8) use `before_action :require_owner`; `Current.membership` and `Current.owner?` give the user's role, and pages get it as `auth.owner`. Add a cross-tenant request spec for every new controller. The exception is `Admin::` controllers (admins only, 404 for everyone else), which see every account.
- **Units:** store water depths in inches. Unit conversion (Q3: `users.unit_system`) happens only at the display and input edge in the frontend.
- **Missing data is NULL, never 0.** A value the user entered as zero is 0.0.
- **Legacy code:** when porting from `../wisp`, check each method against the audit in `PLAN.md` §9 before reusing it.
- **Engine:** the water balance lives in plain-Ruby services (`WaterBalance`, `CropEt`, `Canopy`, `DailyInputs`, `PlantingBalance`), recalculated on read, never stored. A change to the balance must keep `spec/services/legacy_engine_spec.rb` passing; a deliberate change from legacy gets a fix ID in PLAN.md §9 and a switch in `LegacyEngine`. Pages running many balances preload their inputs (`DailyInputs.preload`, `WeatherDay.balance_inputs_by_cell`, `WeatherForecast.ensemble.latest_by_cell`; `FieldStatuses.for(fields)` does all of it) instead of querying per field. Days without stored weather (today and ahead) take the latest forecast; `PlantingStatus` runs the projection (`forecast_days`, `crossing`, `ensemble`), and planned irrigation is an irrigation entry on a future date.
- **Weather:** Open-Meteo only, fetched by jobs (never in a request) into `weather_days` per O1280 grid cell (`Weather::Grid`); values stored in inches/°F/mph, soil moisture as m³/m³. Specs never hit the network (WebMock; `spec/support/fake_open_meteo.rb`, recorded responses in `spec/fixtures/files/open_meteo`).
- Ruby style is Standard; prefer small, plain-Ruby service objects for domain math (no ActiveRecord callbacks cascading recalculation).

## Gotchas

Frontend:

- **Inertia v3** is newer than most training data: check `node_modules/@inertiajs/svelte/dist/*.d.ts` and `@inertiajs/core/types/types.d.ts` rather than guessing. `<Form>` errors come back keyed exactly as the server sends them (`errors['fields.0.name']`); `onBefore` returning false cancels the request.
- **Svelte trims whitespace** at the start of `{#if}` blocks and inside elements, so "Pivot{#if x} · Crop{/if}" renders "Pivot· Crop": put separators and trailing spaces in expressions (``{` · ${crop}`}``, `{'Within '}`). When part of a button's text is hidden on small screens, give it an `aria-label` so its accessible name stays whole.
- **An `$effect` that calls code writing state it also reads** loops; run that call in `untrack` (see `MapOverlays.sync` in `pages/Map/Show.svelte`).
- **Accessibility (WCAG 2.1 AA):** `e2e/accessibility.spec.ts` runs axe on every page in light and dark, so add new pages to it; findings and fixes go in `docs/accessibility.md`. Status colors as text use `text-status-irrigate-ink` / `text-status-caution-ink` (lighter in dark mode), and text on a caution fill uses `text-on-caution`. Links inside sentences are always underlined. An `sr-only` span inside a control needs the control to be `relative`, or it's positioned against an outer container and shifts the layout. `e2e/keyboard.spec.ts` covers keyboard use: an `EditableCell` grid is one tab stop (roving tabindex), and a bits-ui menu's items are left out rather than hidden with CSS (its arrow keys stop on hidden items).
- **Content Security Policy** (`config/initializers/content_security_policy.rb`): scripts load only from WISP, so an inline `<script>` needs `nonce="<%= content_security_policy_nonce %>"` and an outside script host won't load. Images and connections allow any https source (the map's services). Development adds the Vite dev server; a violation shows as a console error, which the smoke tests fail on.
- **Tailwind v4 only emits theme variables some class uses.** Tokens read from JavaScript (chart colors) are in an `@theme static` block in `application.css`.
- **ECharts and MapLibre can't parse `oklch()`**: get colors through `readPalette()` (`lib/charts/palette.ts`), which converts the tokens to rgb on a canvas.
- **The pivot picker's handles aren't MapLibre draggable markers**, which follow the pointer and flicker against a constrained position; `PivotMap`'s `followPointer` moves the shape and places each handle from it. Their custom cursors are SVG data URLs (`lib/map/cursors.ts`).
- **MapLibre** sets `position: relative` on its container, so size the container (`h-full w-full`) rather than positioning it absolutely. Load it with `loadMapLibre()` (its worker URL breaks under Vite otherwise; `worker.format: 'es'` in `vite.config.ts`).
- **Chromium fires `blur` on a focused input that's removed**; jsdom doesn't, so component tests of edit/cancel flows fire it themselves (`EditableCell.test.ts`).
- **Playwright dismisses dialogs by default**, so a stray `confirm` (unsaved changes) cancels a navigation in a test; handle it with `page.once('dialog', …)`.
- **lint-staged runs Prettier on committed JSON.** Large data files go in `.prettierignore` (`lib/map/us-outline.json`), or they're expanded to thousands of lines.

Rails and tests:

- **Typelizer** only records `typelize` hints in development unless `TYPELIZER=1` is set (`config/ci.rb` sets it for the freshness check).
- **Devise's test `sign_in`** takes effect on the next request; if that request raises (a 404 spec), the session isn't saved, so make a normal request first.
- **The test environment** records jobs instead of running them (`queue_adapter = :test`), uses a memory cache cleared before each example (rate limits), and `spec/rails_helper.rb` clears `OPEN_METEO_API_KEY` and the reference data (`db:prepare` seeds it into a new test database). Rack::Attack safelists localhost.
- **`Object#blank?` calls `empty?`** when it exists, so don't define `empty?` on a model (`DailyEntry#nothing_entered?`).
- **Checkbox lists:** a form with every box unchecked sends nothing, which Rails can't tell from "not sent". The field checkboxes send a blank sentinel (`name="…[field_ids][]" value=""`); `PivotIrrigation.normalize_field_ids` treats `[]` as invalid and "not sent" as all fields.
- **Active Job logs job arguments**, so mail whose arguments are secrets (the sign-in link's token and code) is sent through `SecretMailDeliveryJob` (`self.delivery_job` in `MagicLinkMailer`).
- **Zeitwerk:** one constant per file, error classes included (`weather/error.rb`, `transient_error.rb`, `rate_limited.rb`).
- CSV export is in inches whatever the user's units, as stored.

Deploy:

- **`systemctl --user` over SSH** needs `XDG_RUNTIME_DIR` ("Failed to connect to bus" without it); `lib/capistrano/tasks/systemd.rake` sets it, so check by hand with `XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user …`.
- Vite builds to `public/vite` (`set :assets_prefix, "vite"` in `config/deploy.rb`). Capistrano loads `deploy.rb` before the stage file, so per-stage `linked_files` go in `config/deploy/<stage>.rb`. `production.rb` defaults `APP_HOST` to `localhost` so local commands boot; servers get it from Capistrano and the systemd units.

Outside services:

- **Open-Meteo:** the forecast API reaches only ~92 days back (older days need the historical-forecast API or the archive). best_match, GFS and NBM have no soil variables over North America; ECMWF IFS does. Multi-model requests suffix each variable with the model name; multi-location requests return a list (one location, an object). Coastal points snap to a land cell, so the API's coordinates can differ from `Weather::Grid` there.
- **Nominatim** (place search) forbids search-as-you-type: `PlaceSearch` searches only on Enter or Go. Proxy it or switch providers if use grows.
- **Map layers** (`lib/map/overlays.ts`): NOAA's MRMS image service labels its values inches but returns millimeters; NOAA's radar image service stores rendered colors (and defaults to its oldest raster), so radar values come from IEM's tiles (`lib/map/radar.ts`).

Working here:

- **Propose a plan before building a new feature** unless it's a simple change: the design, the data model and any choices to make, then wait for Ben's go-ahead before implementing.
- `pkill -f` with a pattern that's also in the command line kills the shell running it; stop dev servers by port or PID.
