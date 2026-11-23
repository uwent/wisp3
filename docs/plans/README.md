# Plans

The build's record, frozen on 2026-11-22: the original design ([design.md](design.md)) and the work in eight phases by theme, and the work planned since. The work was planned in phases 0–9, with sub-phases slotted in as work came up; the files regroup it, keeping each section's text, with its old number in its heading.

| Phase | Built | |
|---|---|---|
| [1. Groundwork](1-groundwork.md) | Oct 2–3 | Legacy hotfixes; the app's foundation |
| [2. Engine and weather](2-engine-and-weather.md) | Oct 3–4 | The balance, Open-Meteo, the projection |
| [3. The working app](3-working-app.md) | Oct 3–7 | Setup, the planting page, dashboard, daily entry, the digest, landing and About |
| [4. Crop and weather science](4-crop-and-weather-science.md) | Oct 15 – Nov 20 | Canopy curves, weather corrections, crops, crop ET |
| [5. Maps and field shapes](5-maps-and-field-shapes.md) | Oct 17 – Nov 13 | The map, pivot shapes, field outlines |
| [6. Operations, plantings and seasons](6-operations-plantings-seasons.md) | Nov 10–17 | Beta readiness: systems, plots, seasons, daily entry, the example farm, time travel |
| [7. Launch](7-launch.md) | Oct 22 – Nov 20 | Accessibility, admin, audit, the beta and launch, analytics |
| [8. Polish before grower feedback](8-polish.md) | Nov 21–22 | The review's fixes, the dashboard list, the week grid, D15 |
| [9. The irrigation system rename](9-irrigation-system-rename.md) | Nov 23 | `Pivot` → `IrrigationSystem` in code (D18) |

A new piece of work that needs a plan gets its own file here, ticked as it lands; when it's done, it's frozen like these, with what's still current moved into [architecture.md](../architecture.md) and [engine.md](../engine.md).

## Old numbers

Where each old phase and section went. Text in these files, [design.md](design.md) and the research notes may still cite the old numbers; § numbers are the design's. Sections of a phase that moved whole (Phase 6.7 A, Phase 7 F, …) are under that phase's heading.

| Old | Now in | Section |
|---|---|---|
| Phase 0 | [1-groundwork](1-groundwork.md) | Legacy housekeeping |
| Phase 1 | [1-groundwork](1-groundwork.md) | Foundation |
| Phase 2 | [2-engine-and-weather](2-engine-and-weather.md) | Domain and engine |
| Phase 3 | [2-engine-and-weather](2-engine-and-weather.md) | Weather |
| Phase 4 | [3-working-app](3-working-app.md) | Core UI |
| Phase 4.5 | [3-working-app](3-working-app.md) | Review fixes and polish |
| Phase 5 | [2-engine-and-weather](2-engine-and-weather.md) | Forecast projection |
| Phase 6 | [3-working-app](3-working-app.md) | Alerts |
| Phase 6.5 | [3-working-app](3-working-app.md) | Landing page and documentation |
| Phase 6.6 | [3-working-app](3-working-app.md) | Field rain setting and season details |
| Phase 6.7 | [4-crop-and-weather-science](4-crop-and-weather-science.md) | Crop canopy curves |
| Phase 7 | [5-maps-and-field-shapes](5-maps-and-field-shapes.md) | Map |
| Phase 8 | [7-launch](7-launch.md) | Getting ready to launch (Phase 8's plan) |
| Phase 8 A | [7-launch](7-launch.md) | Accessibility (WCAG 2.1 AA) |
| Phase 8 B | [7-launch](7-launch.md) | Admin: monitoring and impersonation |
| Phase 8 C | [7-launch](7-launch.md) | Performance check and code audit |
| Phase 8 D | [7-launch](7-launch.md) | Beta and launch |
| Phase 8 E | [4-crop-and-weather-science](4-crop-and-weather-science.md) | Weather corrections (D12, §8.5; before the beta) |
| Phase 8 F | [6-operations-plantings-seasons](6-operations-plantings-seasons.md) | Time travel on the field page (built 2026-11-10, except the archive replay) |
| Phase 8 G | [6-operations-plantings-seasons](6-operations-plantings-seasons.md) | Beta readiness (UX review, 2026-11-11) |
| Phase 8 G.1 | [6-operations-plantings-seasons](6-operations-plantings-seasons.md) | Quick fixes |
| Phase 8 G.2 | [4-crop-and-weather-science](4-crop-and-weather-science.md) | Season end dates |
| Phase 8 G.3 | [4-crop-and-weather-science](4-crop-and-weather-science.md) | Crops without a canopy curve |
| Phase 8 G.4 | [6-operations-plantings-seasons](6-operations-plantings-seasons.md) | Daily entry as the morning page |
| Phase 8 G.5 | [6-operations-plantings-seasons](6-operations-plantings-seasons.md) | Irrigation systems other than pivots |
| Phase 8 G.6 | [6-operations-plantings-seasons](6-operations-plantings-seasons.md) | Fewer things to decode |
| Phase 8 G.7 | [4-crop-and-weather-science](4-crop-and-weather-science.md) | Crops to add |
| Phase 8 G.8 | [6-operations-plantings-seasons](6-operations-plantings-seasons.md) | Operations, next season and an example farm |
| Phase 8 G.9 | [6-operations-plantings-seasons](6-operations-plantings-seasons.md) | Seasons and history |
| Phase 8 G.10 | [5-maps-and-field-shapes](5-maps-and-field-shapes.md) | Field boundaries (optional) |
| Phase 8 G.11 | [6-operations-plantings-seasons](6-operations-plantings-seasons.md) | Fields with several plantings |
| Phase 8 G.12 | [6-operations-plantings-seasons](6-operations-plantings-seasons.md) | A weather page |
| Phase 8 G.13 | [6-operations-plantings-seasons](6-operations-plantings-seasons.md) | Forms that explain themselves and don't lose edits |
| Phase 8 G.14 | [5-maps-and-field-shapes](5-maps-and-field-shapes.md) | Setup and the map, tidied after G.10 |
| Phase 8 G.15 | [6-operations-plantings-seasons](6-operations-plantings-seasons.md) | Review before merging `beta-readiness` (2026-11-17) |
| Phase 8 H | [7-launch](7-launch.md) | Analytics (approved and built 2026-11-17, merged to `main` the same day) |
| Phase 9 (before the review) | [7-launch](7-launch.md) | Refactors, browser tests and admin tools |
| Phase 9 | [8-polish](8-polish.md) | the whole file; sections 1–9 keep their numbers |
