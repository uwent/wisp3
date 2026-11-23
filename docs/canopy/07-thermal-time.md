# 07. Canopy curves in thermal time (2026-11-20)

C23. Scripts: `scripts/thermal_curves.rb` (the conversion), `scripts/thermal_towers.rb`
(the four Central Sands tower seasons), `scripts/thermal_backtest.rb` (the 2026 grower readings), with
`scripts/thermal_common.rb`. All run with `bin/rails runner` through WISP's own `CanopyCurve`, `Canopy`,
`CanopyFit` and `CropEt`, and need the network once for Open-Meteo's archive (cached in `tmp/thermal`).

## Why

The ET validation's whole season (`docs/et-validation/06-season.md`, "Canopy timing" and point 6):
at the four Central Sands potato seasons with recorded cover (2018–2021), canopy reached 80% between
June 11 and 20 whatever the emergence (April 21 to May 23). 10% to 80% took 22–43 days against the
calendar curve's 15, and the curve ran two to three weeks early for April emergence. That is what
growth in thermal time looks like: an April canopy waits for warmth.

Note 01 had looked for a degree-day effect in the 2026 grower readings and found none it could
detect (one season, emergences within a few weeks of each other), and note 02 found AquaCrop's own
GDD crop files 5–10 days off in Wisconsin. So the change here keeps the calendar curves' validated
timing for a typical season and lets the weather move it.

## Method

