# The water balance

How WISP 3 works out a planting's soil water, today and ahead. It's the checkbook method legacy WISP used, ported with fixes and given FAO-56's crop coefficients; the reasons are in [decisions.md](decisions.md) (D14 above all) and the deliberate changes from legacy in [legacy-audit.md](legacy-audit.md) (C IDs). The canopy that drives crop ET is in [architecture.md](architecture.md) (Canopy and soils), and the weather it runs on in the same doc (Weather).

The rules in [CLAUDE.md](../CLAUDE.md) hold here: the balance is recalculated on read and never stored; depths are inches; missing data is `nil`, never 0; it reads the planting's own soil, area and weather cell (copied from its field and system for the season), never the field's or system's.

## The pieces

| Piece | Does |
|---|---|
| `WaterBalance` | The balance itself, plain Ruby: `run(params, days) → [Result]`, plus `status` |
| `WaterBalance::Params` | A planting's static values (`Params.for(planting)`): soil, root zone, MAD, target, initial moisture, its crop (`Crop`) and soil evaporation's inputs |
| `DailyInputs` | Each day's rain, irrigation, ET0, soil moisture reading, wind and minimum RH, resolved from the grower's entries and the weather, each with its source |
| `Canopy` | Percent cover or LAI on each day (curves, readings, cuttings, vine kill) |
| `CropEt`, `SoilEvaporation` | Crop ET from ET0 and the canopy: FAO-56's dual crop coefficient (C22), or A3600's percent cover table |
| `PlantingBalance` | Puts those together for one planting from season start: `Canopy` + `DailyInputs` + `Params` → `WaterBalance.run` |
| `PlantingStatus` | What pages show: the season through today, today's status, the projection through the forecast, the ensemble's range, the crossing, totals |
| `EnsembleProjection` | The balance once per ensemble member, as percentiles and a chance of crossing |
| `FieldStatuses` | Many fields at once (dashboard, map, digest), with their inputs preloaded in a few queries |
| `LegacyEngine` (`spec/support/legacy_engine.rb`) | Legacy's algorithm with each fix as a switch, so `spec/services/legacy_engine_spec.rb` shows the port is faithful and every difference is a listed fix |

## Static values

Field capacity and wilting point are fractions (the planting's own, `nil` following its soil type), the root zone depth inches, MAD a fraction.

```
TAW         = (FC − PWP) × MRZD                 total available water
AD_max      = MAD × TAW                         AD at field capacity
AD_pwp      = −(1 − MAD) × TAW                  AD at the wilting point
pct_at_ad0  = (FC − AD_max / MRZD) × 100        soil moisture (%) at AD = 0, the irrigation point
target_in   = target_ad_pct / 100 × AD_max      (nil without a target)
```

AD (allowable depletion) is the water above the MAD trigger: AD_max at field capacity, 0 at the trigger, AD_pwp at the wilting point. The season starts at AD_max, or from `initial_moisture_pct` by the reading formula below.

## A day

```
if a soil moisture reading:
    raw = MRZD × (reading − pct_at_ad0) / 100
    AD  = clamp(raw, AD_pwp, AD_max);  drainage = max(0, raw − AD_max)
    (the day's crop ET is reported, not applied)
else:
    w   = AD_yesterday + rain + irrigation − crop ET
    AD  = clamp(w, AD_pwp, AD_max);    drainage = max(0, w − AD_max)
moisture % = pct_at_ad0 + AD / MRZD × 100
```

Outputs are rounded to 4 places; nothing smaller is truncated (C2 has legacy's caps and thresholds).

**Inputs** (`DailyInputs`):

```
rain        = the field's entry ?? (its system's group, or farm, uses model rain, or the day is after today ? weather : 0.0)
irrigation  = the planting's own: a plot's planting entry, else the field's entry ?? 0.0      (D15)
ET0         = weather (nil → gap fill)
moisture    = the field's entry (a plot's own entry for a plot)
wind, RH min = weather (adjust the crop coefficients; nil counts as FAO-56's standard climate)
```

Sources are `entered`, `model`, `forecast`, `none` and `missing`; pages show them. Weather comes from `WeatherDay.balance_inputs`: stored days before today, the latest deterministic forecast for today and ahead.

**Gap fill:** a day with no ET0 takes the mean of the top 3 computed crop ETs in the previous 7 days (`GAP_FILL_DAYS`, `GAP_FILL_TOP`). Filled values never feed later fills, and with nothing computed in the window the day has no ET (`missing`). Gap fill is never used for the projection's days, which have the forecast.

## Crop ET

For a planting whose crop has FAO-56 coefficients (every crop in `db/reference/plants.yml`), FAO-56's dual crop coefficient (C22, coefficients from FAO-56 Rev.1 since C25):

```
crop ET = (Ks × Kcb + Ke) × ET0
Ks      = 1                       when AD ≥ 0
        = (AD − AD_pwp) / −AD_pwp  below it, to 0 at the wilting point
```

- **Ks** (`Params#ks`, C26, D17): FAO-56's water stress coefficient (eq. 84) from the day's starting AD: below the MAD trigger the crop transpires less, in a straight line to nothing at the wilting point. Only the crop's transpiration (Kcb) is scaled; soil evaporation is figured on the unstressed Kcb (eq. 80). Each `Result` carries `ks` at the day's end AD, what the crop manages next: the pages show it as the share of its normal water use (`Outlook.water_use_pct`, `waterUsePct` in `lib/outlook.ts`, to the nearest 5%, shown below 100%). Irrigated and rainfed plantings alike.

- **Kcb** (`CropEt.kcb`): from percent cover (eq. 98) or LAI (eq. 97), 0 on bare soil, toward the crop's Kcb at full cover that day (`WaterBalance::Crop#kcb_full`): `kcb_mid` adjusted for the day's wind and minimum RH (eqs. 62/70), easing to `kcb_end` from the late stage's start (the day before its canopy curve declines, `Planting#late_stage_start`) to harvest.
- **Ke** (`SoilEvaporation`, eqs. 71–77): the soil surface's evaporation, its depletion carried day to day from season start (wet): wetted by rain of 0.1 in or more and by irrigation (over the system's wetted fraction: drip 0.35), drying at the energy available, then slowing. A reading's day and a gap-filled day leave it as it was. Each `Result` carries the layer's state (`evaporation`), so a run that resumes mid-season (the projection, the ensemble) starts from it.

Without a crop's coefficients (`Params` with `crop: nil`, as the spec factory's plant has, for hand-worked numbers), crop ET is A3600 Table C's percent cover regressions as legacy used them, with C8's fixes (`CropEt.adjusted`), or Kc = 1.1 × (1 − e^(−1.5·LAI)) for LAI. C21's scaling of that table by Kc mid survives only in `LegacyEngine`.

