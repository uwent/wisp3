# Phase 6.6: Field rain setting and season details

*A record of the build, frozen when it was folded out of `PLAN.md` on 2026-11-22: it says what was planned and done at the time, and later work may have changed or replaced it. For how the app works now, see [docs/architecture.md](../architecture.md) and [docs/engine.md](../engine.md); for why, [docs/decisions.md](../decisions.md). Section numbers (§) refer to the original design ([design.md](design.md)), except §2 and §15, now [docs/decisions.md](../decisions.md), and §9, now [docs/legacy-audit.md](../legacy-audit.md).*

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
