# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

WISP 3: a rewrite of the Wisconsin Irrigation Scheduling Program (legacy app in `../wisp`).

- `PLAN.md`: where things stand. Its **Handoff** says what's next, then Ben's open choices and the backlog; read it at the start of a session and rewrite the handoff at the end.
- `docs/architecture.md`: how each area works now (pages, irrigation systems, fields and plantings, canopy, weather, daily entry, maps, charts, wording, email, CSV, outside services); `docs/engine.md`: the water balance and projection. Read the area's section before changing it, and keep it current.
- `docs/decisions.md`: why (decisions D1–D15, settled questions Q1–Q11); a new decision takes the next D number with its date and reasons. `docs/legacy-audit.md`: legacy's bugs and WISP 3's fixes (S, C, A IDs).
- `docs/plans/`: the build's frozen record: the original design and eight phases by theme, regrouped from the phases 0–9 the work was planned in (its README maps the old numbers, which older text still cites). A new piece of work that needs a plan gets its own file there, ticked as it lands; when it's done it's frozen like the rest, with what's still current moved into the architecture and engine docs.
- `DEVELOPMENT.md` (setting up a machine, commands), `docs/deployment.md` (staging and production), `TODO.md` (what only Ben can do).

## Commands

```bash
bin/dev                          # Rails :3000 + Vite dev server
bin/ci                           # CI without the browser: standardrb, prettier, eslint, svelte-check/tsc, typelizer freshness, vitest, rspec
bundle exec rspec spec/path_spec.rb
pnpm test                       # vitest
pnpm check                      # svelte-check + tsc
bin/e2e                          # Playwright browser tests on their own database, ~3 min (args go to playwright test: a file, -g, --project desktop)
bin/rails typelizer:generate     # after changing serializers or routes; commit the output
bin/rails demo:seed              # demo account with farms, fields and entries (EMAIL, PASSWORD, YEAR)
bin/rails demo:export            # the demo account, as edited in the app, back to db/demo/farms.yml (its seed)
bin/rails demo:example           # rebuild the public example farm (/example) from the same file, as of July 20 (YEAR)
bin/rails weather:refresh        # fetch weather for active cells now (needs network; OPEN_METEO_API_KEY in .env optional)
bin/rails weather:compare        # AgWeather vs Open-Meteo report → docs/weather-comparison.md
cap staging deploy               # staging (Capistrano)
bin/production deploy            # production (image built on the EC2 server from GitHub, Compose; also status, images, logs, console)
```

## Architecture

The conventions every change touches. Area by area detail is in `docs/architecture.md`.

