# 04. Backtest: combining readings with the curve (2026-10-15)

Phase 6.7, step A.4. Script: `scripts/backtest.py`. Data: the 37 screened Wisconsin 2026 series
from note 01 (field corn 8, potato 9, shell peas 3, snap bean 5, soybean 10, sweet corn 2), with
the curves from note 03.

## Method

Two tests on each series:

- **Forward** (the day-to-day case): with the readings so far, predict the next one, usually a week
  ahead. This runs while the canopy is developing, up to the first reading of 80% or more.
- **Interpolate:** hide every other reading and predict it from the rest.

Error is |predicted − read| in crop ET as a fraction of et0, through the A3600 percent cover
regressions (`CropEt`), so a miss above 80% cover costs nothing. Cover points are in brackets.

Methods:

| Method | Canopy on a day |
|---|---|
| linear (now) | Straight lines from 0 at emergence through the readings; the last one held |
| curve only | The crop's curve, readings ignored |
| scaled | The curve times one factor, fitted (least squares) to all readings so far |
| shifted | The curve moved earlier or later by a fitted number of days |
| shift + scale | Both fitted |
| ratio between readings | The curve times a ratio: reading ÷ curve at each reading, 1 at emergence, linear between readings, the last one held after. Passes through every reading. |

## Results

**Forward**, mean |error| in ET/et0 (cover points):

| Method | Field Corn | Potato | Shell peas | Snap bean | Soybean | Sweet Corn | All |
|---|---|---|---|---|---|---|---|
| linear (now) | 0.151 (14) | 0.184 (16) | 0.128 (12) | 0.093 (9) | 0.112 (11) | 0.126 (11) | **0.133** (12) |
| curve only | 0.134 (15) | 0.137 (12) | 0.051 (5) | 0.100 (9) | 0.046 (5) | 0.191 (15) | **0.099** (10) |
| scaled | 0.071 (12) | 0.059 (12) | 0.077 (8) | 0.066 (12) | 0.055 (6) | 0.141 (20) | **0.068** (10) |
| shifted | 0.073 (8) | 0.055 (7) | 0.060 (6) | 0.061 (8) | 0.057 (6) | 0.132 (14) | **0.065** (7) |
| shift + scale | 0.099 (11) | 0.117 (12) | 0.062 (7) | 0.055 (6) | 0.058 (7) | 0.116 (11) | **0.081** (9) |
| ratio between readings | 0.073 (11) | 0.062 (11) | 0.064 (7) | 0.055 (7) | 0.053 (6) | 0.155 (20) | **0.066** (9) |

**Interpolate:**

| Method | Field Corn | Potato | Shell peas | Snap bean | Soybean | Sweet Corn | All |
|---|---|---|---|---|---|---|---|
| linear (now) | 0.037 (4) | 0.044 (4) | 0.033 (7) | 0.014 (2) | 0.020 (3) | 0.024 (3) | **0.030** (3) |
| curve only | 0.070 (12) | 0.075 (13) | 0.040 (5) | 0.092 (9) | 0.031 (7) | 0.105 (11) | **0.062** (10) |
| scaled | 0.068 (8) | 0.089 (10) | 0.040 (6) | 0.087 (8) | 0.037 (6) | 0.106 (10) | **0.066** (8) |
| shifted | 0.032 (8) | 0.032 (10) | 0.032 (5) | 0.064 (7) | 0.030 (7) | 0.070 (8) | **0.038** (8) |
| shift + scale | 0.037 (4) | 0.038 (5) | 0.032 (4) | 0.062 (7) | 0.034 (5) | 0.072 (7) | **0.041** (5) |
| ratio between readings | 0.028 (4) | 0.033 (5) | 0.036 (5) | 0.021 (3) | 0.019 (3) | 0.031 (4) | **0.026** (4) |

Ratio between readings, by how far the last reading is from the curve (forward test, all crops):

