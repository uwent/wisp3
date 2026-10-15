# 03. Curves for every crop (2026-10-15)

Phase 6.7, step A.5 (first draft of the crop cards). Builds on notes 01 (Wisconsin 2026 readings)
and 02 (AquaCrop and FAO-56). Script: `scripts/fao56_curves.py`.

## Crops without an AquaCrop file: curves from FAO-56 Table 11

WISP counts time from emergence (or transplanting); FAO-56 counts stage lengths from planting.
For each crop:

- **gap** = planting to emergence: 0 for transplanted crops (FAO-56 counts their initial stage
  from transplanting), otherwise a typical germination time (7–14 days). These are assumptions.
- The initial stage ends at about 10% cover: **t₁ = L_ini − gap**. The development stage ends at
  effective full cover, taken as 80% (or 95% of CCx where CCx is under 84%): **t₂ = L_ini + L_dev − gap**.
- CC₀ and CGC are then **solved** so the AquaCrop growth curve passes through both points. That
  avoids guessing seedling canopy sizes, but the curve can't be better than the FAO-56 row. In
  the AquaCrop form, the development stage's length fixes CGC, and the initial stage fixes CC₀.
- **CCx** is 95% where there's no source; it changes ET only if it's below 80% (note 02).

| Crop | FAO-56 row | Gap | CCx | CC₀ | CGC /day | 10% / 50% / 80% (days after emergence) | Mid-season ends (days after emergence) |
|---|---|---|---|---|---|---|---|
| Shell peas (Europe) | Peas, Europe, May | 10 | 95% | 5.81% | 0.108 | 5 / 20 / 30 | 65 |
| Shell peas (Idaho) | Peas, Idaho, April | 10 | 95% | 0.66% | 0.108 | 25 / 40 / 50 | 80 |
| Onion | Onion (dry), Mediterranean, April | 14 | 95% | 8.97% | 0.108 | 1 / 16 / 26 | 96 |
| Cabbage, broccoli | Crucifers, Mediterranean, April | 0 | 95% | 1.64% | 0.090 | 20 / 38 / 50 | 70 |
| Carrot | Carrots, Mediterranean, Feb/Mar | 14 | 95% | 3.38% | 0.068 | 16 / 40 / 56 | 116 |
| Beets | Beets (table), Mediterranean, Apr/May | 7 | 95% | 4.20% | 0.108 | 8 / 23 / 34 | 53 |
| Celery | Celery, Mediterranean, April | 0 | 95% | 1.84% | 0.068 | 25 / 49 / 66 | 110 |
| Leafy greens | Lettuce, Mediterranean, April | 7 | 95% | 3.09% | 0.090 | 13 / 31 / 43 | 58 |
| Pepper | Sweet peppers, Europe/Medit., Apr/June | 0 | 75% | 0.55% | 0.104 | 28 / 45 / 63 | 103 |
| Cucumber | Cucumber, Arid, June/Aug | 7 | 95% | 3.09% | 0.090 | 13 / 31 / 43 | 83 |
| Melon | Sweet melons, Mediterranean, May | 7 | 95% | 2.48% | 0.077 | 19 / 39 / 53 | 93 |
| Pumpkin, winter squash | Pumpkin/winter squash, Europe, June | 7 | 95% | 2.48% | 0.077 | 19 / 39 / 53 | 88 |
| Summer squash | Squash/zucchini, Medit./Europe, May/June | 7 | 95% | 3.09% | 0.090 | 13 / 31 / 43 | 68 |
| Sweet potato | Sweet potato, Mediterranean, April | 0 | 95% | 1.64% | 0.090 | 20 / 38 / 50 | 110 |
| Wheat, barley (spring) | Barley/Oats/Wheat, 35–45° lat., Mar/Apr | 10 | 95% | 3.38% | 0.108 | 10 / 25 / 35 | 95 |
| Asparagus (fern) | Asparagus, warm winter, Feb | 0 | 95% | 0.11% | 0.090 | 50 / 68 / 80 | 180 |

**Plausibility:**
- **Peas:** the Europe and Idaho rows bracket Wisconsin 2026 (80% at day 30 and 50, against 38–42
  read). A curve fitted to the three Wisconsin series (CGC 0.088/day, CC₀ 4.5%: 10% / 50% / 80% on
  days 9 / 28 / 40) lies between them, so it's used.
- **Onion:** the only temperate row gives 80% cover by day 26, which is implausible for an onion
  canopy (CC₀ 9% is also far too large for onion seedlings). I found no published onion CCx or CGC.
  Onion calibrations exist (Ethiopia, Kenya) but don't report their parameters. **No curve
  until there's a source.**
- **Asparagus:** the row is for a warm-winter crop from February; it doesn't describe Wisconsin fern
  growth after the harvest season. **No curve.**
- **Pepper:** CCx 75% by analogy with AquaCrop's tomato. That's an assumption to check: it puts
  pepper's maximum ET below et0.
