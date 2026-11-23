# WISP 3

A rewrite of the Wisconsin Irrigation Scheduling Program (WISP), replacing the legacy app at `../wisp`. It launched on 2026-11-19 at `https://wisp.cals.wisc.edu`; the 2026–27 winter is the beta, ahead of the 2027 season.

This file is where things stand and what's next. Rewrite the handoff at the end of each session, and keep the backlog current.

## Where the docs are

| Doc | Holds |
|---|---|
| [docs/architecture.md](docs/architecture.md) | How each area of the app works now. Kept current as the code changes |
| [docs/engine.md](docs/engine.md) | The water balance and the projection, as they work now |
| [docs/decisions.md](docs/decisions.md) | Why: the recorded decisions (D1–D15) and settled questions (Q1–Q11). A new decision takes the next D number |
| [docs/legacy-audit.md](docs/legacy-audit.md) | Legacy WISP's bugs and what WISP 3 does instead (S, C and A IDs); a deliberate change from legacy takes the next C number and a switch in `LegacyEngine` |
| [docs/plans/](docs/plans/) | The build's record, frozen: the original design (`design.md`) and the work in eight phases by theme, from groundwork to the polish before grower feedback (its README maps the old phase numbers). A new piece of work that needs a plan gets its own file here |
| [DEVELOPMENT.md](DEVELOPMENT.md), [docs/deployment.md](docs/deployment.md) | Setting up a machine and the commands; staging and production |
| [TODO.md](TODO.md) | What only Ben can do |

Code comments say what the code is for; they cite a doc only for a decision or legacy ID (`D15`, `C22`, `Q10`) or a design doc, never a phase.

## Handoff (2026-11-23)

**Where things stand.** Production is `https://wisp.cals.wisc.edu` (EC2 t3.medium and RDS db.t4g.small, mail through SES); staging is `dev.wisp.cals.wisc.edu`. Legacy is at `https://old.wisp.cals.wisc.edu` until it's deleted on December 31, 2027. Growers set up their operations over the winter; Ben sends the announcement email and holds a training session. Production runs `main` as of `dae08af`; `main` has moved on with C22–C25, the rainfall setting's move, the admin tools, the polish before grower feedback (`docs/plans/8-polish.md`), D15, the outline import's rework, D16 and the Map tab's weather zones. The planned work is done; what remains of launch preparation is Ben's (TODO.md: the screen reader walkthrough, the wording review, the RDS restore test).

**Latest (2026-11-23): weather zones on the Map tab** (`docs/architecture.md`, Maps). The zones of the operation's systems (only those cells are kept current) are a layer, on by default: each grid cell's box as thin sky-blue lines (`ZONE_STYLE` in `lib/map/zones.ts`, for trying colors). With nothing else under the pointer the hover label is the zone's last 7 days and next 7 (rain, reference ET, highs and lows; `lib/weatherSummary.ts`, worded as the digest's `digest_weather`, a pair that changes together); a click opens the zone's panel with the week ahead and a link to its weather page; a system's panel shows its zone's lines. After the build, the map code was cleaned up: the three map panels share `MapPanel` (`data-map-panel`), every map's hover label is `MapHover` + `HoverLabel`, `showLayers` is in `lib/map/maplibre.ts`, and the Map tab's source and layer ids are named once (`PIVOT_IDS`, `GROUP_IDS`, `FIELD_IDS`, `setFieldColors`).

