# 05. Corn

US-CC1 and US-CC2 (Coloma, 2021; Stoy, Brevert and Khan) are AmeriFlux BASE files: not gap-filled, with no air temperature (derived from RH and VPD) and no pressure (from elevation). Whole days of measured ET are rare, so `scripts/corn.py` uses daytime sums: measured ET over FAO-56 ET0 (from the tower's weather, as `et0.py`) for 08–18 local standard time, over hours with LE and every input measured, on days with at least 16 of the 20 half-hours. It runs the potato towers the same way as a check: their daytime ratios over July (0.76–0.85) sit close to the whole-day ones in 03.

```bash
python3 -I docs/et-validation/scripts/corn.py
```

## What the fields were

Paul Stoy (2026-11): both were **dryland field corn**; his group has no planting dates or other agronomic records. That settles two of the three questions the first pass left open (field or sweet corn, irrigated or not) and changes how the records are read:

- **Field corn** compares with Field Corn's coefficients (`plants.yml`, FAO-56 Rev.1's maize grain row): Kcb mid 1.15, which WISP adjusts each day for wind and humidity (eq. 70). On US-CS5's weather over the two windows below (wind at 2 m 1.5–1.6 m/s, minimum RH 52–59%) that's **1.08–1.10**, plus soil evaporation, small under a closed canopy.
- **Dryland** means the crop runs short of water between rains on this sand, and WISP has no stress coefficient: it models a well-watered crop, which is what an irrigated field is meant to be. So only days with moist soil compare. Both towers measured soil moisture (sensor depths not in the metadata); `corn.py` keeps days whose mean over the sensors is at least **7.5%**, where FAO-56 has maize begin to run short (p = 0.55, Table 22) on WISP's Sand (field capacity 11.2%, wilting point 4.5%).

## Full canopy from the towers, not the calendar

Without planting dates the windows come from the towers' own records (the day-by-day tables `corn.py` prints):

- **US-CC1**: daytime ET / ET0 runs 0.36–0.59 from late June to July 12, with midday CO2 uptake of 13–24 µmol m⁻² s⁻¹. Between July 12 and 19 both jump, to about 1.0 and 36–43, with no change in soil moisture to explain it: the canopy closing. Uptake holds through August and is down to 19–20 by Aug 30–31. **Window: Jul 19 – Aug 21.**
- **US-CC2**: its NDVI is 0.92–0.96 from July 6, five weeks before its fluxes start (Aug 13), so the canopy was already closed. After 26 mm on Aug 24 (and 31 mm on the 27th) NDVI drops to 0.73–0.77 and recovers to 0.91 by Aug 31, so storm damage or a wet sensor; the days after are left out. **Window: Aug 14 – 23.**

The first pass (below) put US-CC1's window at July 10 from a guessed May 1 planting, which took in four days of open canopy at 0.36–0.52; most of its low 0.82 came from those.

## The towers' wind

Both towers' sonic anemometers read 0.4–0.9 m/s at midday from June to October, where US-CS5 (potato, a few miles away, the same summer) reads 2.4–2.9 m/s: they sat at or in the canopy top, where the wind is far below the 2 m wind over grass that ET0 is defined on. `corn.py` runs the corn towers' ET0 on US-CS5's wind for the same half-hour (at 2.5 m over potato, taken to 2 m as `et0.py` does), and on their own wind for comparison. Daytime ET0 is mostly radiation, so it moves the ratio only 5–10%, downward.

## Results

| Site | Window | Wind | Soil | Days | Daytime ET / ET0 | Daytime closure | Corrected | Closure, G = 0.1 Rn where unmeasured | Corrected |
|---|---|---|---|---|---|---|---|---|---|
| US-CC1 | Jul 19 – Aug 21 | US-CS5 | moist | 9 | 0.93 | 1.17 | (0.79) | 1.17 (G measured) | (0.79) |
| US-CC2 | Aug 14 – 23 | US-CS5 | moist | 6 | 0.91 | 0.78 | 1.17 | 0.86 | 1.06 |
| US-CC2 | Aug 14 – 23 | US-CS5 | dry | 3 | 0.85 | 0.79 | 1.08 | 0.87 | 0.97 |
| US-CC1 | Jul 19 – Aug 21 | own | moist | 9 | 1.02 | 1.17 | (0.87) | 1.17 | (0.87) |
| US-CC2 | Aug 14 – 23 | own | moist | 6 | 0.98 | 0.78 | 1.26 | 0.86 | 1.13 |

- **US-CC2 agrees with WISP.** On moist days, closure-corrected, the tower's coefficient is 1.06–1.17 against WISP's 1.08–1.10 plus a little soil evaporation. Measured as recorded (0.91) it sits where the potato towers do (0.76–0.85), whose corrected values also came out near FAO-56's.
- **US-CC2 shows the dryland stress.** The ratio holds at 0.88–1.00 as the soil dries from 15% to 7.2% (Aug 14–20), then falls to 0.81–0.85 at 6.3% and 5.9% (Aug 22–23), under the 7.5% where FAO-56 has maize begin to run short. Three days, but in the direction and at about the point expected.
- **US-CC1 can't be closure-corrected.** Its closure is 0.25–0.66 before the canopy closes and 1.05–1.53 after (more turbulent flux than available energy), jumping in the same week as the CO2 uptake, and midday albedo goes from 17% to 24–33% in late July. The net radiometer and soil heat plate were likely read differently once the corn grew up around them. Its 0.93 as recorded is a floor; with the potato towers' typical closure (0.75–0.85) it would be 1.09–1.24, but that's an assumption, not a measurement.

**What this can and can't say.** About fifteen moist full-canopy days at two fields in one season, one of them without a usable energy balance: WISP's full-cover coefficient for field corn is consistent with the one tower that can be checked, and nothing here argues for changing it. It isn't a test of the season: emergence isn't known, US-CC1 starts mid-development and US-CC2 in mid-August, and US-CC1 has no rain gauge, so a season run through WISP's canopy would mostly be testing a guessed planting date. Corn's coefficients stay as FAO-56 Rev.1 gives them.

## First pass (2026-11-19)

Before Stoy's answer, with the windows from the calendar (Central Sands corn planted around May 1), the towers' own wind and no soil moisture filter:

| Site | Window | Days | Daytime ET / ET0 | Daytime closure | Corrected | Closure, G = 0.1 Rn where unmeasured | Corrected |
|---|---|---|---|---|---|---|---|
| US-CC1 | Jul 10 – Aug 31 | 16 | 0.82 | 0.88 | 0.93 | 0.88 (G measured) | 0.93 |
| US-CC2 | Aug 14 – Aug 31 | 14 | 0.93 | 0.75 | 1.23 | 0.84 | 1.11 |

With FAO-56 Rev.1's hourly ET0 (C24): US-CC1 0.81 / corrected 0.91, US-CC2 0.92 / 1.22 (1.10 with G = 0.1 Rn). It was read as inconclusive, pending what was grown and whether it was irrigated.
