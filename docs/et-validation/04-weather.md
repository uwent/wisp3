# 04. WISP 3's own weather at the towers

03 tested the method on the towers' own weather. This tests the weather WISP 3 actually uses: Open-Meteo's historical forecasts at each tower's weather cell, through WISP's hourly merge, shortwave and humidity corrections and FAO-56 ET0 (`Weather::Comparison`, as `bin/rails weather:compare`), for each tower's season (April–September). It also fetches AgWeather's gridded ET at each tower, classic and adjusted: the inputs legacy WISP and Talib et al. actually used.

Reproduce (needs the network):

```bash
bin/rails runner docs/et-validation/scripts/weather_at_towers.rb    # tmp/ameriflux/wisp_weather.csv
python3 -I docs/et-validation/scripts/compare_weather.py
```

**Before 2025, Open-Meteo's historical forecasts have no NBM**, so for these seasons (2018–2023) WISP's chain runs on `best_match` alone. WISP uses NBM first, then `best_match`, and the shortwave correction was fitted to that merge; `best_match`'s shortwave reads higher than NBM's (1.20 against 1.15 × the Wisconet stations, PLAN.md §8.5), so these results are probably a few percent high for WISP as it runs today.

AgWeather's adjusted ET is asked for with `method=adjusted` (the point endpoint; the grid's parameter is `et_method`).

## Reference ET

Against FAO-56 ET0 from each tower's instruments (03), on days with the tower's inputs measured; ratio of totals, MAE, correlation:

| Source | Days | Tower ET0 mm/d | Ratio | MAE mm/d | r | Apr | May | Jun | Jul | Aug | Sep |
|---|---|---|---|---|---|---|---|---|---|---|---|
| WISP 3 (corrected, FAO-56) | 672 | 3.47 | 1.05 | 0.40 | 0.94 | 1.10 | 1.06 | 1.08 | 1.05 | 1.04 | 1.03 |
| Open-Meteo's own ET0 (uncorrected) | 672 | 3.47 | 1.18 | 0.65 | 0.94 | 1.23 | 1.18 | 1.20 | 1.18 | 1.17 | 1.17 |
| AgWeather classic | 670 | 3.48 | 1.16 | 0.66 | 0.94 | 0.95 | 0.99 | 1.15 | 1.23 | 1.20 | 1.06 |
| AgWeather adjusted | 672 | 3.47 | 0.84 | 0.64 | 0.92 | 0.77 | 0.75 | 0.87 | 0.93 | 0.85 | 0.64 |

By site, WISP 3: 1.00 (US-CS1), 1.04 (CS3), 1.04 (CS4), 1.00 (CS5), 1.08 (CS6), 1.15 (CS8), r 0.94–0.95 at every site.

- **WISP's corrections work here too.** Open-Meteo's own ET0 is 18% above the towers', as AgWeather v2 found against the Wisconet stations (1.16); WISP's corrected ET0 is 5% above, a little more than against the stations (1.03), as expected from `best_match` alone. They were fitted elsewhere and tested here on stations they never saw.
- **AgWeather classic's seasonal shape** shows here as against the stations: low in spring, 15–23% high in summer. AgWeather adjusted is low all season, most in spring and fall.
- **US-CS8 (2023) is the outlier**, 1.15 in every month. Its pyranometer agrees with ERA5 as well as the other sites' do (tower/ERA5 shortwave 1.02–1.07 at all six), so it isn't the tower's radiation. 2023 was a drought summer with Canadian wildfire smoke: the tower's daily maximum VPD averaged 18–21 hPa in June–August against 13–15 in the other seasons. A forecast model's air over a dry region and a smoky sky would both read high against a tower over an irrigated field; this note doesn't separate them.

## Crop ET at full cover

July, the same 172 days as 03; bias against the towers' measured ET as recorded / closure-corrected:

| Site | Days | Measured mm/d | Closure | WISP 3, tower weather | WISP 3, its own weather | AgWeather classic | AgWeather adjusted |
|---|---|---|---|---|---|---|---|
| US-CS1 | 30 | 4.12 | 0.77 | +26% / −3% | +29% / −1% | +25% / −4% | −7% / −28% |
| US-CS3 | 30 | 3.88 | 0.79 | +25% / −1% | +30% / +3% | +43% / +13% | +8% / −15% |
| US-CS4 | 25 | 3.73 | 0.81 | +33% / +8% | +34% / +8% | +53% / +24% | +15% / −7% |
| US-CS5 | 27 | 3.66 | 0.83 | +33% / +10% | +35% / +12% | +50% / +25% | +12% / −7% |
| US-CS6 | 29 | 3.79 | 0.74 | +22% / −9% | +30% / −4% | +37% / +1% | +4% / −23% |
| US-CS8 | 31 | 3.50 | 0.85 | +39% / +18% | +66% / +42% | +49% / +27% | +11% / −5% |
| **All** | 172 | 3.78 | 0.80 | +29% / +3% | +37% / +9% | +42% / +13% | +7% / −15% |

**2026-11-19: FAO-56 Rev.1's hourly ET0 (PLAN.md §9 C24).** Both the towers' ET0 (`et0.py`) and WISP's (`Weather::Fao56`, `weather_at_towers.rb` rerun) now use the second edition's surface resistance. Tower ET0 over these 672 days rises from 3.47 to 3.66 mm/d, and WISP's moves with it: WISP 3 against the towers stays 1.05 (by month and by site unchanged within 0.01, US-CS8 1.16). The sources computed another way fall against the higher reference: Open-Meteo's own ET0 1.18 → 1.12, AgWeather classic 1.16 → 1.10, adjusted 0.84 → 0.79. Crop ET at full cover (Kc mid 1.15, as in the table): WISP 3 on the towers' weather +36% / +8%, on its own +44% / +14% (+29% / +3% and +37% / +9% before); AgWeather's columns don't change.

- **WISP 3 on its own weather: +9% against the closure-corrected towers**, +3% without 2023 (the four Heartland seasons: −1% to +12%). Some of that is `best_match` standing in for NBM.
- **On their real inputs, Talib et al.'s numbers reappear:** AgWeather classic +42% against the uncorrected towers (the paper: +20–35% over whole seasons, with canopy conversion), adjusted +7% (the paper: −10% at training sites, +1% at validation sites).
- **Against the corrected towers, WISP 3 is the closest of the three** (+9%, against classic's +13% and adjusted's −15%), and the only one that's right for the right reason: its reference ET matches the towers' (1.05) and its crop coefficient matches the crop (03). Classic gets near by having reference ET 15–23% high in summer and a coefficient of 1; adjusted has reference ET 7–15% low in summer and the same coefficient of 1.

## AgWeather v2

AgWeather v2 (`../agweather2`) is being built to serve several gridded weather sources, each chosen for the best match to Wisconsin stations and corrected, falling back to Open-Meteo with the same corrections outside them. Once it's deployed, WISP may switch to it as its weather provider (PLAN.md D6). `weather_at_towers.rb` and `compare_weather.py` are the check for that switch: run the towers with v2's ET0 beside WISP's, and keep whichever matches them better.
