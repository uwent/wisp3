# Crop ET against the Central Sands flux towers

Whether WISP 3's crop ET (FAO-56 Penman-Monteith ET0 × the crop's coefficient × canopy) matches the water use measured by eddy-covariance towers over irrigated potato and corn in Wisconsin's Central Sands, and what potato's full-cover coefficient should be. Started 2026-11-19, before the potato growers' demonstration. The About page gets a summary once the results are in.

Notes, in order:

- `01-background.md`: the two Talib et al. papers, legacy WISP's ET and its "adjusted" variant, where WISP 3 stands, and the question this work answers.
- `02-data.md`: the AmeriFlux sites and files, what each season measured, energy balance closure, what's missing, and Desai's group's crop dates, irrigation logs and canopy cover: what's usable and what isn't.
- `03-results.md`: potato at full cover (July, six seasons) on the towers' own weather: the coefficient the towers imply, closure and how much it matters, WISP 3 and legacy's two equations against them, and net longwave.
- `04-weather.md`: the same with the weather each model really uses: WISP 3's corrected Open-Meteo weather, and AgWeather's gridded ET, classic and adjusted.
- `05-corn.md`: the two short corn records (inconclusive).
- `06-season.md`: the whole potato season (2018–2021, with Desai's group's crop dates and canopy cover) through WISP 3's own canopy and `CropEt`, by phase, by cover, and after vine kill, with the changes it suggests.

Still to do: Ben's decision on 06's suggested changes (soil evaporation at low cover and after vine kill, the early August decline, canopy timing), then the About page's summary.

**In short (2026-11-19):**

- At full cover the towers measure potato at 0.87 × FAO-56 ET0 as recorded. They account for 80% of the available energy; with the rest put back, potato's coefficient is about 1.09–1.12 at the best-instrumented seasons (up to 1.2 on more generous readings of closure). FAO-56 gives 1.15, which WISP adjusts to 1.12 for the humid Central Sands July.
- On the towers' weather, WISP 3 is 3% above the closure-corrected towers. On its own weather (Open-Meteo, corrected), 9% above (3% without the 2023 drought season); its reference ET is 5% above the towers', where Open-Meteo's own is 18% above.
- Legacy's classic equation is high either way (+42% against the towers as recorded, on AgWeather's own data). Talib et al.'s adjusted equation fits the towers as recorded (+7%), as it was fitted to, and is 15% below them once closure is corrected. Their diagnosis of legacy's longwave error holds against the towers' radiometers.
- So the funded research found a real flaw in legacy WISP, and its towers are what WISP 3 is validated against.
- Over the whole season (06, four seasons) WISP 3's total is within 1–6% of the corrected towers, but by cancelling errors: it misses soil evaporation at low cover (−21% in development with the measured canopy) and after vine kill (−49%), and holds full Kc into early August, when the towers' coefficient has eased to 0.97 (+13%). Potato's curve also grows faster than these canopies did, two to three weeks early for April emergence.
- **Since C22 (2026-11-19) WISP 3 uses FAO-56's dual crop coefficient** (a basal coefficient from the canopy, easing to harvest's over the late season, plus soil evaporation from the wetted surface), which those results argued for. On the same four seasons (06, "After the change") it is −1% at full cover (C21 was +6–7%), −5% to +2% in the decline (+14–27%) and 0.97 in early August (the towers' 0.97); development and vine kill to harvest now run high rather than low (+10% and +11%, from −21% and −49%), with bare ground below 10% cover the most over on few days. The season total is +4–6% on sand. The full-cover comparisons in 03–04 were made with C21's Kc mid (1.15, about 4% above C22's Kcb mid of 1.10 with a closed canopy's evaporation).
- **With the canopy in degree days too (C23)**, potato's default curve keeps time with these seasons (7 days off on average at 50% and 80% cover, against 14 by the calendar), and on sand every phase is within −1% to +11% of the corrected towers, the season +4% (06, last section).

Raw downloads stay out of git (`tmp/ameriflux/`; AmeriFlux data are CC BY 4.0, cited by each site's DOI). Scripts are in `scripts/`, as in `docs/canopy/`: `inventory.py`, `season_data.py`, `et0.py` and `compare.py` (02–03), `weather_at_towers.rb` and `compare_weather.py` (04), `corn.py` (05), `season.rb` (06, through `bin/rails runner`).
