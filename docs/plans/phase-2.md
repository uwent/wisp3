# Phase 2: Domain and engine

*A record of the build, frozen when it was folded out of `PLAN.md` on 2026-11-22: it says what was planned and done at the time, and later work may have changed or replaced it. For how the app works now, see [docs/architecture.md](../architecture.md) and [docs/engine.md](../engine.md); for why, [docs/decisions.md](../decisions.md). Section numbers (§) refer to the original design ([design.md](design.md)), except §2 and §15, now [docs/decisions.md](../decisions.md), and §9, now [docs/legacy-audit.md](../legacy-audit.md).*

- [x] Migrations and models for §4 (weather tables wait for Phase 3); plants and soil types in `db/reference/*.yml`, loaded by `ReferenceData` on `db:seed` and on every deploy.
- [x] `WaterBalance`, `Canopy`/`CanopyModel`, `CropEt` (`app/services`) with the §5 fixes and unit tests; property tests for AD bounds and water conservation.
- [x] `DailyInputs` resolver (precedence and provenance, including pivot irrigation and run hours); `PlantingBalance` runs a planting's season from the database.
- [x] Golden test harness: `spec/support/legacy_engine.rb` reproduces legacy with each fix switchable (with all fixes it equals `WaterBalance`); `spec/golden` checks each fixture field and attributes every differing day to a fix. Export script `script/legacy/export_golden_fixtures.rb` (checked against the local legacy dev DB, whose 2026 fields have no weather). *(The golden fixtures, `spec/golden` and the export script were retired in `5533ff4` once all 30 fields passed; `legacy_engine_spec` remains.)*
- [x] Golden tests passed on 30 fields exported from legacy production (2026-10-03), then retired along with the legacy data (no legacy data is kept in the repo); `LegacyEngine` and its synthetic spec stay as the record of what each fix changes. 12 have weather; 18 never received reference ET (AD flat all season) and pass trivially. Every differing day traces to C2, C3, C4, C7, C19, or C7+C4 together. Findings:
  - **C19** (new): stale ET on moisture-reading days.
  - **C7 dominates**: active fields are missing reference ET on 80–200 of 243 days, so legacy ran much of the season on self-fed gap fill. Open-Meteo (Phase 3) should make gaps rare; the new engine stops gap-filling after 7 days instead.
- [x] `bin/rails demo:seed`: a demo account with 3 farms, 13 fields (a pivot with 8 fields, a double crop), both ET methods, pivot irrigation in inches, run hours and for a subset, a soil moisture reading and a field group.
- **Exit:** golden tests pass for every fixture field, and each difference traces to a listed fix.
