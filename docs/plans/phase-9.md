# Phase 9: polish before grower feedback

From the 2026-11-21 review (four reviewers over the backend, services, pages and maps, plus a walk through a grower's season), with Phase 9's open items from `PLAN.md` moved here. Work top to bottom: each section is in priority order, and so are the items in it. Tick items as they land, with the date and where the code went; `PLAN.md` keeps the decisions and the handoff, this file the work.

New plans for later phases go in this folder (`docs/plans/`), one file each, rather than at the end of `PLAN.md`.

## 1. Fix before the announcement

Bugs a wave of new growers would hit, or that the announcement's traffic would make worse.

- [ ] **Sign-in mail waits behind long jobs.** `config/queue.yml` has one worker with 3 threads for every queue; `AnnouncementJob` sleeps between emails (10+ minutes for 3,000), `DailyDigestJob` runs every user in one job, and the weather jobs sleep in `Weather::RateLimiter` and retries. During a send, a new grower's sign-in code (`SecretMailDeliveryJob`) can wait out its 15 minutes. Give mail (`default`, `mailers`) a worker of its own and put announcements on a bulk queue.
- [ ] **No limit on a season's length.** `Planting#dates_in_order` and `dateProblems` (`lib/plantings.ts`) check only the dates' order. A season start typed as 2016 backfills ten years of the cell's weather (`WeatherCell#backfill_start`) and runs a 3,800-day balance on every page load; a harvest year typo blocks next season through the overlap check. Harvest within about a year of the season start, emergence within it; both copies together.
- [ ] **The planting form hides some server errors.** `PlantingForm` shows errors only for keys it names: `partial` (a plot with its own entries switched to Whole field), `et_method`, `canopy_curve_key` and `canopy_interpolation` come back unshown (the settings section opens, empty).
- [ ] **Typed values dropped without asking.** The irrigation form on a system's page (`Pivots/Show`: leaving, the Season menu, another row's Edit), "Add the next planting" in `PlantingDialog` (it has `leave()` already), and the Settings and operation (`Groups/Show`) forms, against the rule in CLAUDE.md (`confirmUnsavedChanges`).
- [ ] **Leaving Alerts bounces back.** `Alerts/Show` flushes a pending save in `onDestroy` with `router.patch`, after the next page has shown; the controller redirects to Alerts, so Inertia goes back there.
- [ ] **The outline import's soil survey skips rows.** `surveyNewRows` (`Setup/ImportOutlines`) returns while a run is going, and the run carries on with its old index: rows changed behind it, or all of a new file's or name column's rows before it, are saved with the default soil and no suggestion. Rerun from the start when called mid-run.
- [ ] **Exports name a past season's current system.** `PlantingCsv` and `SeasonReportCsv` read `field.pivot`, not `planting.system` (G.14 part 7's rule): a field moved to another system files its earlier seasons' irrigation, zone and header under the new one.
- [ ] **The example farm repeats every planting's queries.** In `as_of` mode `PlantingStatus` runs its own `DailyInputs.preload` per planting, ignoring the one `FieldStatuses.for` made (about four queries a planting on `/example`'s dashboard and map, where the announcement sends people). Pass the preloaded records with `as_of:`.

## 2. Cheap workflow wins

Small changes that head off the first confusions of a grower's first season.