## Status

| Status | Today's AD |
|---|---|
| Full | ≥ 0.9 × AD_max |
| OK | ≥ the target (0.5 × AD_max without one) |
| Caution | above 0 but below that; or Full or OK today and projected to reach the threshold within 3 days (`PlantingStatus::LEAD_DAYS`) |
| Irrigate | ≤ 0 |
| Needs canopy | in season and emerged, set to readings only (no curve), with no reading yet: bare soil's ET, so the balance can't say |

A **rainfed** planting (`plantings.rainfed`, D17) has no target and gets its water stress instead (`WaterBalance.status` with `Params#rainfed`):

| Status | Today's AD |
|---|---|
| No stress | > 0 |
| Stress coming | No stress today, projected to reach 0 within 3 days |
| Stressed | ≤ 0 (Ks below 1 once it's under 0) |

The **threshold** is the target, or AD = 0 without one (always 0 for a rainfed planting). `FieldStatuses.urgency` and `RANK` order fields by status (Irrigate first, the rainfed statuses after every irrigated one) for the dashboard, map and digest.

## Ahead: the projection

`PlantingStatus` runs one balance from season start through the forecast's last day (16 days including today, `HORIZON` after it), within the season.

- **Forecast days** (`forecast_days`): the days after today with forecast ET0. Planned irrigation is an irrigation entry on a future date (a future day takes only irrigation and notes). On a field using only entered rain, the projection still takes the forecast's rain (nobody enters rain ahead), and `dry_projection` runs the same days with no forecast rain, shown beside it (Q7).
- **Crossing** (`crossing`): the first day, today or ahead, at or below the threshold, and the refill to field capacity then (AD_max − AD). Pages show it as "Irrigate by".
- **Ensemble** (`EnsembleProjection`): the balance once per GFS ensemble member (31) from today's AD and soil surface, each with its own ET0 and, where the day's rain is the forecast's, its own rain; entered values kept. The members' ET0 is scaled by the deterministic forecast's correction ratio (`Weather::Ensemble.corrected`, Q10). Each day gives P10, P50 and P90 of AD and the share of members that have reached the threshold by then.
- **Time travel** (`as_of`): the season as it stood on a past day, with the days that followed as the projection, from stored weather and what was entered for them; no ensemble.

## Testing

- `spec/services/water_balance_spec.rb` and its neighbours: hand-worked days, clamps, resets, gap fill, the table's band edges, FAO-56's examples.
- `spec/services/legacy_engine_spec.rb`: random seasons through `LegacyEngine` with every fix on match `WaterBalance` exactly, and with fixes off, each differing day is explained by one. A deliberate change from legacy gets the next C ID in [legacy-audit.md](legacy-audit.md) and a switch there.
- `docs/et-validation/`: crop ET against six seasons of Central Sands potato flux towers (D14), with the scripts that rerun it.
