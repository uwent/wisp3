# 01. Background

## The papers

**Talib, Desai, Huang, Griffis, Reed and Chen (2021)**, *Evaluation of prediction and forecasting models for evapotranspiration of agricultural lands in the Midwest U.S.*, Journal of Hydrology 600: 126579, doi:10.1016/j.jhydrol.2021.126579. Random forest and LSTM models of daily ET, trained on 19 Midwest eddy-covariance sites (corn, soybean, potato; 2003–2019). Relevant here only for its data and one finding: for irrigated crops, vapor pressure and FAO-56 crop coefficients were the most important predictors. The two Central Sands potato sites (US-CS1, US-CS3) had the lowest mean April–October ET of the 19 (1.7–1.8 mm a day). Funded in part by the Wisconsin Potato and Vegetable Growers Association (WPVGA).

**Talib, Desai, Huang, Thom, Panuska and Stoy (2024)**, *Improving parameterization of an evapotranspiration estimation model with eddy covariance measurements for a regional irrigation scheduling program*, Agricultural and Forest Meteorology 350: 109967, doi:10.1016/j.agrformet.2024.109967. Evaluates legacy WISP's ET (AgWeather, Diak et al. 1998) against towers and corrects it. Funded in part by WPVGA.

- **Model:** Priestley-Taylor, PET = α · Δ/(Δ+γ) · Rn with α = 1.26 in AgWeather's code (the paper says 1.28, after Sanford and Panuska 2015), albedo 0.25, G = 0, net longwave from Idso's (1981) clear-sky emissivity εa = a₁ + a₂ · eₐ · exp(1500/T) scaled by the day's clearness. Crop ET from PET by A3600's percent cover table (PET at 80% cover and above).
- **Inputs were good:** AgWeather's temperature, vapor pressure and satellite insolation matched the towers (insolation NSE 0.90, bias −3.4%).
- **Net longwave was not:** WISP's mean net longwave was −24.2 W/m² against the towers' −64.8 (bias −62.8%), traced to Idso's coefficients (a₁ = 0.70, a₂ = 5.95 × 10⁻⁵ hPa⁻¹), fitted in Phoenix.
- **The correction:** a₁ = 0.544, a₂ = 6.4 × 10⁻⁵ hPa⁻¹, fitted on clear days at three potato site-years (US-CS1 2018, US-CS3 2019, US-CS4 2020; n = 309 days, all within about 10 km). AgWeather serves it as `method=adjusted` (`../ag-weather`, `EvapotranspirationCalculator.et_adj`); it was never the default.
- **Results:** ET bias at the training sites +19.6% → −10.1% (NSE −0.08 → 0.52); at the validation sites (potato US-CS5 2021 and US-CS6 2022, corn US-CC1 and US-CC2 2021, pasture US-DFC 2019, Kernza US-DFK 2019–2020) +35% → +1.3%. Correlation didn't improve (validation R² 0.30 → 0.26): the correction moves the level, not the day-to-day tracking. US-CC2 (corn, 18 days) got worse (−19.9% → −42.7%). Cumulative May–August 2022 ET over the Central Sands fell from 501–544 mm to 371–414 mm.
- **Caveats the paper states:** no energy balance closure correction was applied to the towers' fluxes; footprint mismatch; transpiration and soil evaporation not separated; Priestley-Taylor ignores advection; the 80% cover threshold.

## Reading it against WISP 3