- [ ] **Which day this morning's rain goes on.** Rain gauges are read in the morning and the reading is mostly yesterday's rain; daily entry opens on today with no word about it. A hint by the date ("Read your gauge this morning? That rain fell yesterday"), and opening on yesterday before noon, or a "Yesterday" button beside the date. Decide which with Ben.
- [ ] **"Did you irrigate?"** A planting that has read "Irrigate now" for two days or more with no irrigation entered says so on its card and page, linking to daily entry for those days: a grower who irrigated and didn't enter it otherwise sees the model "wrong" and stops trusting it. The digest's line for it links to daily entry for yesterday.
- [ ] **A home-screen icon.** A web app manifest (name, icons, `display: standalone`, theme colors) and an Apple touch icon, so "Add to Home Screen" on a phone gives WISP's icon and opens without the browser's bars. No offline work (that's PWA daily entry, After launch).

## 3. Smaller bugs

- [ ] **Admin weather reads the ensemble as the forecast.** `WeatherCellStatus`'s `DISTINCT ON` has no `kind`, so it shows the ensemble's issue time and a blank "through", and loads every cell's 31-member payload; it also runs two queries per cell. `WeatherForecast.deterministic.latest_by_cell`, and the season counts grouped. Its spec creates only a deterministic forecast.
- [ ] **A zone's earlier-season systems** (`WeatherZone.find`) select `pivots.id` (the field's current system) where it means `plantings.pivot_id`.
- [ ] **A failed basemap switch can't be retried** on the outline pages (`OutlineMap`, `ImportMap` set `basemap` before `setBasemap` and never put it back; `OutlineMap` restarts terra-draw on the timeout too). Goes away with the one basemap switcher (section 4).
- [ ] **Last-owner race:** two owners demoting each other at once can leave an operation with no owner (`MembershipsController`, `Membership`): lock the group, then check and write.
- [ ] **Adding a member while impersonating** emails a third party in the grower's name: `forbid_while_impersonating` on `MembershipsController#create`.
- [ ] **Queries per row that grow with sign-ups:** run-hours irrigation on the planting and system pages (`irrigated_acres` per irrigation, about 3 queries each), `WeatherCell.digest_cell_ids` (two per digest user, every weather refresh), the admin user page's cuttings and irrigation groups.
- [ ] **`Date.current` on page paths** where CLAUDE.md says `Current.today`: `DailyEntriesController#show`, `DailyEntryPage`, `SetupController`, `PlantingsController#travel_dates`, `QuickSetupsController`, `PagesController`, `SeasonReportCsv`'s default. Harmless today; wrong the day one is opened to the example farm or time travel.
- [ ] **CSV escaping twins disagree:** `CsvExport#text` quotes a grower's text like `-5`, `lib/csv.ts` exempts numbers. One rule for both.
- [ ] **The digest's order** repeats `FieldStatuses.urgency` without its `weather_pending?` case.
- [ ] Two pages missing from the accessibility scan: Admin → a user's digest, and an announcement (`e2e/session.ts`).
- [ ] **An intermittent contrast finding on the shape page** (moved from PLAN.md; `/fields/:id/outline`, about one full run in six, not reproduced since the tools' wait): the scan's message names the elements and why, so the next CI failure says which. Then fix it or wait for it in `scan`.

## 4. Simplifications

Before the new features below, so they're built on the shared pieces (the week grid and percent timer both reuse the irrigation amount inputs).

- [ ] **One irrigation amount input:** `canUseHours` and the inches / run hours pair (with its blank hidden input) are written twice, in `Pivots/Show` and `DailyEntries/Show`: `lib/irrigation.ts` and an `IrrigationAmount` component.
- [ ] **One basemap switcher** for `OutlineMap`, `ImportMap`, `OverviewMap` and `PivotMap` (state, own sources, re-adding images, reverting on failure), in `lib/map/basemaps.ts`.
- [ ] **The weather panels' unused per-field options** (`field`, `cropEt`, `fieldRain`, hollow series and their tooltip text in `lib/charts/weatherCharts.ts`; used only by tests since the panels left the planting page): about 120 lines.
- [ ] **Small shared helpers:** the user's units (`$derived(unitsFor(page.props.auth.user?.unit_system))` in 17 files); one plural helper (`count` in `lib/dailyEntry.ts`, about six copies); saved browser settings (`lib/storage.ts`, four copies of the try/catch); one ISO date param parser in `InertiaController` (four); `send_csv` (five); the soil types and planting form's reference props (`SoilTypeSerializer...` seven times); outline file reading on both outline pages (`read.ts`); the map label paint beside `LABEL_FONT` (six).
- [ ] **The field and planting pages' preload** (the same long `includes`, and `keep_current` with `updating_ids`): a `Field` scope and a helper.
- [ ] **Import map colors from the tokens** (`ImportMap`'s `COLORS`, the legend's hex classes in `ImportOutlines`), the legend inside `ImportMap`.
- [ ] **Dead and stale:** `Group#example?`, `Pivot#point?`, `Planting.in_season` (spec only), `:group` in `PlantingStatus#totals`, `EnsembleProjection`'s `start_ad` comment, the misplaced CSV comment in `weatherCharts.ts`, `Weather::Normals` building its own day of year (`WeatherNormal.day_of_year`), `exceeds_field_area` serialized for every planting but read on one page, the no-op `e()` and `error()` helpers, a doubled `readPalette()` in `OverviewMap`.

## 5. Dashboard list view

Ben, 2026-11-21: a compact view, for phones above all. The map's `compact` card drops only last rain and irrigation, which saves little; a list does more.

- [ ] **Cards | List** in the dashboard's header, remembered in this browser (a phone can keep List, a desktop Cards), at any width. A list row per field: its name, crop, status badge and the outlook's headline ("Irrigate by Thu · about 0.6 in refills it"), readings due as a small "2 due"; the row links as the card does. Left out: moisture and AD, the sparkline, last rain and irrigation, the task list. A field of plots: one row per planting under the field's name. Systems stay as headings, lighter than the cards' boxes.
- [ ] **"Needs water first"**: the list (and cards) ordered by urgency across systems instead of by farm and system (`FieldStatuses.urgency` / `summaryUrgency`), each row naming its system.
- [ ] **Status counts as filters:** the counts above the cards become toggles that show only fields at that status.

## 6. A week grid for catching up

A grower back from three days away, or one who enters once a week, has to step through daily entry a date at a time.

- [ ] **Daily entry's week view**: a Day | Week switch; the week is a grid of the systems (irrigation, inches or run hours) and the rain rows (irrigation groups and systems, filling their fields as daily entry does) by the 7 days to the date chosen, one Save for the lot. Fields, plots and cover readings stay in the day view (the week's rows link to it). Uses `EditableCell`'s grid (one tab stop, arrow keys) or plain inputs with one form; decide with a sketch. The save reuses `DailyEntriesController#update` per date or a `dates` form of it, checked in the same `:entry` context.

