# 01. Legacy percent cover readings (2026-10-15)

Phase 6.7, step A.2. Source: `legacy_canopy_export.rb` run on legacy production (2026-10-15),
anonymised (random planting numbers, locations rounded to 0.1°).

## What's there

- 578 readings from 56 plantings, **all from the 2026 season**. Legacy WISP deleted each season's data
  on February 15, so nothing earlier exists.
- The extract itself isn't committed (too little of lasting value); this note keeps what it showed.
- By crop (plantings / readings): soybean 15 / 156, field corn 15 / 172, potato 10 / 102,
  snap bean 5 / 46, shell peas 3 / 27, other 3 / 18, sweet corn 2 / 31, alfalfa 1 / 21,
  wheat 1 / 4, leafy greens 1 / 1. No other crop has any readings.

## Quality

- **Emergence left at the May 1 default:** 11 plantings. Their days after emergence are unreliable
  (one field corn planting reaches 20% only at "day 34"), so they are excluded from timing fits.
- **Copied series:** several groups of plantings share the same dates and values (7 field corn
  plantings emerged May 18, 6 soybeans emerged May 14). These are most likely one grower's fields
  scouted as a block. Each group counts as one series.
- **Interpolated values:** readings such as 51.43, 64.28, 68.57 on consecutive days are linear
  steps, not measurements. They were probably filled in or copied from WISP's calculated cover.
  They are harmless for shape, but they inflate the reading counts.
- **Readings stop at 80%:** many growers record 80% and hold it. That's the cover where WISP's ET
  stops rising and where the guidance says readings can stop. Others go to 100%. So **maximum
  cover can't be fitted from this data**; only the rise to 80% and the decline after it can.
- After screening (no default emergence, copies removed, at least 3 readings below 80%):
  potato 9, soybean 11 (about 3 independent), field corn 7 (about 4), snap bean 5, shell peas 3,
  sweet corn 2.

## Days from emergence to 50% / 80% cover (linear between readings)

| Crop | Series | To 50% | To 80% | Notes |
|---|---|---|---|---|
| Potato | 9 | 14–26 | 18–35 | Emerged May 27–28: 80% by day 18–24. Emerged May 13–19: day 32–35. |
| Field corn | 7 | 22–36 | 32–43 | |
| Soybean | 11 | 37–40 | 44–52 | Very consistent, but probably 2–3 growers |
| Snap bean | 5 | 25–33 | 40–46 | May and July plantings |
| Shell peas | 3 | 27–29 | 38–42 | |
| Sweet corn | 2 | 31–37 | 40–52 | |

## Decline (senescence and vine kill)

Only potato shows it: two plantings fall from 80% at day 55 to 50% by day 69, and one to 5% by
day 76. Others drop to 70–75% around days 60–77. Corn and soybean readings stop or stay at 100%
before any decline, so their decline must come from the literature.

## Alfalfa

The one alfalfa series is a sawtooth: about 100% before each cutting, then 10–25% after, regrowing
to 100% in about 2–3 weeks (cuttings around days 25, 56, 77 and 109). A single seasonal curve
can't represent it. It needs a regrowth curve that restarts at each cutting, or readings only.

## What it means for the plan

1. **The data can check timing, not fit curves.** A few independent series per crop from one
   season are enough to test whether a published curve reaches 50% and 80% at plausible times
   in Wisconsin. They aren't enough to fit curve parameters. The published parameters (AquaCrop,
   FAO-56) stay the primary source, and this data validates them.
2. **There's a sign of a degree-day effect.** Potatoes that emerged in late May, in warmer
   weather, reached 80% cover 10–15 days sooner than those emerged in mid-May. The next step
   attaches GDD to each series to see whether thermal time removes that difference.
3. **The backtest (A.4) has little to work with:** potato 9, soybean 11 (about 3 independent),
   field corn 7 (about 4), snap bean 5, shell peas 3 and sweet corn 2 screened series. Its
   results will steer the choice but can't decide it alone.
4. **Other crops, such as onion, carrot, cabbage and the cucurbits, have no Wisconsin readings**
   and will rely on literature only (confidence "published, unvalidated here").

## Days or degree-days? (step A.3, first look)

Daily max/min temperatures for 2026 from the Open-Meteo historical API at each series' rounded
location. GDD are summed from emergence by the modified method (max and min capped at 86 °F and
floored at the base). The table compares the spread (coefficient of variation, CV) of the time
to 50% and 80% cover, measured in days and in GDD. If thermal time drove the differences, the
GDD spread would be clearly smaller.

| Crop | Series | To 50%: CV days → GDD | To 80%: CV days → GDD |
|---|---|---|---|
| Potato | 9 | 0.19 → 0.17 (base 40, 45 or 50 °F alike) | 0.17 → 0.13–0.14 |
| Field corn | 8 | 0.17 → 0.16 (base 50) | 0.08 → 0.08 |
| Soybean | 10 | 0.03 → 0.03 | 0.06 → 0.11 |
| Snap bean | 4 | 0.11 → 0.11–0.12 | 0.06 → 0.08–0.10 |
| Shell peas | 3 | 0.02 → 0.14 (base 40) | 0.04 → 0.01 |
| Sweet corn | 2 | 0.09 → 0.19 | 0.13 → 0.23 |

**GDD doesn't explain the spread in this data.** Potato improves slightly; the other crops are
about the same or worse. Snap beans emerged in May and in July took about the same number of
days to cover, though July gave them far more GDD. The fast late-May potatoes are only partly
explained by warmth, so the rest is probably variety, grower or a late-entered emergence date.
One season, a few growers and readings taken by eye can't detect an effect of the size GDD
usually has, so this neither supports nor rules GDD out.

**Consequence:** the driver for each crop is chosen from the literature (step A.1). Days since
emergence remains acceptable where the literature calibrates in calendar days, because it's
simpler to explain and the 2026 data fits it about as well. Any GDD curve still has to reproduce
the 2026 timings above.
