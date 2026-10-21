# 05. LAI curves from DSSAT (2026-10-21)

Phase 6.7, follow-up to the LAI decision (PLAN.md, "LAI only for crops with an LAI curve"): can
DSSAT supply LAI curves for more crops, and how does it compare with the WIS field corn curve in
`CanopyModel`? Script: `scripts/dssat_lai.py`.

## Sources

- **DSSAT-CSM 4.8** (Jones et al. 2003, *Eur. J. Agron.* 18:235–265,
  doi:10.1016/S1161-0301(02)00107-7; Hoogenboom et al., DSSAT v4.8, dssat.net;
  github.com/DSSAT/dssat-csm-os, BSD-3). Models used: CERES-Maize (`MZCER`), CERES-Sweetcorn
  (`SWCER`) and SUBSTOR-Potato (`PTSUB`), with their cultivar, ecotype and species files.
- **DSSATTools 3.0.2** (Quintero 2026, doi:10.5281/zenodo.18481764; GPL-3), a Python wrapper that
  bundles the DSSAT 4.8.2 Linux binary. Only the script uses it; nothing in the app does.
- **Nocco et al. (2019)**, *Remote Sens.* 11:2460, doi:10.3390/rs11212460: planting dates for these
  crops on Isherwood Farms, Central Sands (Table 1). Its Appendix A fits LAI to aerial EVI, not to
  time, so it gives no growth curves; the weekly LAI-2200 readings behind it (2015–2016) have been
  requested from the authors and would be the test for these curves.

## Why simulate

DSSAT's cultivar files aren't curves. They hold thermal times between growth stages, leaf
appearance intervals and growth rates, and LAI comes out of a daily simulation driven by weather.
So the curves here are fitted to simulated LAI: a model of a model, which is why they need checking
against Wisconsin readings before any becomes a default.

## Setup

- **Site and weather:** Hancock, WI (44.12, −89.53), Open-Meteo archive daily temperature,
  rainfall and solar radiation, seasons 2014–2025 (12).
- **Potential growth:** water and nitrogen stress off, standing in for a well-managed pivot; so the
  soil (WISP's Loamy Sand values, 0.15 / 0.06) barely matters.
- **Plantings** (near the middle of Nocco et al. Table 1): field corn May 12 at 8.4 plants/m² in
  30-inch rows; sweet corn May 28 and June 20 at 6.4/m²; potato May 5 at 4.4/m² in 36-inch rows.
- **Cultivars:** field corn `PC0001`–`PC0003` (DSSAT's 2500–2600, 2600–2650 and 2650–2700 GDD
  hybrids, a typical Central Sands range); sweet corn `SW0001`–`SW0003` (GSS0966, Saturn and BSS0977,
  all sh2, the only sweet corn entries); potato Russet Burbank, Atlantic, Norchip and Shepody.
- Days are counted from DSSAT's simulated emergence, as WISP counts from the entered emergence.

## Results

Medians over the 12 seasons, days since emergence:

| Crop | Cultivar | Planting | Emergence (days after planting) | Peak LAI | Peak day | LAI 1 / LAI 3 reached | Maturity |
|---|---|---|---|---|---|---|---|
| Field corn | PC0001 2500–2600 GDD | May 12 | 12 | 3.80 | 60 | 31 / 48 | 130 |
| Field corn | PC0002 2600–2650 GDD | May 12 | 12 | 4.68 | 68 | 31 / 46 | 157 |
| Field corn | PC0003 2650–2700 GDD | May 12 | 12 | 4.95 | 72 | 32 / 48 | 160 |
| Sweet corn | GSS0966 | May 28 | 8 | 3.25 | 52 | 28 / 47 | 112 |
| Sweet corn | GSS0966 | June 20 | 7 | 3.31 | 50 | 26 / 44 | 130 |
| Sweet corn | Saturn | May 28 | 8 | 4.67 | 54 | 24 / 37 | 122 |
| Sweet corn | Saturn | June 20 | 7 | 4.67 | 52 | 21 / 34 | 133 |
| Sweet corn | BSS0977 | May 28 | 8 | 3.06 | 60 | 32 / 54 | 126 |
| Sweet corn | BSS0977 | June 20 | 7 | 3.20 | 56 | 30 / 52 | 133 |
| Potato | Russet Burbank | May 5 | 30 | 6.77 | 78 | 13 / 20 | – |
| Potato | Atlantic | May 5 | 30 | 5.99 | 86 | 13 / 19 | – |
| Potato | Norchip | May 5 | 30 | 8.07 | 32 | 13 / 20 | – |
| Potato | Shepody | May 5 | 30 | 9.56 | 32 | 13 / 20 | – |

Maturity is physiological maturity (black layer for corn), well after a sweet corn harvest; SUBSTOR
reports none under potential growth.

WISP's curve form, LAI = a · d^b · e^(−c·d), fitted by least squares to the mean daily LAI over
cultivars and seasons, up to each run's maturity:

| Crop | Planting | a | b | c | Peak LAI (day) | RMSE | Spread at the peak (p10–p90) |
|---|---|---|---|---|---|---|---|
| Field corn | May 12 | 1.27e-05 | 3.79 | 0.0483 | 4.32 (78) | 0.18 | 3.33–4.83 |
| Sweet corn | May 28 | 1.63e-05 | 3.89 | 0.0605 | 3.58 (64) | 0.19 | 2.77–4.52 |
| Sweet corn | June 20 | 6.0e-06 | 4.31 | 0.0719 | 3.77 (60) | 0.32 | 2.88–4.54 |
| Potato | May 5 | 0.0453 | 1.64 | 0.0265 | 7.51 (62) | 0.71 | 5.78–7.50 |

### Field corn against the WIS curve

| Day since emergence | 10 | 20 | 30 | 40 | 50 | 60 | 70 | 80 | 90 | 100 | 110 | 120 | 130 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| WIS v6.3.11 (`CanopyModel`) | 0.00 | 0.03 | 0.25 | 0.90 | 1.95 | 3.05 | 3.83 | 4.07 | 3.82 | 3.25 | 2.55 | 1.87 | 1.30 |
| DSSAT fit | 0.05 | 0.41 | 1.18 | 2.16 | 3.10 | 3.82 | 4.22 | 4.32 | 4.16 | 3.83 | 3.39 | 2.90 | 2.43 |
| DSSAT mean | 0.06 | 0.31 | 0.91 | 2.00 | 3.33 | 4.16 | 4.30 | 4.12 | 3.93 | 3.68 | 3.35 | 3.00 | 2.63 |

The peaks agree (4.3 against 4.07), but **DSSAT's canopy develops about 10 days earlier** and
declines more slowly.

### Timing against the 2026 readings

The 2026 readings are percent cover (note 01), so LAI is converted to cover with
cover = 1 − e^(−k·LAI). With DSSAT's own extinction coefficient for ET (KEP = 0.68 in all three
species files), days from emergence to 50% / 80% cover:

