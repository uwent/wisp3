# 02. Published canopy curves (2026-10-15)

Phase 6.7, step A.1, first pass: the five crops with 2026 Wisconsin readings (note 01), then the
sources for the rest. Script: `scripts/aquacrop_check.py`.

## Sources

- **FAO AquaCrop canopy cover model.** Steduto, Hsiao, Raes & Fereres (2009), *Agron. J.* 101:426–437,
  doi:10.2134/agronj2008.0139s; Raes et al. (2009), *Agron. J.* 101:438–447,
  doi:10.2134/agronj2008.0140s; Hsiao et al. (2009, maize), *Agron. J.* 101:448–459,
  doi:10.2134/agronj2008.0218s; AquaCrop reference manual, ch. 3 (canopy development).
- **FAO's default crop files**, as distributed with AquaCrop-OSPy (Kelly & Foster 2021, *Agric.
  Water Manag.* 254:106976, doi:10.1016/j.agwat.2021.106976; github.com/aquacropos/aquacrop,
  `aquacrop/entities/crops/crop_params.py`). They have calendar-day and GDD versions of maize,
  potato, soybean, dry bean, tomato, wheat, barley, sugar beet, alfalfa (GDD only) and others.
- **FAO-56** (Allen, Pereira, Raes & Smith 1998, *Crop evapotranspiration*, FAO Irrigation and
  Drainage Paper 56), Table 11: stage lengths by crop, region and planting date.

## The AquaCrop curve

Time *t* is days (or GDD) since emergence. CC₀ = plant density × initial canopy size per seedling;
CCx is the maximum cover; CGC and CDC are the growth and decline coefficients.

```
growth:   CC = CC₀ · e^(CGC·t)                       while CC ≤ CCx/2
          CC = CCx − ¼ · CCx² / CC₀ · e^(−CGC·t)     after, capped at CCx
decline:  CC = CCx · [1 − 0.05 · (e^(3.33·CDC·t′ / (CCx + 2.29)) − 1)]
          t′ = time since senescence starts; never below 0
```

These are five numbers per crop, which fits a crop card and an About page well. The growth half
is a symmetric S-curve, and the decline accelerates toward the end of the season.

## Checked against Wisconsin, 2026

Days from emergence to 50% and 80% cover. The calendar curves use the crop file's days, and the GDD
curves use 2026 temperatures at each series' location. Error = model − observed, over both
thresholds and every series.

| WISP crop | 2026 observed, to 50% / 80% (median) | AquaCrop file | Calendar curve: 50% / 80% day, mean error (MAE) | GDD curve: mean error (MAE) |
|---|---|---|---|---|
| Potato | 22 / 32 | Potato | 24 / 31, **+2.0 d (3.6)** | PotatoGDD −5.0 (5.7); PotatoLocalGDD +7.6 (7.6) |
| Field corn | 26 / 40 | Maize | 29 / 35, **−1.3 d (4.9)** | MaizeGDD +6.3 (6.3) |
| Soybean | 39 / 51 | Soybean | 33 / 42, −6.5 d (6.5) | SoybeanGDD +10.0 (10.0) |
| Snap bean | 29 / 42 | DryBean | 31 / 39, **−0.8 d (3.2)** | DryBeanGDD +2.7 (3.9) |
| Sweet corn | 34 / 46 (2 series) | Maize | 29 / 35, −8.0 d (8.0) | MaizeGDD −3.2 (6.8) |

Parameters (calendar files; t in days since emergence):

| AquaCrop file | CC₀ | CCx | CGC /day | Decline starts (days after emergence) | CDC /day | Maturity (days after emergence) |
|---|---|---|---|---|---|---|
| Potato | 0.60% | 92% | 0.189 | 74 | 0.0188 | 105 |
| Maize | 0.49% | 96% | 0.163 | 101 | 0.117 | 126 |
| Soybean | 1.65% | 98% | 0.106 | 95 | 0.0289 | 121 |
| DryBean | 1.32% | 99% | 0.118 | 69 | 0.0861 | 109 |

**Findings**

1. **AquaCrop's calendar-day defaults reproduce the Wisconsin timings for potato, field corn and
   snap bean** within a few days, with no calibration. That is about as close as readings taken by
   eye can confirm. Calendar curves beat the GDD versions for every crop except sweet corn, which
   agrees with note 01. The GDD files were calibrated elsewhere (potato GDD in Peru, maize at
   Davis CA) with base temperatures that don't fit Wisconsin.
2. **Soybean runs about 6 days early**, and **sweet corn about 8 days early** on the maize curve.
   Lowering CGC fixes both, a WI adjustment noted on the crop card: soybean CGC ≈ 0.087/day (50% / 80% on
   days 40 / 51) and sweet corn ≈ 0.124/day (38 / 46) put the 80% day at the 2026 medians. Two sweet corn series are too few to
   adjust from; the literature has to support any change.
3. **Potato decline:** AquaCrop's potato barely declines (88% cover at maturity). Wisconsin
   readings decline from about day 55–62, to 50% by day 69, and in one field to 5% by day 76.
   That's probably vine kill and early dying, not the crop file's natural senescence. Options:
   start the decline earlier, around day 60, with a CDC fitted to those two series; or leave the
   decline to readings and the end date. The decline doesn't affect ET until cover falls below 80%,
   but then it matters, which is why the potato decline needs to be right.
4. **Maximum cover** (CCx 92–99%) can't be checked against Wisconsin readings, because growers
   stop at 80% (note 01). ET doesn't depend on it under percent cover, which is at et0 from 80%.
