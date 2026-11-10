# Weather corrections

Tables for the corrections WISP applies to Open-Meteo's hourly weather (PLAN.md D12, §8.5),
described in `corrections.yml` and applied by `Weather::Corrections` as hours are aggregated to days.

| File | Label | Fitted | Source |
|---|---|---|---|
| `openmeteo_shortwave_correction.json` | `openmeteo-shortwave v1` | 2026-10-31 | `ncep_nbm_conus` then `best_match` (historical-forecast) at 80 Wisconet stations, 2025–2026, against the stations' hourly pyranometer means |
| `openmeteo_rh_map.json` | `openmeteo-rh v1` | 2026-10-31 | the same, against AgWeather v2's hourly RH at the stations' cells |

ET0 computed here (`Weather::Fao56`) is labelled `et0-fao56 v1`; it has no table.

Copied unchanged from AgWeather v2 (github.com/uwent/agweather2), `packages/agdata/src/agdata/data/`,
at commit `bbb0a6dc26b0d37321bc44aef923968bd2789c74` (2026-11-10). v2 applies them in
`agdata.sources.openmeteo.correct`; `agdata.shortwave.correct_w_m2` and `agdata.calibration.map_rh`
are the reference implementations.

To update a table: copy the new file from v2 byte for byte (Prettier skips these files), note the
commit here, and refetch stored weather (`bin/rails weather:recorrect`) so every day is on one
version. The label each day records comes from the table's `version`.

Table layouts:

- Shortwave: `clearness` (bin centres, the hour's Rs over FAO-56 clear-sky Rso) and `factor`. Hours
  whose clear-sky Rso is 1 W/m² or less take clearness 0 (so the first factor).
- RH: `map[season][lead group][solar hour][RH]`, seasons centred on days of year
  `season_day_of_year` (blended around the year's end), one lead group, 24 solar-hour bins centred
  on h + 0.5, and the mapped RH at each whole percent of `rh_grid` (0–100).