- **Inertia pages:** controllers `render inertia: "Folder/Page", props: {...}`, which maps to `app/frontend/pages/Folder/Page.svelte`. Pages under `Auth/` use `AuthLayout`; everything else uses `AppLayout` (`app/frontend/entrypoints/inertia.ts`), which goes full width with no footer for `Map/` pages.
- **Shared props** (`InertiaController`): `auth.user`, `auth.group`, `auth.owner`, `auth.groups`, `auth.impersonator` while an admin is signed in as someone else, `example` in example mode, and `today`; `page.flash` carries `notice` and `alert`.
- **Serializers and types:** page props are built with Alba serializers in `app/serializers`; Typelizer generates their TypeScript types (`@/types/serializers`) and typed route helpers (`@/routes`, returning `{url, method}` for `<Form action>` and `<Link href>`).
- **Forms:** Inertia's `<Form>` component with Rails-style input names (`user[email]`). On validation failure, controllers redirect back with `redirect_with_errors(path, record)`. Edit forms end with `FormFooter`: Delete at the left (owners only, asking first), Save at the right; Setup's rows have no Delete buttons. A dialog holding a form takes `guard`, and a page calls `confirmUnsavedChanges(isDirty, form)`, so changes are never dropped silently.
- **Units:** format and parse every quantity through `app/frontend/lib/units.ts` (`units(user.unit_system)`); form inputs in user units use `NumberField`, which submits the stored unit in a hidden input.
- **Dates:** dates from Rails are ISO strings; use `lib/dates.ts`, and for today `today()` there (the server's date, the shared `today` prop), never the browser's `new Date()`. On the server, code on a page's path reads `Current.today` (the example farm's or time travel's day), never `Date.current`.
- **Vocabulary:** a `Pivot` in code is any irrigation system (center pivot, linear, traveler, solid set, drip, location); growers see its kind's name (`Pivot::KIND_NAMES`, `kind_name`) and "irrigation system" collectively. A field is the land; a planting is what grows on it (the whole field or a plot), and has its own balance and page.
- **Text:** labels and short hints stay in the component; a term's meaning goes in `lib/glossary.ts` (`<Term>`), a form input's purpose in `lib/fieldInfo.ts` (`info="key"`), how a crop is modeled in `lib/guidance.ts`. Ruby and TypeScript copies of the same logic (`Outlook`/`lib/outlook.ts`, size limits in `Pivot`/`lib/geo.ts`, `Planting.typical_end`/`typicalEnd`, `Planting#dates_in_order`/`dateProblems`, `FieldBoundary`/`lib/boundary.ts`) change together.
- **Charts:** ECharts through `lib/charts/Chart.svelte` with pure, unit-tested option builders; colors from the `--color-chart-*` tokens; no dual-axis charts (stack grids or small multiples).
- **CSV exports:** PRISM-style frontmatter, values in stored units, UTF-8 with a BOM, grower text escaped with `text` (`CsvExport`, `lib/csv.ts`).

## Rules

- **Tenancy:** every signed-in controller inherits `AuthenticatedController`. Load group-owned records only through `Current.group` (e.g. `Current.group.farms.find(params[:id])`), never `Model.find(params[:id])`. The legacy app's worst bug was unscoped lookups. Actions only a group's owners may take (Q8) use `before_action :require_owner`; deleting a planting or an irrigation group is also open to the member who created it (`owner_or_creator?`; `mayDelete` in `lib/permissions.ts` hides the button); `Current.membership` and `Current.owner?` give the user's role, and pages get it as `auth.owner`. Add a cross-tenant request spec for every new controller. The example farm reaches only GET actions listed with `allow_example`. The exception is `Admin::` controllers (admins only, 404 for everyone else), which see every account.
- **Units:** store water depths in inches. Unit conversion (Q3: `users.unit_system`) happens only at the display and input edge in the frontend.
- **Missing data is NULL, never 0.** A value the user entered as zero is 0.0.
- **Legacy code:** when porting from `../wisp`, check each method against `docs/legacy-audit.md` before reusing it.
- **Engine:** the water balance lives in plain-Ruby services (`WaterBalance`, `CropEt`, `Canopy`, `DailyInputs`, `PlantingBalance`), recalculated on read, never stored. A change to the balance must keep `spec/services/legacy_engine_spec.rb` passing; a deliberate change from legacy gets the next C ID in `docs/legacy-audit.md` and a switch in `LegacyEngine`; keep `docs/engine.md` current. The balance reads a planting's own soil, area and weather cell (copied from its field and system), never the field's or pivot's. Pages running many balances preload their inputs (`FieldStatuses.for(fields)` does all of it: `DailyInputs.preload`, `WeatherDay.balance_inputs_by_cell`, `WeatherForecast.ensemble.latest_by_cell`) instead of querying per field. Days without stored weather (today and ahead) take the latest forecast; `PlantingStatus` runs the projection (`forecast_days`, `crossing`, `ensemble`), and planned irrigation is an irrigation entry on a future date.
- **Weather:** Open-Meteo only, fetched by jobs (never in a request) into `weather_days` per O1280 grid cell, corrected as described in `docs/architecture.md` (Weather). Pages showing irrigation systems keep it current with `WeatherCell.keep_current` and poll with `pollWeather`. Specs never hit the network (WebMock; `spec/support/fake_open_meteo.rb`, recorded responses in `spec/fixtures/files/open_meteo`).
- **Reference data** lives in `db/reference/` (plants, soil types, canopy curves, weather corrections), each value with its source; the About page is built from it, so change a value there with its source and notes.
- Ruby style is Standard; prefer small, plain-Ruby service objects for domain math (no ActiveRecord callbacks cascading recalculation).

## Gotchas

Frontend:

- **Inertia v3** is newer than most training data: check `node_modules/@inertiajs/svelte/dist/*.d.ts` and `@inertiajs/core/types/types.d.ts` rather than guessing. `<Form>` errors come back keyed exactly as the server sends them (`errors['fields.0.name']`); `onBefore` returning false cancels the request. Lists in a form are sent with indexed names (`rows[0][name]`: Inertia's JSON loses `rows[][name]`) and read with `indexed_list`.
- **Svelte trims whitespace** at the start of `{#if}` blocks and inside elements, so "Pivot{#if x} · Crop{/if}" renders "Pivot· Crop": put separators and trailing spaces in expressions (``{` · ${crop}`}``, `{'Within '}`). When part of a button's text is hidden on small screens, give it an `aria-label` so its accessible name stays whole.
- **An `$effect` that calls code writing state it also reads** loops; run that call in `untrack` (see `MapOverlays.sync` in `pages/Map/Show.svelte`).
- **Accessibility (WCAG 2.1 AA):** `e2e/accessibility.spec.ts` runs axe on every page in light and dark, so add new pages to it; findings and fixes go in `docs/accessibility.md`. Status colors as text use `text-status-irrigate-ink` / `text-status-caution-ink` (lighter in dark mode), and text on a caution fill uses `text-on-caution`. Links inside sentences are always underlined. An `sr-only` span inside a control needs the control to be `relative`, or it's positioned against an outer container and shifts the layout. `e2e/keyboard.spec.ts` covers keyboard use: an `EditableCell` grid is one tab stop (roving tabindex), and a bits-ui menu's items are left out rather than hidden with CSS (its arrow keys stop on hidden items).
- **Content Security Policy** (`config/initializers/content_security_policy.rb`): scripts load only from WISP, so an inline `<script>` needs `nonce="<%= content_security_policy_nonce %>"` and an outside script host won't load. Images and connections allow any https source (the map's services). Development adds the Vite dev server; a violation shows as a console error, which the smoke tests fail on.
- **Tailwind v4 only emits theme variables some class uses.** Tokens read from JavaScript (chart colors) are in an `@theme static` block in `application.css`.
- **ECharts and MapLibre can't parse `oklch()`**: get colors through `readPalette()` (`lib/charts/palette.ts`), which converts the tokens to rgb on a canvas. More map gotchas (terra-draw, MapLibre's container, the picker's handles) are in `docs/architecture.md` (Maps).
- **Chromium fires `blur` on a focused input that's removed**; jsdom doesn't, so component tests of edit/cancel flows fire it themselves (`EditableCell.test.ts`).
- **Don't run Prettier on the Markdown docs** (PLAN.md, `docs/`): it reformats every table; lint-staged leaves Markdown alone.
- **lint-staged runs Prettier on committed JSON.** Large data files go in `.prettierignore` (`lib/map/us-outline.json`), or they're expanded to thousands of lines.

Browser tests:

- **Two workers** (files side by side, each file's tests in turn) against one database: a test that writes must not write what another file's tests (or the same file in the other project) read, so the phone project's writes go to their own rows or days. `signIn` adds the session the `setup` project saved (`e2e/auth.setup.ts`, signed in through the form once a run, the demo farms chosen); `bin/e2e` skips the Vite build when nothing it's built from changed.
- **Import `test` and `expect` from `e2e/test.ts`**, not `@playwright/test`: it answers the soil survey, the USGS imagery tiles and OpenFreeMap's vector tiles (empty) for every page (a test's own `page.route` takes precedence; `E2E_LIVE=1 bin/e2e` reaches the real services). The phone project (dark mode) runs only tests tagged `{ tag: '@phone' }`: the accessibility scans, and tests where touch or the small screen's layout matters; a new page's scan gets the tag with the rest.
- **The demo is found by the names in `e2e/demo.json`** (each for the part it plays, described in `e2e/demo.ts`); renaming things in the demo (`db/demo/farms.yml`) means changing them there.
- **An input with an info tip** is also matched by its "About …" button: select it with `getByLabel(label, { exact: true })` or `getByRole('textbox', { name })`.
- **Playwright matches role names by substring** ("Move its pin" matched "Remove its pin"): use `exact: true` where one name contains another.
- **Playwright dismisses dialogs by default**, so a stray `confirm` (unsaved changes) cancels a navigation in a test; handle it with `page.once('dialog', …)`.

Rails and tests:

- **Typelizer** only records `typelize` hints in development unless `TYPELIZER=1` is set (`config/ci.rb` sets it for the freshness check).
- **Devise's test `sign_in`** takes effect on the next request; if that request raises (a 404 spec), the session isn't saved, so make a normal request first.
- **The test environment** records jobs instead of running them (`queue_adapter = :test`), uses a memory cache cleared before each example (rate limits), and `spec/rails_helper.rb` clears `OPEN_METEO_API_KEY` and the reference data (`db:prepare` seeds it into a new test database). Rack::Attack safelists localhost.
- **`Object#blank?` calls `empty?`** when it exists, so don't define `empty?` on a model (`DailyEntry#nothing_entered?`).
- **Checkbox lists:** a form with every box unchecked sends nothing, which Rails can't tell from "not sent". Where that matters, send a blank sentinel first (`name="…[ids][]" value=""`) and drop it with `compact_blank`, so `[]` means none checked and a missing key means not sent.
- **Active Job logs job arguments**, so mail whose arguments are secrets (the sign-in link's token and code) is sent through `SecretMailDeliveryJob` (`self.delivery_job` in `MagicLinkMailer`).
- **Zeitwerk:** one constant per file, error classes included (`weather/error.rb`, `transient_error.rb`, `rate_limited.rb`).

Deploy (details in `docs/deployment.md`, "Changing the deploy"):

- Staging is Capistrano on a shared host; production is Docker Compose on an EC2 server with RDS, its image built on the server from the pushed commit (`bin/production deploy`). A new setting the app reads from `ENV` goes in the server's `/opt/wisp/.env` and the docs' list, not in credentials.
- `systemctl --user` over SSH needs `XDG_RUNTIME_DIR`; staging inherits the production block in `database.yml`, so a production-only setting there needs an `ENV` default that suits staging.

## Working here

- **Propose a plan before building a new feature** unless it's a simple change: the design, the data model and any choices to make, then wait for Ben's go-ahead before implementing.
- **Frontend and visual design work: Ben checks it before CI.** Once the planned changes are in, stop and ask Ben to look at them in the app before running CI, which takes a long time. Expect a few rounds of changes; when the design is settled, update the tests, run `bin/ci` and the browser tests the change touches (`bin/e2e e2e/smoke.spec.ts -g …`), then commit.
- **CI is two parts:** `bin/ci` (a few minutes) and `bin/e2e` (about 3 minutes), separate jobs on GitHub Actions. Run all of `bin/e2e` before merging to `main`, and after a change to shared layout, components or anything every page loads.
- **Work on `main` by default.** Make a feature branch only when the work's scale justifies one (several sessions, a risky or wide change, something to review before it lands). When proposing a plan for a new feature, recommend whether it should get a branch.
- **End of a session:** rewrite PLAN.md's handoff (and its backlog and open choices), tick the work's plan in `docs/plans/` if it has one, update `docs/architecture.md` and `docs/engine.md` for what moved, record new decisions in `docs/decisions.md`, and put anything only Ben can do in `TODO.md`.
- **Comments describe the code:** what it's for and any constraint that isn't obvious. Cite a doc only for a decision or legacy ID (`D15`, `C22`, `Q10`) or a design doc (`docs/engine.md`), never a phase or a plan's section; `git blame` has the history.
- `pkill -f` with a pattern that's also in the command line kills the shell running it; stop dev servers by port or PID.