## 7. Setup speed-ups

Moved from PLAN.md's Phase 9 (Quality of life). Setup is the first thing every new grower does this winter.

- [ ] **The same crop on several fields:** after saving a planting, "Plant this on other fields too" with a checklist of the system's fields without one that season (same crop, dates and settings), for first-time setup and next season.
- [ ] **Keep an outline file's shapes while setting up:** the field shape page reads a file and uses one shape, so outlining twelve fields one at a time means reading the same file twelve times. Keep the last file's shapes in the browser (IndexedDB, per operation, until the tab's session ends or a day passes) and offer them on the next field's shape page ("Shapes from Fields.zip: pick one"), the one that holds the field's system or matches its name first (`lib/outlines/matching.ts`), with those already used marked. Link to Setup's import for doing them all at once.
- [ ] **Duplicate an irrigation system** in Setup (a farm of similar pivots).
- [ ] **Daily entry:** offer yesterday's amounts for systems that ran yesterday, as a placeholder to accept, not a value.
- [ ] **Remember the last choices** in setup forms for the session (soil, crop, emergence date), as suggestions.

## 8. A center pivot's percent timer

How pivot operators set what they apply. A center pivot's panel sets its speed as a percent: at 100% the end tower runs all the time and the pivot makes its fastest circle, putting on the least water; at 50% it runs half of each minute, so a circle takes twice as long and puts on twice the depth. Growers know their pivot by its sprinkler chart or a rule of thumb ("0.2 in at 100%", or "a circle takes 18 hours at 100%"), and think "I ran North at 40%", not in inches or hours. Depth = depth at 100% × 100 ÷ percent, for a whole circle.

- [ ] **On the system:** a center pivot's (and a linear's) hours for a full circle (or pass) at 100%, optional, in Equipment. With the pump capacity WISP already has, that gives the depth at 100% through the run hours conversion (`PivotIrrigation#irrigated_acres`), so nothing else is asked; or the depth at 100% straight from the chart, if growers know that better (ask the beta which).
- [ ] **In daily entry and on the system page:** a third choice beside inches and run hours, "Percent timer", with the circles or fraction run (default one), shown and stored as run hours (circle hours × 100 ÷ percent × circles) so the balance and exports need nothing new; the entry shows the inches it comes to. Check the conversion against a real chart with a grower first.

## 9. More on the dashboard

- [ ] **Log irrigation from the dashboard:** on each system's section, "Log irrigation" opening a small dialog (date, defaulting to today; amount; fields applied to) that saves through daily entry's controller, for the common case of one system that ran.
- [ ] **A rain forecast strip:** the operation's weather zones' next days of rain (chance and amount, from `ForecastDays`), above the cards, so "hold off, rain Thursday" is seen beside the outlooks it already shapes. One strip per zone when the operation spans several, named as on the Weather tab.