**Earlier this session (2026-11-22 to 23):** Ben's open choices were settled (below), and Setup's outline import was reworked (`docs/architecture.md`, Field outlines): shapes match fields by overlap as well as name, cards (Skip | New field | Update field) only for shapes going somewhere, the rest skipped in a searchable table, overlaps with existing fields or other shapes warned of, dropdowns nearest first, the map beside the cards, at most a file's first 1,000 shapes, and the geometry made fast enough for a county file (shapes kept out of deep `$state`; a 38-shape file took 6 s to show, now well under a second). Setup also lists saved fields whose shapes overlap. Then (2026-11-23) the import's map got the saved fields as a layer, a symbology by priority (the file's shapes filled by where each goes, saved fields outlined, systems the only blue, drawn on top), hover labels and an overlaid legend; a shape within 3 m of its matched field's outline starts skipped; the kept file moved to localStorage for a week and is matched as the page opens; and, in place of the import making irrigation systems (D16), the system form's map shows a kept file's shapes not yet imported, to set the systems up on before importing. Daily entry no longer remembers Day or Week. Before that, the docs were reorganized (`PLAN.md` as status; decisions, the legacy audit, the plans and the engine in `docs/`).

**Next:**
1. **Deploy `main`** (`bin/production deploy`) before the announcement: C22–C25 and the About page, the rainfall setting's migration, the admin tools (a migration), the polish before grower feedback (`docs/plans/8-polish.md`), D15's two migrations (the second reports any irrigation it couldn't move), and the Map tab's weather zones (no migration).
2. **Legacy:** commit, push and `cap production deploy` the retirement changes; take the archive `pg_dump` before it's deleted (TODO.md).
3. **Ben** (TODO.md): the RDS restore test; the announcement email and training session; GA's settings and the privacy wording; the wording review (C21's included) and the screen reader walkthrough.
4. **Code during the winter beta:** Wisconsin season lengths for the warm-climate crops (needs extension sources; `docs/plans/4-crop-and-weather-science.md`, Season end dates); whatever the beta and training session turn up.

## Ben's open choices

None at the moment.

Settled 2026-11-22 (from `docs/plans/8-polish.md`): Setup's import gives cards only to matched and new shapes, the rest skipped in one searchable table with Add, matches shapes to fields by overlap as well as name, warns of overlaps, and sits beside its map (done); the Day | Week choice isn't remembered (done: no redirect, the nav opens the day); the phone bar stays the branding bar's red (the manifest's `theme_color` now matches); Duplicate stays open to any member, as Add is; Needs water first stays on cards and the list.

## Beta feedback prompts

Questions to put to growers during the winter beta and the training session.

- Check the irrigation calculator against a real sprinkler chart.
- Do they know their pivot's depth at 100%, or its circle hours?

## Backlog

After launch, roughly in order of value; check with the beta before building most of it. Phase references use the old numbers, which `docs/plans/README.md` maps; § numbers point into `docs/plans/design.md`.

- Forecast accuracy tracking (stored forecasts vs finalized weather), from the daily archive started in Phase 8 E: by lead time, for ET0 and rain, and whether the ensemble's spread covers what happened. Part of the evaluation pages below.
- **Model evaluation and usage insights (admin pages; Ben, 2026-11-10; ideas, not designed).** After a season of data, an admin section that shows how WISP's models compare with what happened and with what growers entered, as anonymised statistics and charts, and how WISP is used:
  - **Forecasts:** the archived forecasts (Phase 8 E) against the finalized weather, by lead time, for ET0 and rain; the ensemble band's coverage (how often the outcome fell inside P10–P90), which decides Q10's revisit (ratio scaling vs per member).
  - **Canopy:** each crop's default curve and fitted curves (`CanopyCurve`, `CanopyFit`) against the percent cover and LAI readings growers entered, by crop and days since emergence; what `Canopy#check` flagged; feeds the curve refits under "Canopy and LAI readings in the 2027 season".
  - **Water balance:** modeled AD against entered soil moisture readings where fields have them (the drawdown check of the percent-cover refit below).
  - **Corrections from the evidence:** tools to apply what the comparisons show, either one-time (a refit, recorded as a new table version with its evidence, like the weather corrections) or ongoing (a correction recomputed as data accumulates), each versioned and listed on the About page.
  - **Usage metrics, collected natively** (no third-party analytics): page views and active users by day, which pages and features are used (entries, setup, map layers, exports, time travel), sign-in methods, digest opens or clicks if measurable without tracking pixels, devices by screen size; stored in our database, aggregated, with no personal data beyond what the account already holds, and a retention limit. Decide what to count and the privacy wording (About page) before building.
  - Anonymised: no grower, farm or field names; groups below a minimum count left out; growers' consent as in Phase 6.7 A.2 where readings leave the account.
