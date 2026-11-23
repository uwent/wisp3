# Phase 2: Engine and weather

October 3–4, 2026. The water balance ported from legacy and checked against it, Open-Meteo weather by grid cell with the AgWeather comparison, and the forecast projection with its ensemble.

*A record of the build, frozen on 2026-11-22. It was planned and written in phases 0–9, regrouped here by theme; each section's heading gives its old number, and [README.md](README.md) maps every old phase and section ID to its place. Cross-references inside the text ("G.14 part 7", "Phase 6.7", "§5.3") use the old numbers. Later work may have changed what's described: for how the app works now, see [docs/architecture.md](../architecture.md) and [docs/engine.md](../engine.md); for why, [docs/decisions.md](../decisions.md).*

## Domain and engine (was Phase 2)

- [x] Migrations and models for §4 (weather tables wait for Phase 3); plants and soil types in `db/reference/*.yml`, loaded by `ReferenceData` on `db:seed` and on every deploy.
- [x] `WaterBalance`, `Canopy`/`CanopyModel`, `CropEt` (`app/services`) with the §5 fixes and unit tests; property tests for AD bounds and water conservation.
- [x] `DailyInputs` resolver (precedence and provenance, including pivot irrigation and run hours); `PlantingBalance` runs a planting's season from the database.
- [x] Golden test harness: `spec/support/legacy_engine.rb` reproduces legacy with each fix switchable (with all fixes it equals `WaterBalance`); `spec/golden` checks each fixture field and attributes every differing day to a fix. Export script `script/legacy/export_golden_fixtures.rb` (checked against the local legacy dev DB, whose 2026 fields have no weather). *(The golden fixtures, `spec/golden` and the export script were retired in `5533ff4` once all 30 fields passed; `legacy_engine_spec` remains.)*
- [x] Golden tests passed on 30 fields exported from legacy production (2026-10-03), then retired along with the legacy data (no legacy data is kept in the repo); `LegacyEngine` and its synthetic spec stay as the record of what each fix changes. 12 have weather; 18 never received reference ET (AD flat all season) and pass trivially. Every differing day traces to C2, C3, C4, C7, C19, or C7+C4 together. Findings:
  - **C19** (new): stale ET on moisture-reading days.
  - **C7 dominates**: active fields are missing reference ET on 80–200 of 243 days, so legacy ran much of the season on self-fed gap fill. Open-Meteo (Phase 3) should make gaps rare; the new engine stops gap-filling after 7 days instead.
- [x] `bin/rails demo:seed`: a demo account with 3 farms, 13 fields (a pivot with 8 fields, a double crop), both ET methods, pivot irrigation in inches, run hours and for a subset, a soil moisture reading and a field group.
- **Exit:** golden tests pass for every fixture field, and each difference traces to a listed fix.

---

## Weather (was Phase 3)

- [x] `Weather::OpenMeteo` client (free / customer hosts, key optional), rate limiter, hourly → daily aggregation and unit conversion; WebMock specs from recorded responses.
- [x] Cells on the O1280 grid, `weather_days`, `weather_forecasts`; refresh, finalize, backfill and prune jobs on recurring schedules. `PlantingBalance` reads stored weather.
- [x] Daily and cumulative GDD from tmax/tmin (`Weather::DegreeDays`, base 50 °F / cap 86 °F), groundwork for Q2 option C.
- [x] Admin weather-status page (`/admin/weather`; admins only), with "Refresh now".
- [x] **AgWeather vs Open-Meteo comparison report** (§8.4, `docs/weather-comparison.md`); model chosen: NBM, then best_match.
- [x] Verified locally on the free API: every demo pivot has season-to-date data and a current forecast. Deployed to staging with the commercial key in its credentials (2026-10-03); the local `.env` key check is in TODO.md.
- **Exit:** every pivot in the demo seed data has season-to-date data and a current forecast; comparison report written and decision recorded.

---

## Forecast projection (was Phase 5)

- [x] Deterministic projection through the 16-day forecast. *(Today from the forecast too; §6 "As built".)*
- [x] Ensemble spike (et0 per member?), then the ensemble runner, P10/P50/P90 band, crossing probability. *(Yes for GFS, 31 members; `EnsembleProjection`.)*
- [x] Planned irrigation (what-if) and recommended irrigation amount and timing. *("Irrigate by" with the refill amount and the share of forecast scenarios that agree, on the field page and dashboard cards; the dashboard sparkline continues dashed through the forecast.)*
- **Exit:** the chart shows observed → forecast → band; adding a planned irrigation updates the projection in under 300 ms.
