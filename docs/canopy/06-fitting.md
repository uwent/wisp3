# 06. Fitting the curve to readings, and letting a reading's effect fade (2026-10-29)

Phase 6.7, follow-up to note 04. Script: `scripts/backtest.py` (the same data: 37 screened Wisconsin
2026 series). Errors are in crop ET as a fraction of et0, as in note 04.

## Why

Ratio between readings (note 04) passes through every reading, but holds the last reading's ratio
for the rest of the season. A reading taken while the curve is still near 0 can carry a large
ratio: one field corn LAI reading of 0.3 on day 20, when the curve says 0.027, took the canopy to
the curve's peak (LAI 4.07) by day 40 and held it there, where the curve says 0.9. Ben also asked
that sparse readings barely move the default curve, that more readings fit it more closely, and
that a reading still be used exactly as entered.

## Method

Two steps (`CanopyFit`, `Canopy`):

1. **Fit the curve:** a shift (days earlier or later), a stretch (growth slower or faster, about
   emergence) and a height (fuller or thinner), each held toward the typical curve. The fit
   minimises Σ ((reading − curve) / noise)² + (shift / 5 d)² + (ln stretch / 0.15)² +
   (ln height / 0.10)²: penalized least squares, or equally a Bayesian fit with a normal prior on
   each. The penalties are how much crops vary from field to field (Wisconsin 2026: potato reached
   50% anywhere from day 14 to 26); noise is how precise a reading is. Readings of 80% or more count
   as "at least 80" (growers stop there and hold, note 01). The search is a coarse grid (shift
   −15…15 days in steps of 3, stretch and height in steps of e^0.1) refined around its best (steps of
   1 day and e^0.05), about 430 curves per fit; stretch spans e^±0.3 and height e^±0.2. Potato's
   calendar decline keeps its date.
2. **Pass through the readings:** the fitted curve times a ratio (reading ÷ fitted curve at each
   reading, 1 at emergence, linear between readings), which **eases back to 1 over 14 days after
   the last reading** instead of being held.

## Results

Mean error, forward (next reading) / rest of season (every later reading, from the readings so far)
/ interpolate (every other reading hidden). "Unadjusted" is potato, field corn and snap bean, whose
curves are published ones not adjusted to these readings; soybean, shell peas and sweet corn were
adjusted to them (note 03), which flatters any method that stays close to the curve.

| Method | Unadjusted | All |
|---|---|---|
| Straight lines (legacy) | 0.146 / 0.426 / 0.035 | 0.133 / 0.398 / 0.030 |
| Curve only | 0.125 / 0.063 / 0.076 | 0.099 / 0.044 / 0.062 |
| Ratio between readings, held (note 04) | 0.064 / 0.076 / 0.029 | 0.066 / 0.072 / 0.026 |
| Ratio fading, typical curve | 0.061 / 0.048 / 0.029 | 0.054 / 0.035 / 0.027 |
| **Fitted curve + ratio fading** | **0.059 / 0.048 / 0.026** | **0.057 / 0.037 / 0.025** |

**With only the first n readings** (fitted + ratio fading): how far the fit moves the curve, and the
error over the rest of the season.

| Readings | Mean \|shift\| | Mean \|stretch − 1\| | Mean \|height − 1\| | Curve only | Ratio held | Fitted + fading |
|---|---|---|---|---|---|---|
| 1 | 0.6 d | 0.01 | 0.00 | 0.060 | 0.098 | 0.055 |
| 2 | 1.3 d | 0.01 | 0.00 | 0.056 | 0.103 | 0.050 |
| 3 | 1.8 d | 0.03 | 0.01 | 0.048 | 0.062 | 0.039 |
| 5 | 2.2 d | 0.04 | 0.02 | 0.028 | 0.037 | 0.021 |

**Sensitivity** (forward / rest / interpolate):

- Reading noise, unadjusted crops: 5 points 0.056 / 0.047 / 0.024 (one reading moves the curve
  1.5 d on average, at most 6), 8 points 0.058 / 0.048 / 0.026, **10 points 0.059 / 0.048 / 0.026
  (0.6 d, at most 5)**, 15 points 0.058 / 0.048 / 0.027 (0.4 d).
- Penalties twice as loose, all crops: 0.060 / 0.040; half: 0.055 / 0.036. On the unadjusted crops
  the proposed strength is as good as any.
- Fade, unadjusted crops: 7 days 0.080 / 0.055 / 0.029 (typical curve), 14 days 0.059 / 0.048 /
  0.026 (fitted), 21 days 0.057 / 0.045 / 0.026 (fitted), 28 days no better.

## Findings

1. **Fading the last reading's ratio is the main gain.** It cuts the error over the rest of the
   season by about 40% (0.076 to 0.048 on the unadjusted crops), and it ends the early-reading
   problem: a reading's ratio now lasts two weeks, not the season.
2. **Fitting adds a smaller gain, and behaves as asked.** On the unadjusted crops it improves the
   next reading (0.061 to 0.059) and the days between readings (0.029 to 0.026, the best of any
   method). One reading moves the curve 0.6 days on average, five readings 2.2 days. On the adjusted
   crops it looks slightly worse than fading alone, as expected when the typical curve was fitted
   to these same readings.
3. **Accuracy is flat across noise of 5–15 points**, so noise was chosen for behaviour: at 10, a
   lone reading rarely moves the curve far. Readings scatter 4–9 points (median 6) around their own
   best-fitting curves, in sample, so 10 is a reasonable allowance for readings by eye and
   emergence dates that may be off. A single reading on the steepest part of the curve, 30 points
   off, still moves it a few days (potato, 6 days ahead on day 20: shift −3 d and growth 10%
   faster), as such a reading says a lot about timing; the reading itself is used exactly either way.
4. **14 or 21 days of fade are equivalent** within this data (0.002–0.003). 14 days keeps a single
   reading's effect short.

**Caveats:** one season, few growers. Readings mostly stop at 80%, so the decline and the height
can't be checked: the fit's effect on a long season's decline (Ben's case for the stretch) is
untested, and the height mostly matters for display. The LAI fit (field corn) uses noise 0.4 LAI,
the same share of the peak as 10 points of cover, a judgment with no LAI readings to test it.

## Implemented (2026-10-29)

Fitted curve + ratio fading, with the penalties and noise above and a 14-day fade, as the `curve`
setting (the approach agreed with Ben; the constants are in `CanopyFit` and `Canopy`, for his
review). The canopy check (note 04, finding 5) keeps its own unpenalized shift fit: a penalized fit
understates how far off readings are, and the check's 7-day threshold was set on the unpenalized
one. Fits are cached by their readings and curve (`CanopyFit.fetch`): about 30 ms uncached for a
dozen readings.
