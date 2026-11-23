# Phase 3: The working app

October 3–7, 2026. The pages growers use every day (setup, the planting page with its grid and charts, the dashboard, daily entry, CSV, units), a review's fixes, the daily digest, the landing and About pages, and the rain setting with season details.

*A record of the build, frozen on 2026-11-22. It was planned and written in phases 0–9, regrouped here by theme; each section's heading gives its old number, and [README.md](README.md) maps every old phase and section ID to its place. Cross-references inside the text ("G.14 part 7", "Phase 6.7", "§5.3") use the old numbers. Later work may have changed what's described: for how the app works now, see [docs/architecture.md](../architecture.md) and [docs/engine.md](../engine.md); for why, [docs/decisions.md](../decisions.md).*

## Core UI (was Phase 4)

- [x] Setup pages (farms/pivots/fields/plantings), "copy last season", and a guided first-run setup (target: two-field pivot in under 5 minutes, §13). `/setup` (nested list, dialogs for fields and crops, season picker, the group's rainfall setting), `/setup/start` (`QuickSetup`: farm, pivot on the map, fields with crops, all or nothing), `SeasonCopy`.
- [x] Pivot location picker (MapLibre, click center, drag radius) used in pivot creation; location required. `PivotMap`: USGS imagery or OpenFreeMap streets, draggable center and radius handle, arcs, "use my location", the group's other pivots outlined.
- [x] Editable daily grid component; field status page with the summary box. `EditableCell` (click or type to edit, Enter saves and moves down, arrow keys, Escape); `FieldDaysController` saves a day's entry and canopy reading together.
- [x] ECharts chart: observed AD, inputs, thresholds, zoom. AD (or % moisture) above, rain and irrigation below on the same date axis (no dual axis), threshold lines, reading days marked, last 30 days by default.
- [x] Weather panels on the field page from `weather_days` and the forecast (Ben's request): modeled soil moisture by depth (against the field's FC/PWP) and soil temperature, GDD since emergence, temperature, humidity/VPD, wind and cloud cover. `WeatherPanel`; one measure per chart, forecast shaded. Later: precipitation (rain and snow-and-other stacked, with snowfall bars and snow depth in light gray when there's snow) and reference vs crop ET as daily bars, each with running totals over the days in view in a grid below; an (i) on each card explaining its measures, and a reset button once a chart is zoomed or a series toggled (`ChartCard`, `InfoTip`).
- [x] Dashboard by farm → pivot → field ("Farm:", "Pivot:" cards with View/Edit, "Field:" status cards; pivots without fields listed). A pivot's page shows its irrigation and its cell's weather for the season (`WeatherSection`, shared with the field page; reference ET only, GDD from the season start).
- [x] Dashboard (field cards, status), bulk daily entry, field groups. Cards show status, AD, a 21-day sparkline, last rain and irrigation; days-until-crossing waits for the Phase 5 projection.
- [x] Pivot irrigation entry (inches or run hours, which fields it applied to) with "from pivot" badges and per-field overrides in field grids. On the pivot's irrigation page and in daily entry; the grid shows the pivot amount under a field's override.
- [x] CSV export (parity with legacy columns), plus each input's source and the modeled rain. Depths in inches whatever the user's units (`PlantingCsv`).
- [x] Settings menu with the unit toggle (Q3) and the `units.ts` formatters and parsers used by every display and input. `NumberField` shows and parses in the user's units and submits stored units.
- [x] Modeled rain shown next to entered corrections in the grid, chart and season summary (Q7).
- [x] Playwright smoke tests in CI (§10). A local script covered every page this phase (desktop, and phone in dark mode). *(In the repo and CI from Phase 4.5: `bin/e2e`.)*
- **Exit:** the main legacy features are all available; an internal user can manage a season end to end. *(Verified locally in a headless browser on the demo data and a fresh metric-units account, 2026-10-03; not yet deployed to staging.)*

---

## Review fixes and polish (was Phase 4.5)

From a review of Phases 1–4 (2026-10-03): bugs, plan items that slipped, and rough edges to finish before the projection work builds on these pages.

Done 2026-10-03; the staging deploy followed, and the member roles were decided (Q8, 2026-10-04). Also fixed: GitHub CI failed because `db:prepare` seeds reference data into a freshly created test database; `spec/rails_helper.rb` now clears it before the suite.

Bugs:
- [x] **Escape in a grid cell saves the draft.** Chromium fires `blur` when the focused input is removed, and `EditableCell`'s `onblur` calls `commit()` without checking that editing was cancelled. Reproduced in Playwright on the field grid (typing a note, then Escape, sent the PATCH). The jsdom test passes because jsdom doesn't blur on removal. Guard `commit` (a cancelled flag or `if (!editing) return`) and cover it in the Playwright smoke tests. *(Fixed; a Vitest case simulates the blur, and the e2e test fails without the fix.)*
- [x] Setup: "Delete this crop" closes the dialog even when the confirm is cancelled.

Slipped from the plan:
- [x] **Field-group percent cover** (§4 precedence: "group pct-cover entries become CanopyObservations on each member planting"). The field group grid has rain, irrigation, moisture and notes, but no cover column. *(A Cover column when a member has a percent-cover crop; saving writes `CanopyObservation.record` on each member's percent-cover planting that day; the grid shows their shared reading or "varies".)*
- [x] Playwright smoke tests in CI (carried over from Phase 4): sign in, the demo group, every page, one grid edit, one daily entry save, Escape-cancels. *(`bin/e2e`: own database `wisp3_e2e`, demo account with synthetic weather from `e2e/seed.rb`, desktop and phone/dark; a step in `bin/ci` and GitHub Actions, which uploads the report on failure.)*
- [x] Deploy Phases 4 and 4.5 to staging and smoke test there (each phase ends deployed to staging). *(Ben: push, then `bundle exec cap staging deploy`; TODO.md.)* *(Done.)*
- [x] Give unassigned §11/§12 items a phase, or cut them: admin users list, CSV, announcements and impersonation; the public landing and about pages; the admin email when a job fails or a cell's weather is more than 24 h stale. Suggest Phase 8 for all of them. *(Added to Phase 8.)*
- [x] Plan housekeeping: Phase 7's "moving a pivot triggers a backfill" already shipped in Phase 3 (`Pivot#backfill_weather`; the balance is recalculated on read). The Phase 1 and Phase 3 exit notes still say staging sign-up and email delivery and the commercial key are "still to check", but TODO.md marks them done. Reconcile both. *(Done.)*

Polish:
- [x] **Weather-pending state.** A new pivot shows blank ET and a flat AD line until its backfill lands, with no explanation. Show "Weather for this pivot is on the way" on the field page and dashboard card while the cell has no days. *(`PlantingStatus#weather_pending?`.)*
- [x] Daily entry: changing the date (arrows or picker), or leaving the page, silently drops unsaved values. Use `confirmUnsavedChanges` (the form already tracks `isDirty`).
- [x] Weather panels cover the whole season while the soil-water chart opens on the last 30 days. On a phone that's eight dense season-long charts. Open them on the same window as the main chart (or link their zoom), and consider collapsing them by default on narrow screens. *(Same window, scroll or pinch for more, collapsed on phones.)*
- [x] Phone header: the group switcher and user menu wrap to a second row, so about 140 px of chrome sits above the content. Fold them into one compact menu at phone widths. *(Two rows; the group switch moves into the account menu.)*
- [x] Pivot irrigation page: "Add an irrigation" for a date that already has one silently replaces it. Warn, or switch the form to editing that day. *(Warns, with "Edit that one instead".)*
- [x] Copy last season: plantings that fail validation are skipped silently. Report how many were skipped and why. *(The realistic case is a season running into the next year, whose copy overlaps it.)*
- [x] Farm notes exist in the model but can't be edited (the farm dialog has only the name).
- [x] Charts draw with the body font when they are built. If Red Hat Text hasn't loaded yet, canvas text falls back to the system font, so rebuild once `document.fonts.ready` resolves.
- [x] CSV export: prefix cells starting with `=`, `+`, `-` or `@` with `'` (spreadsheet formula injection from field, farm and note text).
- [x] Dashboard runs the full balance for each field, about 5 queries per field (~50 ms for 2 fields locally). Measure with 50+ fields and batch the loads before Phase 5 adds forecast and ensemble runs to every card. *(60 fields: 368 queries / ~830 ms → 13 queries / ~220 ms in the test environment, via `DailyInputs.preload` and `WeatherDay.balance_inputs_by_cell`. What remains is the balance itself; Phase 5 should run projections from the same preloaded inputs.)*
- [x] Membership roles: any member can rename the group, change its rainfall setting or delete farms. Decide on owner/member roles before group invitations (Phase 8 stretch). *(Q8 decided 2026-10-04: owner and member; shipped with the operation page.)*
- [x] Specs: a `PlantingCsv` unit spec (columns, totals, sources), `SeasonCopy` edge cases (leap day, overlap), and Vitest coverage for `weatherCharts.ts` and `dates.ts`.
- **Exit:** the bugs are fixed with tests, Playwright runs in CI, Phase 4 is live on staging, and every unassigned plan item has a phase.

---

## Alerts (was Phase 6)

Decided 2026-10-04 (Ben): a **daily digest** instead of event-based alerts. Simpler to build and to understand, and it shows the whole picture every day.

- [x] Digest settings: how often (never, daily during the season, or only when irrigation is needed: a field at Irrigate or Caution, i.e. needing water within 3 days) and which fields it includes (default: every field in the user's operations, picked by operation, farm or field). *(Alerts page, `/alerts`, in the main nav; `digest_exclusions` in §4.)*
- [x] The digest email rehashes each included field's dashboard card: status, AD today, the outlook ("Irrigate by …", refill amount, how many forecast scenarios agree), last rain and irrigation. A short "Needs attention" list (irrigate, or caution; soonest first) leads, then every field by farm and pivot as on the dashboard, each pivot with its weather for the past 7 days and next 7 (rain, ET, range of highs and lows); a field needing attention gets the full outlook, one that's fine a compact line. *(`DailyDigest`, `WeatherSummary`, `DigestMailer`; the outlook's wording is in Ruby too, `Outlook`, matching `lib/outlook.ts`. Links carry `?operation=` so they open in the field's operation.)*
- [x] **Digest by weather zone** (Ben, 2026-10-15): operation › farm › weather zone (the grid cell the farm's pivots share, with that zone's weather and the pivots in it) › pivot › field, with "Operation:", "Farm:", "Pivot:" and "Field:" labels as on the dashboard and each field's due tasks (Phase 6.7). When the included fields are all in one operation (or on one farm), that heading gives way to a line at the top ("Operation: Demo · Farm: Hancock"). *(`DailyDigest#operations`, `#context`.)*
- [x] **What the digest lists** (Ben, 2026-10-15): `users.digest_scope`: all the fields it covers (in season or not, "Off season" with when the season starts or ended), those with a crop in season (the default), those needing irrigation or a reading, or only those needing irrigation. With nothing to list it says "No action needed" and why, with the in-season pivots' weather. A new frequency, `daily_all_year`, sends every morning even with nothing in season (weather for every included pivot). "Fields it covers" gains a pivot level (a pivot with none of its fields picked is left out whole, `DigestExclusion` on a Pivot). The footer counts what's listed of what's covered. `WeatherCell.active` takes in the cells such digests show out of season.
- [x] Preview today's email and send a test from the Alerts page, for every user (a test goes whatever the frequency, at most one per 5 minutes). *(The preview is an optional Inertia prop, built only when asked for.)*
- [x] Sent each morning after the 5 am refresh, to users with the digest on and at least one active field; unsubscribe link and `List-Unsubscribe` header. *(`DailyDigestJob` at 6 am Central; one-click `List-Unsubscribe-Post`; the link's GET only shows a button.)*
- [x] SPF/DKIM check (Q6): Ben, on staging. *(Done: SPF and DKIM pass on staging; production sends through SES with DKIM, Q6.)*
- [x] Admin preview: "what would be sent today" for any user. *(Admin user page → "Preview today's daily email".)*
- **Exit:** staging sends correct digests for test fields across simulated scenarios (rain refill, sudden heat, planned irrigation pushing back "Irrigate by").

---

## Landing page and documentation (was Phase 6.5)

Decided 2026-10-05 (Ben): replace the legacy PDF user guide with documentation in the app, and greet signed-out visitors with what WISP is instead of a sign-in form. Brought forward from Phase 8.

- [x] **Landing page** at `/` for signed-out visitors (signed in, `/` stays the dashboard): what WISP is and who it's for, how it works in a few steps (weather → water balance → when and how much to irrigate), what you enter, and sign-up / sign-in buttons. Its text is the introduction of the About page, shared rather than copied. *(`PagesController`, `Pages/Home`; `lib/docs/Introduction.svelte`.)*
- [x] **About page** (`/about`, public, in the nav after Setup; signed out, the nav shows only About with sign-in and sign-up buttons). Sections, each with an anchor:
  - Introduction (shared with the landing page).
  - How WISP works: the water balance (§5) in plain words; weather from Open-Meteo, the forecast and its scenarios; statuses and "Irrigate by".
  - Getting started: account, operations and members, farms → pivots → fields → plantings, quick setup, copying last season.
  - Day to day: dashboard, daily entry, field groups, the field page (grid, planned irrigation, chart, weather), the daily email (Alerts).
  - Ground-truthing: which readings matter and how often (`lib/guidance.ts`): soil moisture weekly, sensor depths, percent cover or LAI, rain gauges.
  - Crops: a table from the `plants` table: default root zone depth, canopy methods (percent cover; LAI with the growth curve or with readings only), suggested sensor depths, with the shared defaults (MAD 50%, season dates) noted.
  - Glossary: every entry in `lib/glossary.ts`, each with an anchor the tooltips can link to.
  - Credits and contact: UW-Madison Vegetable Entomology Lab, agweather@cals.wisc.edu.
  *(`Pages/About`; the crop table from `plants`, reading advice from `lib/guidance.ts`, glossary from `lib/glossary.ts`, so they follow the app.)*
- [~] Wording reviewed by Ben (agronomy, contact details). *(Folded into one wording review before the beta: Phase 8 D. Claude's review after G.6 and G.11 is done, 2026-11-12.)*
- **Later (Phase 8):** screenshots, a printable version, the methods detail (equations from §5) for agronomists, and a "More in the guide" link from each glossary tooltip.

---

## Field rain setting and season details (was Phase 6.6)

Decided 2026-10-07 (Ben): some growers want the balance to use only the rain they enter, field by field. A per-field setting (Q7 addendum, §4 precedence), a "season details" card with gauge-vs-model statistics, entered rain on the precipitation chart, and two chart fixes.

**A. Chart fixes** (independent; can land first)
- [x] Snowfall and snow depth appear in the precipitation legend only when the days *in view* have some (`shownSeries` checked the whole season, so April snow put them in an October legend). *(The series stay on the chart, for scrolling back; `legend.data` names only those with snow in view.)*
- [x] Crop ET on the ET chart continues through the forecast: the projection's `adj_et` (forecast et0 and projected canopy) is what it takes out of the soil. Update the chart's info text.

**B. Per-field rain setting**
- [x] `fields.use_model_precip` (nullable boolean); `Field#effective_use_model_precip` falls back to the group's. `DailyInputs` reads it, and uses modeled rain on days after today whatever the setting (it takes `today:`, passed through `PlantingBalance` from `PlantingStatus`). Check that `FieldStatuses` and `DailyDigest` preload what it reads.
- [x] Any member can change it (like other field settings); the group-level default stays owner-only (Q8).
- [x] `FieldSerializer`: the field's setting (the page takes the group's default from `auth.group`, the effective one from `summary.use_model_precip`); `fields#update` permits it. Specs: override both ways, NULL inherits, forecast rain kept after today, cross-tenant update. `legacy_engine_spec` unchanged (the default doesn't change).
- [x] **"No rain" projection** for entered-only fields: `PlantingStatus` runs the balance over the projection's days with forecast rain set to zero (planned irrigation and entered rain kept), from today's AD with the same ET history as the ensemble. The projection gets a `dry_ad` per day and the summary a `dry_crossing`. On the field page: a dashed "If no rain falls" line on the soil-water chart, a column in the forecast table, and "Irrigate by … (… if no rain falls)". Status, "Irrigate by" and the digest follow the forecast case. *(`PlantingStatus#dry_projection`, `#dry_crossing`; the outlook's `dry` line, in `lib/outlook.ts` and `Outlook`, also goes in the digest.)*
- [x] Wording elsewhere: the operation page says fields can override its setting; daily entry doesn't show the "model" placeholder for entered-only fields; Setup marks entered-only fields; the field page's summary card says "Rain: only your entries · change" (linking to the setting). *(The setting is in a "Field settings" card at the bottom of the field page for now; part D adds the statistics to it.)*

**C. Entered rain on the field page's precipitation chart** (the pivot page's chart is unchanged)
- [x] `weatherPanels(units, { fieldRain })`, from `days` and `forecast_days`: an entered rain bar where there's an entry, with the modeled precipitation as a hollow, dashed bar behind it (the soil-water chart's style); for entered-only fields every modeled bar not used by the balance is hollow. The lower panel gets two running totals: modeled, and used by the balance. The section intro and the chart's info text say so. vitest for overrides, entered-only and no `fieldRain`. *(Entered rain is a bar beside the model's stack, like snowfall, rather than over it; the tooltip marks outlined amounts "not used".)*

**D. Season details and settings card** (at the bottom of the field page, after the weather)
- [x] The rain setting: operation default (named) / modeled, replaced by my entries / only rain I enter. Saving reloads the season.
- [x] Statistics through today, computed in the browser from `days` (`lib/seasonStats.ts`, pure and unit tested):
  - Entered rain: total, readings, days with rain. Modeled rain: total, days with rain (≥ 0.01″, measurable). For entered-only fields, the modeled rain days and total the balance left out.
  - Irrigation: total, days, typical interval (median days between irrigations), typical amount (median).
  - Deep drainage: season total.
  - Gauge vs model, by day: both rained; you entered rain the model didn't have; you entered 0 where the model had rain; model rain with no reading (not counted as a disagreement: no reading may mean no rain or no check). On days both rained: how often they disagree (by more than the larger of 0.1″ and 25%), the typical adjustment (median entered − modeled), and the ratio of the totals.
- [x] The summary card's "your gauge read … the model …" sentence links to the card. A glossary entry for the rain setting; guidance on when to choose entered-only (a gauge read every day it rains). *(Glossary `entered_rain_only`; the About page's Weather section and its rain advice.)*
- [x] Playwright: switch a field to entered-only, see the badge, totals and dry line change, switch back.
- **Exit:** switching a demo field to entered-only and back restores the same balance; its projection shows both cases; the precipitation chart and the details card agree with the daily grid.
