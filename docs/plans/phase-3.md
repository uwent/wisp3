# Phase 3: Weather

*A record of the build, frozen when it was folded out of `PLAN.md` on 2026-11-22: it says what was planned and done at the time, and later work may have changed or replaced it. For how the app works now, see [docs/architecture.md](../architecture.md) and [docs/engine.md](../engine.md); for why, [docs/decisions.md](../decisions.md). Section numbers (§) refer to the original design ([design.md](design.md)), except §2 and §15, now [docs/decisions.md](../decisions.md), and §9, now [docs/legacy-audit.md](../legacy-audit.md).*

- [x] `Weather::OpenMeteo` client (free / customer hosts, key optional), rate limiter, hourly → daily aggregation and unit conversion; WebMock specs from recorded responses.
- [x] Cells on the O1280 grid, `weather_days`, `weather_forecasts`; refresh, finalize, backfill and prune jobs on recurring schedules. `PlantingBalance` reads stored weather.
- [x] Daily and cumulative GDD from tmax/tmin (`Weather::DegreeDays`, base 50 °F / cap 86 °F), groundwork for Q2 option C.
- [x] Admin weather-status page (`/admin/weather`; admins only), with "Refresh now".
- [x] **AgWeather vs Open-Meteo comparison report** (§8.4, `docs/weather-comparison.md`); model chosen: NBM, then best_match.
- [x] Verified locally on the free API: every demo pivot has season-to-date data and a current forecast. Deployed to staging with the commercial key in its credentials (2026-10-03); the local `.env` key check is in TODO.md.
- **Exit:** every pivot in the demo seed data has season-to-date data and a current forecast; comparison report written and decision recorded.