**Degree days.** AquaCrop's method 3, the one AquaCrop-OSPy's crop files use (`GDDmethod: 3`,
`aquacrop/solution/growing_degree_day.py`; AquaCrop reference manual, ch. 3): the day's max held
between the crop's base and upper temperatures, its min only below the upper, their mean less the
base, at least 0 (`Weather::DegreeDays.aquacrop`, °C days from WISP's °F highs and lows).

**Base and upper temperatures** come from AquaCrop's crop files where they have the crop: potato
2/26 °C (2/30 °C since C25, FAO-56 Rev.1 Table 6.10; days to cover at the towers change by a day at most), maize 8/30 (field corn, corn silage, sweet corn), soybean 5/30, dry bean 9/30 (snap and dry
beans), tomato 7/28 (and pepper, assumed), barley 0/15, wheat 0/26 (and oats, assumed), sugar beet
5/30, sorghum 8/30, alfalfa 5/30 (the perennial regrowth curve). Elsewhere they're assumptions: cool-
season vegetables (peas, crucifers, carrot, beets, celery, leafy greens) 4.4 °C (40 °F, the base of
pea heat units) and 26 °C; warm-season ones (cucurbits, sweet potato) 10 °C (50 °F) and 30 °C; the
generic vegetable curves AquaCrop's default file, 5.5/30 °C.

**Growth rate in degree days** is converted from each calendar curve, not taken from AquaCrop's GDD
files. Each crop gets a typical Wisconsin emergence date (potato and field corn May 15, the 2026
readings' medians; soybean May 20; spring small grains April 25; shell peas and leafy greens May 5;
sweet corn, tomato, pepper and sorghum June 1; cucurbits and sweet potato June 5; snap bean June 15;
the rest in `thermal_curves.rb`, each with its reason). For each of the 20 years 2006–2025 at Hancock
(Open-Meteo's ERA5 archive, `era5_seamless`), the curve emerges on that date and degree days are summed
from it; the growth coefficient per degree day (CC₀ and CCx kept) is the one that best matches the
calendar curve from emergence to full cover over all 20 years (least squares in cover). An AquaCrop
decline starts at the mean degree days to the calendar start day, with its coefficient divided by the
mean degree days a day from the start to the season's end. Potato's July 25 decline is a management
rule and keeps its date (from when the canopy is full, if later, now in degree days). Season lengths
stay in calendar days (`Planting.typical_end`).

In a typical year the thermal curve is the calendar one. Over 2006–2025 at Hancock its day of 80% of
CCx spreads over 6–17 days around the calendar curve's, depending on the crop (potato 25–32 days to
80% of CCx, against the calendar curve's 28; field corn 28–38, against 34).

**At a planting's weather cell** the degree days come from the stored days for the past, the latest
forecast for today and the next 16 days, and the cell's normals after that (and for any day missing
in the past). Normals are the mean high and low for each day of the year over the last 20 complete
years of the same archive, smoothed with a 15-day moving average (`Weather::Normals`, `weather_normals`),
fetched once per cell by `WeatherNormalsJob` (queued with each weather update of a cell people look
at and each scheduled refresh; `bin/rails weather:normals` backfills). A cell without normals yet runs
its curves by calendar days, and the planting page says so. The normals' smoothed temperatures
undercount degree days a little near the base temperature (averaging before clamping); they only stand
in for days past the forecast.

**Fitting to readings** (`CanopyFit`) works on the thermal axis: a shift moves the day the degree days
start from (still in days, held to about 5), a stretch divides the degree days, a height scales the
cover. Its cache key includes a digest of the temperatures from emergence less 15 days to the last
reading, so a revised day or a new forecast refits it. LAI (field corn, `CanopyModel`) stays in days.

## The towers (potato, four seasons)

Desai's group's measured cover at US-CS1 (2018), CS3 (2019), CS4 (2020), CS5 (2021); temperatures from
the archive at each tower, normals from the 20 years before. CS1 and CS3's cover is a template between
recorded phases (06), so CS4 and CS5 carry the most weight.

Days from emergence to 10 / 50 / 80% cover:

| Site | Emergence | °C days (base 2) in the first 30 days | Measured | Calendar | GDD (WISP) | GDD, base 7 °C | AquaCrop PotatoGDD file | AquaCrop PotatoLocalGDD file |
|---|---|---|---|---|---|---|---|---|
| US-CS1 | May 23 | 534 | 6 / 21 / 28 | 15 / 24 / 31 | 12 / 20 / 25 | 9 / 17 / 22 | 9 / 16 / 21 | 17 / 26 / 34 |
| US-CS3 | May 8 | 352 | 10 / 35 / 43 | 15 / 24 / 31 | 21 / 29 / 35 | 24 / 32 / 38 | 18 / 26 / 30 | 27 / 37 / 46 |
| US-CS4 | Apr 25 | 255 | 9 / 43 / 52 | 15 / 24 / 31 | 28 / 35 / 41 | 32 / 39 / 44 | 25 / 31 / 36 | 32 / 43 / 51 |
| US-CS5 | Apr 21 | 261 | 11 / 45 / 51 | 15 / 24 / 31 | 28 / 34 / 43 | 32 / 41 / 46 | 25 / 31 / 35 | 32 / 44 / 51 |

Error, curve − measured, mean absolute (mean), in days:

| Curve | 10, 50 and 80% | 50 and 80% |
|---|---|---|
| Calendar | 11.2 (−6.2) | 13.8 (−12.2) |
| **GDD (WISP: base 2 °C)** | 9.1 (−0.2) | **7.0 (−7.0)** |
| GDD, base 7 °C (converted the same way) | 8.3 (+1.8) | 4.9 (−4.9) |
| AquaCrop PotatoGDD file's rate | 11.1 (−4.2) | 11.5 (−11.5) |
| AquaCrop PotatoLocalGDD file's rate | 7.5 (+7.2) | 2.3 (+1.8) |

Crop ET against the closure-corrected towers (all four seasons, 400 days kept; as in 06, from the
towers' own ET0 and today's `CropEt`):

| Canopy | Development | Full cover | Decline | Vine kill to harvest | Season |
|---|---|---|---|---|---|
| Measured cover | −21% | +7% | +14% | −1% | −2% |
| Calendar curve | −1% | +6% | +25% | −49% | −1% |
| GDD curve | −17% | +6% | +25% | −49% | −6% |
| GDD, base 7 °C | −25% | +6% | +25% | −49% | −8% |
| Calendar + weekly readings | −19% | +6% | +27% | −46% | −6% |
| GDD + weekly readings | −18% | +6% | +27% | −46% | −6% |

## The 2026 grower readings (six crops, 37 series)

The 37 screened series of notes 04 and 06 (`legacy_canopy_export.rb`'s CSV), with temperatures from
the archive at each series' location, rounded to 0.1° (2026 as observed, normals from 2006–2025). The
calendar rows reproduce note 04 and 06's numbers exactly, through `Canopy` rather than
`backtest.py`. Mean |error| in crop ET as a fraction of ET0 (cover points):

| Test | Method | Field corn | Potato | Shell peas | Snap bean | Soybean | Sweet corn | All |
|---|---|---|---|---|---|---|---|---|
| Forward | Calendar, curve only | 0.134 (15) | 0.137 (12) | 0.051 (5) | 0.100 (9) | 0.046 (5) | 0.191 (15) | **0.099** (10) |
| | GDD, curve only | 0.153 (23) | 0.105 (12) | 0.103 (13) | 0.107 (10) | 0.058 (9) | 0.215 (18) | **0.108** (13) |
| | Calendar, fitted + ratio fading (WISP) | 0.068 (7) | 0.062 (6) | 0.055 (5) | 0.042 (5) | 0.048 (5) | 0.093 (10) | **0.057** (6) |
| | GDD, fitted + ratio fading | 0.084 (9) | 0.077 (8) | 0.054 (6) | 0.041 (4) | 0.042 (5) | 0.112 (13) | **0.062** (7) |
| Rest of season | Calendar, curve only | 0.058 (13) | 0.075 (15) | 0.028 (5) | 0.056 (6) | 0.017 (6) | 0.051 (8) | **0.044** (9) |
| | GDD, curve only | 0.066 (18) | 0.058 (15) | 0.058 (10) | 0.057 (8) | 0.023 (8) | 0.061 (9) | **0.048** (12) |
| | Calendar, fitted + ratio fading (WISP) | 0.044 (12) | 0.058 (13) | 0.034 (6) | 0.042 (8) | 0.024 (8) | 0.033 (7) | **0.037** (9) |
| | GDD, fitted + ratio fading | 0.053 (14) | 0.051 (13) | 0.040 (7) | 0.047 (8) | 0.022 (9) | 0.046 (9) | **0.040** (11) |
| Interpolate | Calendar, curve only | 0.070 (12) | 0.075 (13) | 0.040 (5) | 0.092 (9) | 0.031 (7) | 0.105 (11) | **0.062** (10) |
| | GDD, curve only | 0.076 (16) | 0.057 (13) | 0.090 (11) | 0.096 (9) | 0.036 (8) | 0.105 (11) | **0.065** (11) |
| | Calendar, fitted + ratio fading (WISP) | 0.025 (3) | 0.029 (4) | 0.039 (5) | 0.020 (2) | 0.019 (4) | 0.028 (3) | **0.025** (4) |
| | GDD, fitted + ratio fading | 0.035 (6) | 0.033 (4) | 0.039 (5) | 0.017 (2) | 0.017 (4) | 0.042 (4) | **0.028** (4) |

Days to 50% and 80% cover, the curve alone against the readings (linear between them): mean (mean
absolute, SD):

| Crop | Series | Calendar | GDD |
|---|---|---|---|
| Snap bean | 5 | −0.8 (3.2, SD 3.9) | +1.2 (4.2, SD 4.7) |
| Field corn | 8 | −1.3 (4.9, SD 5.0) | −8.6 (8.7, SD 5.6) |
| Potato | 9 | +2.0 (3.6, SD 4.7) | −2.0 (4.2, SD 4.5) |
| Soybean | 10 | +1.5 (1.6, SD 2.2) | −1.3 (2.6, SD 3.0) |
| Shell peas | 3 | +0.3 (1.3, SD 1.4) | −4.2 (5.1, SD 3.3) |
| Sweet corn | 2 | +2.0 (5.0, SD 5.1) | +0.8 (7.3, SD 7.9) |
| All | 37 | +0.7 (3.2, SD 4.2) | −2.9 (5.0, SD 5.7) |

## What it shows

1. **For potato emerging over a month, thermal time removes most of the dependence on the emergence
   date.** The calendar curve's error at 80% cover runs from +3 days (May 23) to −21 (April 21);
   the GDD curve's from −3 to −11. Mean absolute error at 50% and 80% halves (13.8 → 7.0 days) and
   most of the bias from emergence date is gone; what's left is mostly a level (1 to 11 days early,
   mean −7): the towers' canopies grew more slowly than the 2026 growers' readings that the calendar curve
   matches (the calendar curve is 3 days late at CS1, emerged in warm late May). AquaCrop's
   PotatoLocalGDD rate fits the towers (2.3 days) but runs 7.6 days late on the 2026 readings (02), so
   the towers' level isn't adopted from four seasons, two of them templated.
2. **The 10% point isn't fitted by any curve**: measured cover reaches 10% 6–11 days after emergence
   at every tower, then grows more slowly than any AquaCrop curve. That's the curve's shape, not its
   clock.
3. **Getting the canopy right makes development's crop ET low**, as 06's point 3 found with the
   measured cover: −17% (GDD curve) against −21% (measured), where the calendar curve's −1% came from
   running ahead of these canopies. Soil evaporation at low cover is the remaining gap, and is the ET
   engine's to fix, not the canopy's. With weekly readings the two curves give the same ET (−18%/−19%).
4. **In the 2026 grower readings GDD is a little worse than calendar days for most crops** (5 of 6 on
   days to 50/80%; overall 5.0 against 3.2 days, ET error 0.108 against 0.099 forward with the curve
   alone, 0.062 against 0.057 with WISP's fit to readings). This test favours the calendar curves:
   their timings were checked against these same readings (soybean and sweet corn were adjusted to
   them, notes 02 and 03), and the GDD curves were converted to a 20-year typical season, not to 2026.
   The SD of the errors, which doesn't count that offset, is also a little higher with GDD (5.7 against
   4.2 days), so GDD doesn't explain the differences between these series either, as note 01 found.
5. **Field corn is the clear miss** (−8.6 days): late May and June 2026 were warm at base 8 °C (382 °C
   days May 15–June 20 near Hancock, against 342 from the normals), but the readings reached 80% at day
   37–40, slower than the calendar curve's 35. The eight series are about three growers' (six share
   the same readings), entered by eye. Peas (3 series) and sweet corn (2) are too few to say.
6. **Potato in the 2026 readings agrees with the towers**: with the curve alone GDD is better forward
   (0.105 against 0.137), over the rest of the season (0.058 against 0.075) and between readings
   (0.057 against 0.075), though slightly worse forward once readings are fitted (0.077 against
   0.062).
7. **Base 7 °C** (converted the same way) fits the towers' timing a little better than AquaCrop's 2 °C
   (4.9 against 7.0 days) but makes development ET worse (−25%), and 7 °C has no AquaCrop file behind
   it, so WISP keeps 2 °C.

## How sure

- **Four tower seasons, one potato field each, two with templated cover.** They show the emergence-
  date effect clearly but can't fit a level; one season of grower readings can't test the effect,
  because its emergences were within about three weeks and its weather near normal.
- **Grower readings are by eye, often with an emergence date entered later**, and several series are
  one grower's copied across fields (note 01).
- **The assumed base temperatures** (cool- and warm-season vegetables, pepper, oats) have no Wisconsin
  readings behind them at all; they only move these crops' timing in unusual springs.
- **ERA5 at 0.1° against WISP's stored weather** (NBM and best match): the normals and the conversion
  use ERA5; a planting's past days use WISP's own weather. A systematic difference between them shifts
  the curve by its share of the degree days (a 1 °C warmer stored day is 7% more potato degree days at
  15 a day).

## Recommendation

Thermal time is clearly better for **potato**, WISP's main crop, and is physiologically the standard
for canopy development; keep it there. For the other crops the one season of evidence is neutral to
slightly negative (field corn negative), and in-sample for the calendar curves. Two options:

- **Keep GDD for every crop** (as built): a typical season is unchanged by construction, a warm or cool
  spring moves the curve the way crop physiology says it should, and readings correct the rest.
- **Keep GDD for potato only** until the 2027 readings can be checked: delete the other crops'
  `thermal:` lines in `db/reference/canopy_curves.yml` (each crop then runs by calendar days; the
  machinery stays). Field corn and corn silage are the first candidates.

Either way, rerun `thermal_backtest.rb` on the 2027 season's readings, which will be the first season
whose readings weren't used to make the curves.

## Decision (2026-11-19)

Ben chose to run potato on degree days and keep the other crops on calendar days for now: potato's gain is clear at the towers and on the grower readings with the curve alone, while the other crops did a little worse than their calendar curves on the 2026 readings those curves were tuned to. Their conversions stay in `canopy_curves.yml` as `thermal_candidate:` (nothing in the app runs on them) to check against the 2027 readings; renaming a crop's line to `thermal:` puts it on degree days.