- **The correction is atmospheric, not specific to potato.** It changes the clear-sky emissivity, so it lowers ET for every crop, and it lowered the bias at the corn and grass sites too. "Overfit to potato" isn't the right objection.
- **The fitted a₁ is an outlier.** Every other recalibration in the paper's Table 6 has a₁ between 0.63 and 0.72 (Phoenix, Finland, Spain, a glacier, the contiguous US, 71 FLUXNET sites, Tibet). 0.544 suggests the coefficient absorbed other differences between model and towers: α, albedo, G, the canopy conversion, and the towers' missing energy.
- **Energy balance closure.** Eddy-covariance towers typically account for 70–90% of the available energy (Rn − G); the rest is usually missing from H and LE. Over a well-watered crop most of it would belong to LE, so towers without a closure correction read ET low, by as much as the 10–30% bias the correction removed. The AmeriFlux files carry Rn, G, H and LE, so closure can be measured site by site (02).
- **Net longwave in FAO-56.** WISP 3 uses FAO-56's formula (eq. 39, hourly in eq. 53's form), not Idso's. On typical Central Sands summer days (Tmax 24–29 °C, Tmin 10–17 °C, eₐ 1.2–2.0 kPa) it gives 1.6–2 × legacy's net longwave and about 65% of the adjusted version's, so it probably removes half to two-thirds of the error the paper found. Not yet checked against the towers' radiometers.
- **Wind and humidity.** Penman-Monteith includes them; Priestley-Taylor doesn't. Irrigated circles among dry sand and pine take heat and dry air from around them (advection), which raises ET above Priestley-Taylor's equilibrium.

## Where WISP 3 stands

At full canopy, against FAO-56 ET0 from Wisconet stations' own measurements (PLAN.md §8.5; AgWeather v2's `docs/validation/legacy/v1.md`):

| | Full-cover potato ET, × station ET0 |
|---|---|
| Legacy, classic (AgWeather) | about 1.11 (April–October), 1.14–1.26 (June–September) |
| WISP 3 (Kc mid 1.15, adjusted for wind and RH, × corrected ET0 ≈ 1.03) | about 1.18 |
| Legacy, adjusted (about 0.71 × classic over a year in v2's comparison; 0.75 in the paper's May–August map) | about 0.80–0.90 |

So C21 (2026-11-17) put potato's full-cover water use back near legacy's classic, which the towers measured as 20–35% high. Before C21, WISP corrected called for 4.5 fewer irrigations a season than AgWeather on the standard potato field; with potato's Kc, 1.3 fewer (`docs/weather-comparison.md`).

Two sources disagree: FAO-56 Table 12's Kc mid of 1.15 for potato (lysimeters, worldwide), and the Central Sands towers, which imply a full-cover coefficient near 1.0 against FAO-56 ET0 without a closure correction. With closure around 85%, they would roughly agree. That reconciliation mixes years and datasets; this work replaces it with a measurement. *(Measured in 03: closure is about 80%, and with it put back the towers give 1.09–1.12, so the two agree.)*

## How the decision was made

Looking back (2026-11-19): WISP 3's reference ET became FAO-56 Penman-Monteith as a side effect of moving to Open-Meteo (D6, PLAN.md §8.4), and deliberately with D12, when WISP started computing it from corrected shortwave. Potato's full-cover water use was then set by C21 from FAO-56 Table 12 and the irrigation counts against AgWeather. Neither step drew on the Central Sands tower research, the only measured ET for irrigated potato in Wisconsin, though the percent-cover refit planned after launch listed it. This work fills that gap: the towers are the independent check on D12 and C21 (results in 03 and 04, recorded as D14).

## The question

1. From each tower's own weather (temperature, humidity, wind, pressure, its pyranometer), compute FAO-56 ET0, hourly as WISP does. This takes the weather source out of the comparison.
2. Measure each site-season's energy balance closure, and the towers' ET with and without a closure correction (Bowen ratio preserving, as FLUXNET's `LE_CORR`).
3. The implied crop coefficient, ETa / ET0, by days since emergence and by canopy cover where known; at full cover, compare it with 1.15.
4. Run WISP 3's `CropEt` on the towers' ET0 with each site's crop, dates and canopy, and compare modeled with measured ET: bias, MAE, NSE by site, crop and month, against the paper's numbers for classic and adjusted Priestley-Taylor on the same days.
5. Check FAO-56's net longwave against the towers' four-component radiometers, as the paper did for Idso's.
6. Then, separately, WISP 3's actual inputs (Open-Meteo, corrected) at the towers for the seasons Open-Meteo's historical forecasts cover, to see what the weather source adds.

The outcome is either evidence for C21's 1.15 or a revised potato (and corn) coefficient, recorded as a D# in PLAN.md with this as its evidence, and a summary on the About page crediting the research and its funding.
