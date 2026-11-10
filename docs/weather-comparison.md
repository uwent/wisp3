# AgWeather vs Open-Meteo

Generated 2026-11-10 by `bin/rails weather:compare` (PLAN.md §8.4, §8.5). 12 points × 2025, 2026 seasons (Apr 1 – Sep 30), daily values from AgWeather (legacy WISP's source) and from Open-Meteo's historical-forecast API at each point's O1280 cell. Points: Hancock, Plainfield, Coloma, Almond, Bancroft, Plover, Wautoma, Grand Marsh, Arena, Spring Green, Antigo, Janesville.

Sources: each Open-Meteo model alone with Open-Meteo's own ET0; **WISP 2026**, NBM then best_match hour by hour with Open-Meteo's ET0 (what WISP used through the 2026 season); and **WISP corrected**, the same hours with the shortwave and humidity corrections and WISP's FAO-56 ET0 (D12, what WISP uses from 2027). Precipitation isn't corrected, so the two WISP rows share it.

Errors are the source minus AgWeather, in inches per day, over days where both have a value.

## Reference ET

| Model | days | reference mean | mean | bias | ratio | mae | rmse | r |
|---|---|---|---|---|---|---|---|---|
| Open-Meteo best_match | 4332 | 0.145 | 0.156 | 0.011 | 1.08 | 0.025 | 0.033 | 0.87 |
| NBM | 4248 | 0.145 | 0.149 | 0.003 | 1.02 | 0.023 | 0.029 | 0.90 |
| WISP 2026 (NBM, best_match; Open-Meteo ET0) | 4332 | 0.145 | 0.148 | 0.003 | 1.02 | 0.023 | 0.029 | 0.90 |
| WISP corrected (FAO-56 ET0, corrected shortwave) | 4332 | 0.145 | 0.132 | -0.013 | 0.91 | 0.027 | 0.033 | 0.89 |

Ratio to AgWeather's ET by month:

| Source | Apr | May | Jun | Jul | Aug | Sep |
|---|---|---|---|---|---|---|
| Open-Meteo best_match | 1.27 | 1.26 | 1.08 | 0.95 | 1.00 | 1.03 |
| NBM | 1.17 | 1.15 | 1.04 | 0.93 | 0.96 | 0.98 |
| WISP 2026 (NBM, best_match; Open-Meteo ET0) | 1.17 | 1.15 | 1.04 | 0.93 | 0.96 | 0.99 |
| WISP corrected (FAO-56 ET0, corrected shortwave) | 1.04 | 1.04 | 0.92 | 0.82 | 0.85 | 0.87 |

## Precipitation

| Model | days | reference mean | mean | bias | ratio | mae | rmse | r | rain days reference | rain days | rain day agreement |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Open-Meteo best_match | 4392 | 0.158 | 0.125 | -0.032 | 0.79 | 0.129 | 0.376 | 0.60 | 1425 | 844 | 0.85 |
| NBM | 4392 | 0.158 | 0.146 | -0.011 | 0.93 | 0.094 | 0.223 | 0.79 | 1425 | 1602 | 0.87 |
| WISP 2026 (NBM, best_match; Open-Meteo ET0) | 4392 | 0.158 | 0.146 | -0.011 | 0.93 | 0.094 | 0.223 | 0.79 | 1425 | 1602 | 0.87 |
| WISP corrected (FAO-56 ET0, corrected shortwave) | 4392 | 0.158 | 0.146 | -0.011 | 0.93 | 0.094 | 0.223 | 0.79 | 1425 | 1602 | 0.87 |

Rain days: days with at least 0.05 in; agreement is the share of days where both sources agree on wet or dry.

## Effect on a standard field

A potato field on sand (FC 0.15, PWP 0.05, 16 in roots, MAD 0.5, emergence May 20, full cover by July 1) run through the WISP 3 engine on each source's weather, irrigated 0.75 in the day after AD reaches 0. Irrigations per season (first irrigation date):

| Point | Year | AgWeather | Open-Meteo best_match | NBM | WISP 2026 (NBM, best_match; Open-Meteo ET0) | WISP corrected (FAO-56 ET0, corrected shortwave) |
|---|---|---|---|---|---|---|
| Hancock | 2025 | 8 (Jul 4) | 16 (Jun 5) | 8 (Jun 16) | 8 (Jun 16) | 5 (Jun 22) |
| Plainfield | 2025 | 9 (Jul 5) | 15 (Jun 5) | 7 (Jun 16) | 7 (Jun 16) | 5 (Jun 20) |
| Coloma | 2025 | 9 (Jun 23) | 16 (Jun 5) | 9 (Jun 15) | 9 (Jun 15) | 6 (Jun 16) |
| Almond | 2025 | 8 (Jul 10) | 16 (Jun 6) | 8 (Jun 18) | 8 (Jun 18) | 5 (Jun 22) |
| Bancroft | 2025 | 8 (Jul 5) | 17 (Jun 8) | 9 (Jun 18) | 9 (Jun 18) | 5 (Jun 22) |
| Plover | 2025 | 8 (Jul 4) | 17 (Jun 8) | 10 (Jun 23) | 10 (Jun 23) | 5 (Jul 16) |
| Wautoma | 2025 | 10 (Jul 11) | 19 (Jun 12) | 10 (Jun 15) | 11 (Jun 15) | 7 (Jun 16) |
| Grand Marsh | 2025 | 9 (Jun 23) | 15 (Jun 5) | 9 (Jun 15) | 9 (Jun 15) | 6 (Jun 16) |
| Arena | 2025 | 12 (Jun 15) | 16 (Jun 11) | 9 (Jun 21) | 9 (Jun 21) | 6 (Jun 23) |
| Spring Green | 2025 | 11 (Jun 15) | 18 (Jun 6) | 11 (Jun 15) | 11 (Jun 15) | 9 (Jun 22) |
| Antigo | 2025 | 10 (Jul 4) | 15 (Jun 5) | 9 (Jul 5) | 8 (Jul 5) | 5 (Jul 16) |
| Janesville | 2025 | 12 (Jun 13) | 15 (Jun 14) | 13 (Jun 14) | 13 (Jun 14) | 9 (Jun 14) |
| Hancock | 2026 | 13 (Jun 8) | 17 (Jun 3) | 11 (Jun 4) | 11 (Jun 4) | 7 (Jun 5) |
| Plainfield | 2026 | 10 (Jun 8) | 18 (Jun 3) | 11 (Jun 5) | 11 (Jun 5) | 8 (Jun 5) |
| Coloma | 2026 | 13 (Jun 22) | 18 (Jun 2) | 11 (Jun 4) | 11 (Jun 4) | 8 (Jun 5) |
| Almond | 2026 | 13 (Jun 23) | 18 (Jun 5) | 12 (Jun 5) | 12 (Jun 5) | 8 (Jun 5) |
| Bancroft | 2026 | 13 (Jun 10) | 17 (Jun 5) | 10 (Jun 5) | 10 (Jun 5) | 8 (Jun 5) |
| Plover | 2026 | 11 (Jun 24) | 18 (Jun 5) | 11 (Jun 5) | 11 (Jun 5) | 6 (Jul 14) |
| Wautoma | 2026 | 14 (Jun 8) | 18 (Jun 2) | 13 (Jun 4) | 13 (Jun 4) | 9 (Jun 5) |
| Grand Marsh | 2026 | 12 (Jun 21) | 17 (Jun 2) | 10 (Jun 4) | 10 (Jun 4) | 7 (Jun 5) |
| Arena | 2026 | 15 (Jun 5) | 19 (Jun 2) | 9 (Jun 4) | 9 (Jun 4) | 5 (Jun 5) |
| Spring Green | 2026 | 15 (Jun 5) | 19 (Jun 2) | 10 (Jun 4) | 10 (Jun 4) | 7 (Jun 5) |
| Antigo | 2026 | 11 (Jun 29) | 17 (Jun 4) | 9 (Jun 8) | 9 (Jun 8) | 5 (Jul 15) |
| Janesville | 2026 | 13 (Jun 17) | 16 (Jun 2) | 10 (Jun 3) | 10 (Jun 3) | 8 (Jun 4) |

Average difference from AgWeather:

- **Open-Meteo best_match**: +5.8 irrigations per season on average (range 3 to 9); first irrigation -16.5 days vs AgWeather.
- **NBM**: -1.2 irrigations per season on average (range -6 to 2); first irrigation -10.2 days vs AgWeather.
- **WISP 2026 (NBM, best_match; Open-Meteo ET0)**: -1.2 irrigations per season on average (range -6 to 2); first irrigation -10.2 days vs AgWeather.
- **WISP corrected (FAO-56 ET0, corrected shortwave)**: -4.5 irrigations per season on average (range -10 to -2); first irrigation -4.1 days vs AgWeather.

The correction itself (WISP corrected minus WISP 2026): -3.3 irrigations per season on average (range -5 to -2).