- **The other rows are Mediterranean or arid plantings**, chosen as the closest to a Wisconsin
  spring or summer planting. Expect timing errors of about a week either way. Readings correct
  them, and these crops are rarely irrigated with WISP.

## Proposed default for every crop

Percent cover curve; LAI for every crop except field corn comes from the cover curve (below).
"End date" means the canopy holds its maximum until the planting's end date (harvest), then 0.

| Crop | Growth | Decline | Confidence |
|---|---|---|---|
| Potato | AquaCrop Potato (calendar) | Wisconsin rule: from Aug 1, −10 points/week to 50%, then end date | Published; matches WI 2026 (note 02). Decline: expert judgment |
| Field corn | AquaCrop Maize (calendar); LAI: WIS curve, unchanged | AquaCrop (from day 101) | Published; matches WI 2026 |
| Sweet corn | AquaCrop Maize with CGC 0.124/day | End date (harvested green) | WI-adjusted: 2 WI series and FAO-56 rows (80% at day 37–52) agree |
| Soybean | AquaCrop Soybean with CGC 0.087/day | AquaCrop (from day 95) | WI-adjusted: published curve was 6 days early in WI 2026 |
| Snap bean | AquaCrop DryBean (calendar) | End date (harvested green) | Published; matches WI 2026 |
| Shell peas | AquaCrop form fitted to WI 2026 (CGC 0.088, CC₀ 4.5%) | End date | WI-fitted (3 series), within FAO-56's range |
| Tomato | AquaCrop Tomato (calendar; CCx 75%) | AquaCrop (from day 87) | Published, unvalidated in WI |
| Cabbage, broccoli | FAO-56 crucifers | End date | FAO-56 derived |
| Carrot, beets, celery, leafy greens, sweet potato | FAO-56 (rows above) | End date | FAO-56 derived |
| Cucumber, melon, pumpkin, winter squash, summer squash | FAO-56 (rows above) | End date | FAO-56 derived |
| Pepper | FAO-56, CCx 75% (as tomato) | End date | FAO-56 derived, CCx assumed |
| Wheat | FAO-56 spring small grains | AquaCrop Barley's decline (from day 58) | FAO-56 derived; winter wheat (emergence = spring green-up) to check |
| Barley | AquaCrop Barley (calendar; CCx 80%) | AquaCrop (from day 58) | Published, unvalidated in WI |
| Onion | **None** (readings only) | | No source found |
| Alfalfa, mint | **None** (readings only) | | Cut and regrown during the season (WI 2026 alfalfa: a sawtooth, note 01); needs cutting dates, a later feature |
| Asparagus | **None** (readings only) | | No temperate source for fern growth |
| Other | **None** (readings only) | | |

## LAI from cover

For crops other than field corn, LAI = −ln(1 − CC) / k with k = 1.5, the value in WISP's LAI
formula. Substituting into Kc = 1.1 × (1 − e^(−1.5·LAI)) gives exactly **Kc = 1.1 × cover**. So for
these crops, the LAI method amounts to a crop coefficient proportional to cover: 0.88 at 80% cover
and 1.05 at 95%. The percent cover method instead uses A3600 Table C and reaches et0 (Kc 1.0) at
80% cover. A3600's ratio of adjusted ET to et0 (from `CropEt`, similar for et0 0.1–0.3 in) runs
well above 1.1 × cover during development:

| Cover | 10% | 30% | 50% | 70% | 80% | 95% |
|---|---|---|---|---|---|---|
| Percent cover method (A3600) | 0.22 | 0.53 | 0.78 | 0.95 | 1.00 | 1.00 |
| LAI from cover (1.1 × cover) | 0.11 | 0.33 | 0.55 | 0.77 | 0.88 | 1.05 |

So the LAI method would put crop ET 20–40% lower than percent cover through canopy development, and
higher only above 91% cover. A3600's regressions start from bare-soil evaporation at 0% cover,
while the Beer's-law Kc has no soil term. Whether that difference is intended, and whether
k = 1.5 is right, is a question for the agronomist (Q2, questions 2 and 4). Until then, percent
cover is the method to recommend for every crop but field corn.

## For the agronomist

1. The AquaCrop calendar defaults for potato, maize, soybean and dry bean, with the Wisconsin
   adjustments for soybean and sweet corn (note 02).
2. Potato decline: the Aug 1 rule until the researcher's potato model arrives.
3. A source for onion canopy development (and maximum cover) in the Upper Midwest.
4. LAI from cover with k = 1.5, i.e. Kc = 1.1 × cover, which gives 20–40% less ET than the
   percent cover method during canopy development.
5. Whether winter wheat is irrigated with WISP, and if so, what its emergence date should be.

## Next

Step A.4: backtest how readings scale these curves (scale factor, the band for breaking to
straight lines, whether to fit a time shift too), on the Wisconsin 2026 series.