- PWA / offline-friendly daily entry.
- Validated LAI or canopy curves for more crops; sensor integrations; AgWeather v2 as the weather provider once it's deployed (D6's note), checked against the Wisconet stations and the Central Sands towers (`docs/et-validation/`) before switching.
- **Canopy and LAI readings in the 2027 season** (2026-11-10: the researchers contacted haven't replied, so the curves get checked against our own data). Before the season, pick a few cooperating fields (potato first, then field corn, sweet corn, soybean, snap bean) and a protocol: percent cover about weekly from emergence to vine kill or harvest, by photo (the Canopeo app, which measures green cover from a phone picture), and LAI where a ceptometer can be borrowed, with emergence and vine kill dates recorded. Growers' own WISP 3 readings add to it, with their consent and anonymised as in Phase 6.7 A.2. After the season, rerun the backtest (`docs/canopy/scripts/backtest.py`) and refit the curves, with a note in `docs/canopy/` and a changelog line on the About page. A potato LAI curve, if the data supports one, is the most valuable result (Q2).
- **Refit the percent-cover table (§5.4) against today's ET0** (Q9 and Q11: full-cover crop ET likely 10–20% low on corrected ET0, Phase 8 E step 8; step 1 done before the beta as C21, with FAO-56's Kc mid in place of Allen and Pereira's density coefficient; steps 2–3 stay here, now checking C21; Ben, 2026-10-31: no academic is available to refit it, so it has to be done computationally). Its slopes are crop ET over the old API's ET by cover (1.0 at 80% and above), and the old API's ET runs about 1.11 × station FAO-56 grass ET0 (April–October), so at full cover the table meant a Kc of about 1.1, near FAO-56's mid-season values (Table 12: potato 1.15, field corn 1.20, soybean 1.15). With corrected ET0 (1.03 × the stations') it gives about 1.03, 10–14% below those values (it was 3–8% below), so WISP may now under-count full-cover water use. Steps:
  1. Re-express the table against FAO-56 grass ET0 and compare it, band by band, with Allen and Pereira (2009)'s crop coefficient from fraction of ground cover and height (*Irrigation Science* 28: 17–34, doi:10.1007/s00271-009-0182-z: a density coefficient on FAO-56's basal Kcb per crop, plus FAO-56's dual-coefficient soil evaporation in place of the bare-soil steps). Published, per crop, and needs only cover (which WISP has) and crop height (a default per crop).
  2. Check both against measured ET: Wisconsin eddy-covariance records over irrigated crops (Central Sands potato and corn; ask the Kucharik lab and AmeriFlux; **full cover done 2026-11-19 in `docs/et-validation/`, D14: potato's coefficient 1.09–1.12 closure-corrected, C21's 1.15 kept; the whole season in `06-season.md`: soil evaporation at low cover and after vine kill, and early August, are where WISP 3 departs**), and WISP 3's own soil moisture readings once seasons accumulate (the drawdown between two readings with no rain or irrigation between them is crop ET; needs growers' consent and the anonymised extract of Phase 6.7).
  3. Pick a method per crop, with its error against the measurements, and replace `CropEt::PCT_COVER_COEFFICIENTS` or keep it with a scale, recorded as a D# with the evidence; a changelog line on the About page.

- **Deferred from earlier phases (2026-11-17 review of open items):**
  - The time travel archive replay (Phase 8 F), once the archive has a season.
  - All operations at once on the dashboard and map (G.8), if consultants ask.
  - The digest's weather zones named as on the Weather tab, and a dashboard line per zone (G.12).
  - The soil survey's available water capacity beside a soil type's defaults, as a check (Phase 7 F).
  - Announcements shown in the app (Phase 8 B), if still wanted (by email: Phase 9, Admin tools).
  - An onboarding tour, and the water balance's equations on the About page (Phase 8 D), if the beta asks.
  - Importing irrigation from FieldNET or Valley 365 exports (G), if the beta's large growers ask.