| Last reading ÷ curve | Predictions | Linear | Ratio between readings |
|---|---|---|---|
| under 0.5 | 18 | 0.129 | 0.105 |
| 0.5–0.67 | 7 | 0.209 | 0.144 |
| 0.67–0.8 | 11 | 0.136 | 0.042 |
| 0.8–1.25 | 106 | 0.103 | 0.040 |
| 1.25–1.5 | 23 | 0.185 | 0.055 |
| 1.5–2 | 16 | 0.151 | 0.082 |
| over 2 | 36 | 0.167 | 0.116 |

## Findings

1. **Following the curve halves the error of the next week's canopy.** Forward, every curve method
   is at 0.065–0.081 of et0, against 0.133 for straight lines. At et0 0.2 in/day, that's about
   0.013 against 0.027 in/day, roughly 0.1 in a week less ET error between readings.
2. **One scale factor isn't enough.** It forecasts well, but it can't pass through every reading,
   so it's twice as wrong as straight lines on the days between readings (0.066 against 0.030).
   A fitted shift has the same problem, and shift + scale overfits two or three early readings.
3. **Ratio between readings is best overall:** as good as any method forward (0.066), and best
   between readings (0.026). It never contradicts an entered reading, follows the crop's shape
   between and after readings (including potato's August decline), and with no readings it is
   the curve. **Recommended** as the `curve` setting.
4. **Breaking to straight lines wouldn't help.** Ratio between readings beats straight lines in
   every band, even when the readings are 2× or ½ the curve. Large ratios come mostly from the
   first readings, when the curve is still tiny, or from an emergence date that's off. Dropping
   to straight lines outside [½, 2] makes the forward error worse (0.076 against 0.066), and
   outside [⅔, 1.5] worse still (0.084).
5. **A warning catches questionable data instead.** Fit a time shift to the readings between 10%
   and 80% cover (at least two). If the crop is more than 7 days ahead of or behind the curve,
   say so and suggest checking the emergence date. That flags 3 of 37 series, all questionable:
   a field corn series whose readings jump around (50% on day 34, then 28% on day 35), and the
   two potato fields that emerged May 27–28 and reached 80% in 18–24 days (likely a late
   emergence date). A reading that falls by more than 5 points while the canopy is still growing
   (before the curve's decline) is worth the same warning.

**Caveats:** the soybean, shell pea and sweet corn curves were adjusted to these same readings
(note 03), so "curve only" is flattered for them. Potato, field corn and snap bean use unadjusted
published curves, and the result holds there too: forward 0.062 / 0.073 / 0.055 for ratio between
readings, against 0.184 / 0.151 / 0.093 for straight lines. Sweet corn is the exception: with two series, ratio between readings forecasts worse than
straight lines (0.155 against 0.126), because its curve is still uncertain. One season, few growers.

## Recommendation

- **`curve` (the default where a crop has one): ratio between readings.** The ratio is reading ÷
  curve at each reading (curve floored at 1% cover), 1 at emergence, linear in time between
  readings, and held after the last reading. Cover is capped at 100%.
- **No automatic break to straight lines.** Instead, a **warning** when the readings run more than
  7 days ahead of or behind the curve, or fall during growth. It names the gap ("your readings
  run about 9 days ahead of the potato curve; check the emergence date") and stays on the
  curve. Growers who prefer straight lines can still choose `linear` per planting.
- The decision recorded earlier (warn **and** break from the curve when readings are far off) is
  replaced by this, pending Ben.

**Revised 2026-10-29 (note 06):** the curve is now fitted to the readings first, and the last
reading's ratio eases back to 1 over 14 days instead of being held, which cut the error over the
rest of the season by about 40%.

**Implemented (2026-10-15):** ratio between readings in `Canopy` (the `curve` setting), the warning
as `Canopy#check`, shown through `PlantingTasks` on the field page, dashboard and daily email.
Ben agreed to the warning in place of an automatic switch to straight lines.