5. **The WIS field corn LAI curve, under WISP's Beer's-law formula (k = 1.5), matches the cover
   readings.** It gives 54% cover equivalent at day 35 and 74% at day 40, against 50% at about
   day 26 and 80% at about day 40 observed. So 1.5 acts like a *visual cover* coefficient rather
   than the 0.4–0.8 radiation-interception values in the literature (Q2 question 2). This also
   suggests deriving LAI from cover for other crops with k = 1.5, consistent with field corn,
   rather than with literature k values. That needs the agronomist's view.

## FAO-56 Table 11, for crops without an AquaCrop file

Stage lengths in days **from planting**: initial (to about 10% cover), development (to effective
full cover, about 70–80% for row crops), mid-season, late season. The rows chosen are the
temperate ones (Europe, continental, Idaho, central USA) where the table has them.

| WISP crop | FAO-56 row (region, planting) | Init | Dev | Mid | Late | Total |
|---|---|---|---|---|---|---|
| Potato | Continental, May | 25 | 30 | 45 | 30 | 130 |
| Potato | Idaho, Apr/May | 45 | 30 | 70 | 20 | 165 |
| Sweet corn | Idaho, April | 30 | 30 | 30 | 10³ | 110 |
| Sweet corn | Mediterranean, May/June | 20 | 25 | 25 | 10 | 80 |
| Field corn | Idaho, April | 30 | 40 | 50 | 50 | 170 |
| Soybean | Central USA, May | 20 | 30/35 | 60 | 25 | 140 |
| Snap bean | Beans (green), Calif./Medit., Feb/Mar | 20 | 30 | 30 | 10 | 90 |
| Shell peas | Europe, May | 15 | 25 | 35 | 15 | 90 |
| Shell peas | Idaho, April | 35 | 25 | 30 | 20 | 110 |
| Onion | Onion (dry), Mediterranean, April | 15 | 25 | 70 | 40 | 150 |
| Cabbage | Calif. desert, Sept | 40 | 60 | 50 | 15 | 165 |
| Broccoli | Calif. desert, Sept | 35 | 45 | 40 | 15 | 135 |
| Carrot | Mediterranean, Feb/Mar | 30 | 40 | 60 | 20 | 150 |
| Beets | Beets (table), Mediterranean, Apr/May | 15 | 25 | 20 | 10 | 70 |
| Celery | Mediterranean, April | 25 | 40 | 45 | 15 | 125 |
| Leafy greens | Lettuce, Mediterranean, April | 20 | 30 | 15 | 10 | 75 |
| Pepper | Sweet peppers, Europe/Medit., Apr/June | 25/30 | 35 | 40 | 20 | 125 |
| Tomato | Calif., Apr/May | 35 | 40 | 50 | 30 | 155 |
| Cucumber | Arid, June/Aug | 20 | 30 | 40 | 15 | 105 |
| Melon | Sweet melons, Mediterranean, May | 25 | 35 | 40 | 20 | 120 |
| Pumpkin, winter squash | Europe, June | 25 | 35 | 35 | 25 | 120 |
| Summer squash | Zucchini, Medit./Europe, May/June | 20 | 30 | 25 | 15 | 90 |
| Sweet potato | Mediterranean, April | 20 | 30 | 60 | 40 | 150 |
| Wheat, barley | Barley/Oats/Wheat, 35–45° lat., Mar/Apr | 20 | 25 | 60 | 30 | 135 |
| Asparagus | Warm winter, Feb | 50 | 30 | 100 | 50 | 230 |
| Alfalfa | Idaho, 1st cutting / later cuttings | 10 / 5 | 30 / 20 | 25 / 10 | 10 / 10 | 75 / 45 |
| Mint | Not in Table 11 (Kc in Table 12 only) | | | | | |

³ As printed ("103"): 10 days, footnote 3.

**Turning a row into a curve (proposed, to test):** subtract a planting-to-emergence gap (AquaCrop's
EmergenceCD where a similar crop has one, otherwise about 7–10 days) to count from emergence. Then
choose CGC so the AquaCrop curve passes 10% at the end of the initial stage and 80% at the end of
development. Start the decline at the end of mid-season, with CDC reaching the crop's late-season
cover by the end of the late stage. Crops harvested green (cabbage, broccoli, lettuce, sweet corn,
snap bean, peas) are ended by the planting's end date rather than a decline.

A check on the FAO-56 rows: potato (continental, May) gives full cover about 55 days after
planting, about 35 after emergence (Wisconsin 2026: 32). Soybean (central USA) gives about 45
after emergence (Wisconsin: 51). Shell peas (Europe) gives about 30 (Wisconsin: 38–42). Field corn
(Idaho) gives about 60, but FAO-56 ends corn's development stage at silking, well after visual
80% cover (Wisconsin: 40). So FAO-56 rows give timing to within about a week, not better, and they
don't define every crop's development stage the same way.

## Next

- Build the FAO-56-derived curves for the remaining crops and check how plausible they are.
  Find Upper Midwest timings for onion, carrot, cabbage and the cucurbits where extension or
  processing-crop literature has them.
- Potato decline: fit the start and rate to the two 2026 series that decline, and look for UW
  potato vine-kill and early-dying canopy data.
- Ask the agronomist (Q2) whether k = 1.5 is the right way to derive LAI from cover.
- Then step A.4: backtest how readings scale the curve, with the curves above.
