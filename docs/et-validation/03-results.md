# 03. Results: full cover

First results, 2026-11-19: potato at full cover (July), all six Central Sands seasons. The rest of the season, with the crop dates, is in 06; corn in 05.

Reproduce:

```bash
python3 -I docs/et-validation/scripts/et0.py        # tmp/ameriflux/daily.csv; checks FAO-56 Example 19 first
python3 -I docs/et-validation/scripts/compare.py    # July; --from MM-DD --to MM-DD for another window
```

## Method

- **ET0** from each tower's own weather (temperature, VPD, wind taken to 2 m, shortwave, pressure), hour by hour with WISP's FAO-56 chain (`et0.py`, a line-for-line port of `Weather::Fao56`, checked against FAO-56 Example 19). No Open-Meteo, no corrections: this tests the method, not the weather source.
- **Days kept:** at least 90% of the day's half-hours with all five weather inputs measured, at least 40% with LE measured (the rest MDS gap-filled, as ONEFlux does), ET0 ≥ 1 mm.
- **Window: July 1–31.** WISP's potato canopy curve is at full cover through July for any emergence before about May 30, and its decline starts July 25 (`canopy_curves.yml`), so the window is fixed in advance rather than picked from the towers' data. The towers agree: the measured ET/ET0 plateau runs from mid-June to late July at every site.
- **Closure:** C = Σ(H + LE) / Σ(Rn − G) over the window's days, and measured ET ÷ C as the closure-corrected ET. G is measured at US-CS5, CS6 and CS8; elsewhere it's taken as 0 over a day (at CS5 and CS6, where it's measured, it changes closure by 0.01–0.02).
- **Models**, each on the same days and the same tower weather:
  - **WISP 3:** ET0 × potato's Kc mid 1.15, adjusted each day for wind and minimum RH (FAO-56 eq. 62, as `CropEt.kc_mid`). In the humid Central Sands July it comes to 1.11–1.13.
  - **Legacy, classic:** AgWeather's Priestley-Taylor (Diak et al. 1998), ported from `../ag-weather`, at full cover (crop ET = PET).
  - **Legacy, adjusted:** the same with Talib et al.'s emissivity coefficients.

## Crop ET at full cover

| Site | Season | Days | ET0 mm/d | Measured mm/d | Closure | Measured / ET0 | Closure-corrected / ET0 | WISP 3 Kc | WISP 3 vs measured | Classic | Adjusted | WISP 3 vs corrected | Classic | Adjusted |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| US-CS1 | 2018 | 30 | 4.60 | 4.12 | 0.77 | 0.90 | 1.16 | 1.13 | +26% | +40% | +6% | −3% | +8% | −18% |
| US-CS3 | 2019 | 30 | 4.35 | 3.88 | 0.79 | 0.89 | 1.13 | 1.12 | +25% | +45% | +11% | −1% | +15% | −12% |
| US-CS4 | 2020 | 25 | 4.44 | 3.73 | 0.81 | 0.84 | 1.04 | 1.12 | +33% | +56% | +19% | +8% | +26% | −3% |
| US-CS5 | 2021 | 27 | 4.37 | 3.66 | 0.83 | 0.84 | 1.01 | 1.11 | +33% | +52% | +16% | +10% | +26% | −4% |
| US-CS6 | 2022 | 29 | 4.14 | 3.79 | 0.74 | 0.92 | 1.24 | 1.12 | +22% | +39% | +6% | −9% | +3% | −22% |
| US-CS8 | 2023 | 31 | 4.29 | 3.50 | 0.85 | 0.82 | 0.96 | 1.13 | +39% | +45% | +10% | +18% | +24% | −6% |
| **All** | | 172 | 4.36 | 3.78 | 0.80 | 0.87 | 1.09 | 1.12 | +29% | +46% | +11% | +3% | +16% | −12% |

Daily measured ET follows the towers' ET0 closely (r 0.83–0.91 at the Heartland sites, 0.69–0.73 at Worzella).

**2026-11-19: FAO-56 Rev.1's hourly ET0 (PLAN.md §9 C24).** `et0.py` now uses the second edition's surface resistance (50 s/m by day, 200 s/m at night, instead of 70 s/m every hour), as WISP does, and is checked against Rev.1's Example 4.3. The towers' July ET0 rises 4.2–5.3% (all days 4.36 → 4.57 mm/d), so every ratio to it falls by that much: measured / ET0 0.87 → 0.83, closure-corrected / ET0 1.09 → 1.04 (by site 1.11, 1.08, 0.99, 0.97, 1.17, 0.92), and WISP 3 with Kc mid 1.15 goes from +29% / +3% to +36% / +8% against measured / closure-corrected ET. The legacy models don't use ET0 and don't move. The table above is the 1998 form's; potato's coefficients are being revised to Rev.1's at the same time, and the final numbers follow that.

A wider window, June 20 – August 8 (257 days), gives the same picture (closure-corrected / ET0 1.06; WISP 3 +6%, classic +18%, adjusted −10% against corrected), except at US-CS8, whose canopy was going by early August (its ET/ET0 halves in the first week of August).

## What it shows

1. **Everything turns on energy balance closure.** The towers account for 80% of the available energy at full cover (0.77–0.85). Uncorrected, they measure potato at 0.87 × FAO-56 ET0; with the missing energy put back, 1.09.
2. **Where the missing energy goes barely matters here.** Over irrigated potato in July the Bowen ratio (H/LE) is 0.01–0.15: nearly all the energy goes to ET. Preserving the Bowen ratio (FLUXNET's method) and assigning the whole residual to ET give almost the same correction (1.20–1.38 against 1.18–1.35).
3. **WISP 3 matches the closure-corrected towers:** +3% over all six seasons (−9% to +18% by season; −3% to +10% at the four Heartland seasons). Potato's measured full-cover coefficient, 1.09 (0.96–1.24), sits just under FAO-56's 1.15 and WISP's humid-adjusted 1.12.
4. **Talib et al.'s adjusted equation matches the uncorrected towers** (+11%), as it was fitted to, and is 12% low against the corrected ones (−3% to −22%). Classic legacy ET is high either way: +16% corrected, +46% uncorrected. The paper's central finding, that legacy WISP overestimated, holds on every reading.
5. **The paper was right about longwave.** Net longwave loss from the towers' radiometers, July (MJ/m² a day):

   | | Days | Measured | FAO-56 (eq. 39, hourly) | Legacy classic (Idso) | Legacy adjusted |
   |---|---|---|---|---|---|
   | All days | 169 | 5.85 | 3.15 | 1.90 | 5.57 |
   | Clear days (Rs/Rso ≥ 0.8) | 77 | 6.96 | 3.95 | 2.49 | 6.81 |

   Idso's original coefficients give a third of the measured loss; the adjusted ones match it. FAO-56's formula gives a little over half. That doesn't make FAO-56 ET0 wrong for its purpose: ET0 is the water use of a reference grass, not this field's energy budget, and FAO-56's crop coefficients were measured against ET0 computed with this same formula, so its net longwave is built into them. Talib et al.'s correction fixed a real error in a model that used the field's own energy budget directly (Priestley-Taylor, Kc = 1); because their towers weren't corrected for closure, the fitted coefficients also absorbed the missing 20%, and the adjusted ET lands below the energy the field actually had.

## How sure

- **Which hours the closure is measured over matters.** The table uses whole days, where the night's negative Rn offsets some of the day's. Over daytime hours only (08–18, `corn.py`, which runs the potato towers too), closure is lower and the correction larger: 0.66–0.76, or 0.75–0.79 at US-CS1, CS3 and CS4 with their unmeasured G taken as FAO-56's daytime 0.1 Rn. Measured potato ET/ET0 over the same hours is 0.80–0.90, as by whole days, and the corrected coefficient is 1.06–1.20 at the Heartland seasons (1.12 together) against 1.01–1.16 (1.09) by whole days; the Worzella seasons give 1.18–1.34. ONEFlux's half-hourly `LE_CORR` sits higher still (02). So the closure-corrected coefficient is about 1.09–1.12 at the best-instrumented seasons, and up to 1.2 on the more generous readings; WISP 3's 1.12 is within it, and nothing in the towers points below 1.0 once closure is accounted for.
- **The closure correction is the assumption.** It's standard (FLUXNET2015's `LE_CORR`; Wilson et al. 2002, *Agric. For. Meteorol.* 113: 223–243, found 0.80 on average across 22 FLUXNET sites; Mauder, Foken and Cuxart 2020, *Boundary-Layer Meteorol.* 177: 395–426, review the evidence that the missing energy is mostly turbulent flux the towers can't see, not radiation error). If instead the uncorrected towers are right and the imbalance is error in Rn or G, WISP 3 runs 29% high at full cover and the adjusted equation is the better fit. The two readings bracket the answer; the corrected one is the community's standard.
- **The Worzella seasons (US-CS6, CS8) are less certain.** Their midday albedo is 0.07–0.12, against 0.21–0.22 at the Heartland sites and the 0.20–0.25 expected over a potato canopy, which points to the upward shortwave sensor (too much Rn, closure too low, correction too large: CS6's 1.24). US-CS8's soil heat flux averages 1.8 MJ/m² a day in July, about 10 times what CS5 and CS6 measure; with G taken as 0, CS8's closure is 0.74 and its corrected coefficient 1.11 instead of 0.96. The Heartland seasons alone (US-CS1, CS3, CS4, CS5: 112 days) give 1.09, the same as all six.
- **Wet canopy days can't be screened.** The rain gauges catch the pivots, so almost every July day has "rain"; FAO-56's Kc mid includes the usual sprinkler wetting, so the comparison is like for like.
- **Footprint.** The towers see a few hundred meters of a single field; WISP's ET0 comes from a 9 km weather cell. This test removes the weather source; how Open-Meteo's corrected ET0 compares with these towers' ET0 is a separate check (01, step 6).
- **One month, one crop stage.** Full cover is where the coefficient question was; development, decline and vine kill are in 06.

## Next

- ~~With the crop dates and canopy cover from Desai's group: the whole season.~~ Done in 06.
- WISP 3's own weather at the towers: Open-Meteo's historical forecasts with WISP's corrections, against the towers' ET0, for the seasons it covers (2022 and 2023 at least).
- Corn: US-CC1 (about 38 days) at full cover, as a rough check against 1.20.
