# Phase 5: Forecast projection

*A record of the build, frozen when it was folded out of `PLAN.md` on 2026-11-22: it says what was planned and done at the time, and later work may have changed or replaced it. For how the app works now, see [docs/architecture.md](../architecture.md) and [docs/engine.md](../engine.md); for why, [docs/decisions.md](../decisions.md). Section numbers (§) refer to the original design ([design.md](design.md)), except §2 and §15, now [docs/decisions.md](../decisions.md), and §9, now [docs/legacy-audit.md](../legacy-audit.md).*

- [x] Deterministic projection through the 16-day forecast. *(Today from the forecast too; §6 "As built".)*
- [x] Ensemble spike (et0 per member?), then the ensemble runner, P10/P50/P90 band, crossing probability. *(Yes for GFS, 31 members; `EnsembleProjection`.)*
- [x] Planned irrigation (what-if) and recommended irrigation amount and timing. *("Irrigate by" with the refill amount and the share of forecast scenarios that agree, on the field page and dashboard cards; the dashboard sparkline continues dashed through the forecast.)*
- **Exit:** the chart shows observed → forecast → band; adding a planned irrigation updates the projection in under 300 ms.
