# Crop ET against the Central Sands flux towers

Whether WISP 3's crop ET (FAO-56 Penman-Monteith ET0 × the crop's coefficient × canopy) matches the water use measured by eddy-covariance towers over irrigated potato and corn in Wisconsin's Central Sands, and what potato's full-cover coefficient should be. Started 2026-11-19, before the potato growers' demonstration. The About page gets a summary once the results are in.

Notes, in order:

- `01-background.md`: the two Talib et al. papers, legacy WISP's ET and its "adjusted" variant, where WISP 3 stands, and the question this work answers.
- `02-data.md`: the AmeriFlux sites and files, what each season measured, energy balance closure, and what's missing.
- `03-results.md`: potato at full cover (July, six seasons) on the towers' own weather: the coefficient the towers imply, closure and how much it matters, WISP 3 and legacy's two equations against them, and net longwave.
- `04-weather.md`: the same with the weather each model really uses: WISP 3's corrected Open-Meteo weather, and AgWeather's gridded ET, classic and adjusted.
- `05-corn.md`: the two short corn records (inconclusive).

Still to do: the whole potato season (development and decline), once Desai's group sends the crop dates and canopy cover.

**In short (2026-11-19):**

- At full cover the towers measure potato at 0.87 × FAO-56 ET0 as recorded. They account for 80% of the available energy; with the rest put back, potato's coefficient is about 1.09–1.12 at the best-instrumented seasons (up to 1.2 on more generous readings of closure). FAO-56 gives 1.15, which WISP adjusts to 1.12 for the humid Central Sands July.
- On the towers' weather, WISP 3 is 3% above the closure-corrected towers. On its own weather (Open-Meteo, corrected), 9% above (3% without the 2023 drought season); its reference ET is 5% above the towers', where Open-Meteo's own is 18% above.
- Legacy's classic equation is high either way (+42% against the towers as recorded, on AgWeather's own data). Talib et al.'s adjusted equation fits the towers as recorded (+7%), as it was fitted to, and is 15% below them once closure is corrected. Their diagnosis of legacy's longwave error holds against the towers' radiometers.
- So the funded research found a real flaw in legacy WISP, and its towers are what WISP 3 is validated against.

Raw downloads stay out of git (`tmp/ameriflux/`; AmeriFlux data are CC BY 4.0, cited by each site's DOI). Scripts are in `scripts/`, as in `docs/canopy/`: `inventory.py`, `et0.py` and `compare.py` (02–03), `weather_at_towers.rb` and `compare_weather.py` (04), `corn.py` (05).