| Crop | 2026 readings (median) | DSSAT runs, median (p10–p90) | DSSAT fit | WIS curve |
|---|---|---|---|---|
| Field corn | 26 / 40 | 32 (29–35) / 42 (40–48) | 29 / 43 | 42 / 54 |
| Sweet corn (2 series) | 34 / 46 | 27 (21–33) / 38 (30–47) | 26 / 40 | – |
| Potato | 22 / 32 | 13 (12–15) / 18 (17–20) | 8 / 15 | – |

The field corn comparison depends on k, but the gap between the curves doesn't:

| k | LAI at 50% / 80% | DSSAT runs | WIS curve | 2026 |
|---|---|---|---|---|
| 0.5 | 1.39 / 3.22 | 35 / 50 | 45 / 62 | 26 / 40 |
| 0.68 | 1.02 / 2.37 | 32 / 42 | 42 / 54 | 26 / 40 |
| 0.85 (CERES-Maize KCAN) | 0.82 / 1.89 | 29 / 39 | 40 / 50 | 26 / 40 |
| 1.0 | 0.69 / 1.61 | 27 / 36 | 38 / 48 | 26 / 40 |
| 1.5 (WISP's Kc formula) | 0.46 / 1.07 | 24 / 32 | 35 / 42 | 26 / 40 |

### What it would change in WISP

Through WISP's Kc = 1.1 × (1 − e^(−1.5·LAI)) (`CropEt`), the curves differ only while the canopy
develops:

| Day since emergence | 20 | 30 | 40 | 50 | 60 |
|---|---|---|---|---|---|
| Kc, WIS curve | 0.04 | 0.34 | 0.81 | 1.04 | 1.09 |
| Kc, DSSAT fit | 0.51 | 0.91 | 1.06 | 1.09 | 1.10 |

Over the first 60 days that is about 14 Kc-days, roughly **2.5 inches more crop ET** at a typical
0.18 in/day of reference ET; after day 100 the slower decline adds about 0.2 inches.

## Findings

1. **Field corn: the DSSAT curve is a credible candidate to replace the WIS curve.** Its peak
   matches, and its timing is closer to the 2026 cover readings at every k from 0.5 to 1.5: the WIS
   curve reaches 50% cover 9–19 days after the readings do, DSSAT 2 days before to 9 days after
   (12–16 against 1–6 days late at DSSAT's own 0.68–0.85). The WIS curve has no
   known source (WIS v6.3.11 spreadsheet), so this is the first independent check of it, and it
   suggests WISP's LAI method has been under-estimating early-season corn ET.
2. **Sweet corn: not yet.** The three cultivars differ more (peak 3.1–4.7) than the seasons or
   planting dates do, so the curve depends on which hybrid DSSAT happens to have. Its timing runs a
   week ahead of the only two 2026 series. Worth keeping as a candidate to test against measured
   LAI.
3. **Potato: no.** SUBSTOR's canopy is implausible here: peaks of 6–9.6 (field potatoes are mostly
   3–5; Nocco et al.'s potato fit tops out near 4.7) and 50% cover within two weeks of emergence,
   against 22 days in the 2026 readings.
4. **Caveats.** These are potential-growth runs with uncalibrated cultivars at one site; real
   fields lose canopy to nitrogen shortfalls, hail and disease. The cover comparison rests on
   converting LAI to cover. Measured LAI would remove both problems.

## Next

- **Nocco et al.'s LAI readings**, if they come: weekly in 2015–2016 on six Central Sands fields,
  covering field corn, sweet corn and potato (two to three field-seasons each) with planting dates. Compare both field corn curves with them
  directly, and refit the DSSAT sweet corn curve if it holds up.
- **If the field corn curve changes,** it's a deliberate change from legacy: it gets a fix ID in
  PLAN.md §9 and a switch in `LegacyEngine`, and the About page's crop card and `CanopyModel` cite
  this note. No curve is changed by this note.
