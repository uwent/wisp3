# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

WISP 3: a rewrite of the Wisconsin Irrigation Scheduling Program (legacy app in `../wisp`). The design, decisions (D1–D11) and phases are in `PLAN.md`; check it before starting a phase, and update its checklists as work lands.

## Commands

```bash
bin/dev                          # Rails :3000 + Vite dev server
bin/ci                           # full CI: standardrb, svelte-check/tsc, typelizer freshness, vitest, rspec
bundle exec rspec spec/path_spec.rb
npm test                         # vitest
npm run check                    # svelte-check + tsc
bin/e2e                          # Playwright smoke tests on their own database (args go to playwright test)
bin/rails typelizer:generate     # after changing serializers or routes; commit the output
bin/rails demo:seed              # demo account with farms, fields and entries (EMAIL, PASSWORD, YEAR)
bin/rails weather:refresh        # fetch weather for active cells now (needs network; OPEN_METEO_API_KEY in .env optional)
bin/rails weather:compare        # AgWeather vs Open-Meteo report → docs/weather-comparison.md
```

## Architecture

- Rails controllers render Svelte pages with Inertia: `render inertia: "Folder/Page", props: {...}` maps to `app/frontend/pages/Folder/Page.svelte`. Pages under `Auth/` use `AuthLayout`; everything else uses `AppLayout` (`app/frontend/entrypoints/inertia.ts`).
- Shared props (`auth.user`, `auth.group`, `auth.groups`) come from `InertiaController`; `page.flash` carries `notice` and `alert`.
- Page props are built with Alba serializers in `app/serializers`; Typelizer generates their TypeScript types (`@/types/serializers`) and typed route helpers (`@/routes`, returning `{url, method}` for `<Form action>` and `<Link href>`).
- Forms: use Inertia's `<Form>` component with Rails-style input names (`user[email]`). On validation failure, controllers redirect back with `redirect_with_errors(path, record)`.
- Units: format and parse every quantity through `app/frontend/lib/units.ts` (`units(user.unit_system)`); form inputs in user units use `NumberField`, which submits the stored unit in a hidden input. Dates from Rails are ISO strings; use `lib/dates.ts`.
- Grids: `EditableCell` saves one value through `lib/save.ts` (an Inertia visit that keeps scroll and state, resolving with an error message or null). Daily entries are written with `FieldEntry.record` / `FieldGroupEntry.record` (blank clears a value; an empty entry is deleted); canopy readings with `CanopyObservation.record`.
- Charts: ECharts through `lib/charts/Chart.svelte`, given a `build(palette)` function; option builders are pure (`fieldChart.ts`, `weatherCharts.ts`) and unit tested. Colors come from the `--color-chart-*` tokens (validated for color blindness, light and dark). No dual-axis charts: stack grids or use small multiples.
- Tables: `DataTable.svelte` sorts and searches rows in the browser from column definitions (`lib/table.ts`).
- Map: `PivotMap.svelte` (MapLibre, loaded on demand; its worker is bundled by Vite and set with `setWorkerUrl`).
- Devise controllers live in `app/controllers/users/` and render Inertia pages through `InertiaDeviseResponses`. Passwordless sign-in (`MagicLinksController`) emails a one-time link (`User.generates_token_for(:magic_login)`) and a six-digit code (`User#generate_sign_in_code!`). Wrap links in emails with `email_link_to` (adds `ses:no-track`).

## Rules

- **Tenancy:** every signed-in controller inherits `AuthenticatedController`. Load group-owned records only through `Current.group` (e.g. `Current.group.farms.find(params[:id])`), never `Model.find(params[:id])`. The legacy app's worst bug was unscoped lookups. Add a cross-tenant request spec for every new controller. The exception is `Admin::` controllers (admins only, 404 for everyone else), which see every account.
- **Units:** store water depths in inches. Unit conversion (Q3: `users.unit_system`) happens only at the display and input edge in the frontend.
- **Missing data is NULL, never 0.** A value the user entered as zero is 0.0.
- **Legacy code:** when porting from `../wisp`, check each method against the audit in `PLAN.md` §9 before reusing it.
- **Engine:** the water balance lives in plain-Ruby services (`WaterBalance`, `CropEt`, `Canopy`, `DailyInputs`, `PlantingBalance`), recalculated on read, never stored. A change to the balance must keep `spec/services/legacy_engine_spec.rb` passing; a deliberate change from legacy gets a fix ID in PLAN.md §9 and a switch in `LegacyEngine`. Pages running many balances preload their inputs (`DailyInputs.preload`, `WeatherDay.balance_inputs_by_cell`) instead of querying per field.
- **Weather:** Open-Meteo only, fetched by jobs (never in a request) into `weather_days` per O1280 grid cell (`Weather::Grid`); values stored in inches/°F/mph, soil moisture as m³/m³. Specs never hit the network (WebMock; `spec/support/fake_open_meteo.rb`, recorded responses in `spec/fixtures/files/open_meteo`).
- Ruby style is Standard; prefer small, plain-Ruby service objects for domain math (no ActiveRecord callbacks cascading recalculation).
