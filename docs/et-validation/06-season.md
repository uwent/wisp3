# 06. Results: the whole potato season

2026-11-19. Potato from emergence to harvest at the four seasons with crop dates and canopy cover from Desai's group (US-CS1 2018, CS3 2019, CS4 2020, CS5 2021; what was kept from their records, and why, is in 02). Note 03 covered full cover alone; this note covers canopy development, the late-season decline, and vine kill to harvest.

Reproduce:

```bash
python3 -I docs/et-validation/scripts/et0.py            # tmp/ameriflux/daily.csv
python3 -I docs/et-validation/scripts/season_data.py    # tmp/ameriflux/desai/*.csv
bin/rails runner docs/et-validation/scripts/season.rb   # the tables below; tmp/ameriflux/season_daily.csv
```

## Method

- **ET0 is each tower's own** (`et0.py`, as in 03), so this tests the crop side of WISP 3 (its canopy and `CropEt`), not its weather. Days are kept on the same terms as in 03.
- **WISP 3's crop ET is WISP's own code**: `CropEt.from_pct_cover` with potato's Kc mid adjusted each day for wind and minimum RH (C21), run through `bin/rails runner`. It's run on three canopies:
  - **measured cover**: Desai's group's cover, linear between their values. This tests how `CropEt` turns cover into a crop coefficient, separately from the canopy's timing.
  - **curve**: what a grower gets by entering emergence, vine kill and harvest and no readings (`Canopy` with potato's curve, its July 25 decline rule and the 14-day vine kill ramp).
  - **readings**: the same with a cover reading each week until vine kill, taken from the measured cover (the curve fitted to them, as `Canopy` does).
- **Phases** come from `seasons.csv`: development (emergence to the first day at 100% cover), full cover, decline (from the end of full cover to vine kill; only US-CS4 has much), and vine kill to harvest.
- **Closure** is corrected per site and phase, as in 03 (Bowen ratio kept, and G taken as 0 where it isn't measured). It runs 0.73–0.88 with a canopy and 0.81–1.07 after vine kill.
- **Coverage:** 400 days. US-CS1's tower starts June 29, so it has no development days. US-CS5 has only 11 kept development days: its shortwave sensor was out for most of May and June 2021 (02).

## Results

### By phase, all four seasons

ET / ET0 (the crop coefficient), and WISP 3's bias against closure-corrected ET:

| Phase | Days | Measured | Corrected | WISP 3, measured cover | WISP 3, curve | WISP 3, readings |
|---|---|---|---|---|---|---|
| Development | 115 | 0.67 | 0.88 | 0.69 (−21%) | 0.86 (−1%) | 0.71 (−19%) |
| Full cover | 159 | 0.86 | 1.05 | 1.12 (+7%) | 1.11 (+6%) | 1.11 (+6%) |
| Decline (US-CS4, and 2 days at CS5) | 30 | 0.73 | 0.86 | 0.98 (+14%) | 1.07 (+25%) | 1.09 (+27%) |
| Vine kill to harvest | 96 | 0.53 | 0.54 | 0.54 (−1%) | 0.27 (−49%) | 0.29 (−46%) |
| **Season total** (mm, kept days) | 400 | 1127 | 1371 | 1347 (−2%) | 1353 (−1%) | 1290 (−6%) |

By site:

| Site | Phase | Days | Closure | Corrected | Measured cover | Curve | Readings |
|---|---|---|---|---|---|---|---|
| US-CS1 | full cover | 52 | 0.78 | 1.07 | 1.13 | 1.11 | 1.13 |
| | vine kill to harvest | 19 | 0.81 | 0.56 | 0.45 | 0.17 | 0.22 |
| US-CS3 | development | 50 | 0.75 | 0.88 | 0.64 | 0.84 | 0.64 |
| | full cover | 43 | 0.83 | 1.07 | 1.12 | 1.10 | 1.10 |
| | vine kill to harvest | 18 | 0.97 | 0.60 | 0.78 | 0.36 | 0.34 |
| US-CS4 | development | 53 | 0.76 | 0.81 | 0.64 | 0.83 | 0.68 |
| | full cover | 29 | 0.79 | 1.07 | 1.12 | 1.12 | 1.12 |
| | decline | 28 | 0.84 | 0.86 | 0.97 | 1.07 | 1.09 |
| | vine kill to harvest | 24 | 1.00 | 0.45 | 0.17 | 0.31 | 0.31 |
| US-CS5 | development | 11 | 0.79 | 1.12 | 1.13 | 1.13 | 1.13 |
| | full cover | 35 | 0.88 | 0.97 | 1.11 | 1.11 | 1.11 |
| | vine kill to harvest | 35 | 1.07 | 0.55 | 0.69 | 0.27 | 0.29 |

(The "measured cover" model after vine kill uses the group's cover as given. Its 2019 values are a template (02), so that row says little.)

### The crop coefficient by cover

US-CS4 and CS5, whose cover was observed, from emergence to vine kill. "Wet" means rain or irrigation over 0.5 mm that day or the day before.

| Cover % | Days | Wet days | Measured | Corrected | Corrected, wet days | Corrected, dry days | WISP 3 (`CropEt`) |
|---|---|---|---|---|---|---|---|
| 0–10 | 7 | 2 | 0.36 | 0.47 | 0.73 | 0.40 | 0.17 |
| 10–30 | 21 | 14 | 0.42 | 0.55 | 0.62 | 0.40 | 0.33 |
| 30–50 | 18 | 11 | 0.71 | 0.91 | 0.97 | 0.78 | 0.72 |
| 50–80 | 14 | 9 | 0.84 | 1.08 | 1.17 | 0.91 | 1.00 |
| 80–99 | 34 | 28 | 0.80 | 0.99 | 0.99 | 0.97 | 1.13 |
| 100 | 64 | 56 | 0.85 | 1.02 | 1.02 | 0.97 | 1.12 |

### Through the summer at full cover

All four seasons (corrected ET / ET0), while the recorded cover stays at or near 100%:

| | Days | US-CS1 | CS3 | CS4 | CS5 | All | WISP 3, curve |
|---|---|---|---|---|---|---|---|
| July 1–15 | 52 | 1.16 | 1.13 | 1.06 | 0.96 | 1.09 | 1.12 |
| July 16–31 | 60 | 1.12 | 1.06 | 1.04 | 0.96 | 1.05 | 1.12 |
| August 1–15 | 54 | 0.96 | 1.05 | 0.88 | 1.00 | 0.97 | 1.10 |

### After vine kill

Corrected ET / ET0 from vine kill to harvest, split into wet days (rain or irrigation that day or the day before) and dry days:

| Site | Wet days | ET/ET0 | Dry days | ET/ET0 | H/LE, dry |
|---|---|---|---|---|---|
| US-CS1 | 8 | 0.82 | 11 | 0.40 | 1.35 |
| US-CS3 | 13 | 0.70 | 5 | 0.39 | 1.33 |
| US-CS4 | 15 | 0.57 | 9 | 0.27 | 2.11 |
| US-CS5 | 20 | 0.69 | 15 | 0.38 | 1.26 |

### Canopy timing

| Site | Emergence | 10% | 50% | 80% | Emergence to 50%, days | 10% to 80%, days |
|---|---|---|---|---|---|---|
| US-CS1 | May 23 | May 29 | Jun 13 | Jun 20 | 21 | 22 |
| US-CS3 | May 8 | May 18 | Jun 12 | Jun 20 | 35 | 33 |
| US-CS4 | Apr 25 | May 4 | Jun 7 | Jun 16 | 43 | 43 |
| US-CS5 | Apr 21 | May 2 | Jun 5 | Jun 11 | 45 | 40 |
| WISP's potato curve | | | | | 23 | 15 |

## What it shows

1. **Over the whole season WISP 3 is close: −1% with the default curve and −6% with weekly readings, against the closure-corrected towers.** But that total comes from errors that cancel by phase, and the timing matters for scheduling: when WISP 3 underestimates ET, its balance runs wetter than the field, and when it overestimates, drier.
2. **Full cover holds up (+6%),** as in 03.
3. **At low cover WISP 3 is too low.** Below 30% cover the towers measure about 0.5 × ET0 (0.40 on dry days, 0.6–0.7 on wet ones), where `CropEt`'s table gives 0.17–0.33. This is evaporation from the soil surface, which sprinklers and rain keep wet on these sands. The A3600 table's bare-soil end (0–0.02 in a day) leaves it out, and C21 scales the table only toward full cover. FAO-56 puts potato's Kc ini at 0.5 (Table 12), close to what the towers show. With the measured cover, development runs 21% low. The default curve hides this (−1%) only because it runs ahead of these canopies.
4. **After vine kill WISP 3 is about half the towers (−49%).** WISP ramps the canopy to zero over 14 days and then counts bare-soil ET as almost nothing. The towers keep measuring 0.54 × ET0 to harvest: about 0.7 on days after rain or irrigation, and 0.3–0.4 on dry days, when the sensible heat flux shows the surface drying. That's about 0.9 mm a day WISP 3 doesn't count (0.27 × ET0 of 3.2 mm), roughly an inch over the three to five weeks of skin set, the period WISP keeps the balance running for.
5. **The towers' coefficient eases off from mid-July, before the cover does.** It goes from 1.09 in early July to 0.97 in early August (1.05 at CS3 to 0.88 at CS4), with cover still recorded near 100%. WISP's July 25 decline rule points the right way, but `CropEt` counts everything at or above 80% cover as full. The curve's decline only reaches 81% on August 8, so WISP 3 stays at 1.10 through early August (+13%). At US-CS4, the one season whose canopy declined well before vine kill, WISP 3 is +12% with the measured cover and +24% with the curve.
6. **Canopy development is slower than potato's curve in calendar days,** most of all for April emergence. Across the four seasons, 10% to 80% cover took 22 to 43 days against the curve's 15. Every season reached 80% between June 11 and 20, whatever its emergence (April 21 to May 23), as growth in thermal time would. The curve comes closest for the May 23 emergence (2018: 21 days to 50%, against 23) and runs two to three weeks early for April emergence. Weekly readings correct the canopy (`Canopy` fits the curve to them), but that exposes point 3: with the canopy right, development is 19% low.

## How sure

- **Canopy cover is the group's, and how it was measured isn't recorded.** 2018 and 2019 are a template between the phases (02), so only US-CS4 and CS5 test the cover-to-coefficient relation, on 158 days. The timing in point 6 rests on all four seasons, and nothing independent confirms how fast cover grew: over this sand the towers' midday albedo hardly changes as the canopy closes.
- **Closure at low cover and after vine kill.** With a sparse canopy or none, more of the energy goes to sensible heat, so how the missing energy is shared out matters more than at full cover (03, point 2). The uncorrected towers already exceed WISP 3 at low cover (0.36–0.42 against 0.17–0.33) and after vine kill (0.53 against 0.27), so points 3 and 4 hold without any correction. After vine kill closure is 0.81–1.07, close to complete.
- **Small samples, one field per year.** The low-cover rows rest on 28 days at two seasons, and the decline on one season.
- **Weeds and residue after vine kill** may add some of the late ET. The wet/dry split (point 4) says most of it is soil evaporation.
- **The towers' footprint after harvest** includes the dug field; harvest is the end of every phase here, so no post-harvest days are counted.

## What could change in WISP 3 (for Ben to decide)

Each would be a deliberate change to the balance: a fix ID in PLAN.md §9, a `LegacyEngine` switch, and the About page's wording.

1. **Count soil evaporation at low cover and after vine kill.** The simplest option is a floor on the crop coefficient near FAO-56's Kc ini for potato. A floor of 0.4 alone brings vine kill to harvest from −49% to −7% (curve), but leaves development with measured cover at −15%, because the table is also low at 10–30% cover. The fuller option is FAO-56's dual coefficient (Kcb plus an evaporation term Ke that rises after rain or irrigation and decays as the surface dries), which matches the wet/dry pattern above. It's also more machinery, and its inputs (wetted fraction, readily evaporable water for each soil) are more for growers to get wrong.
2. **Reduce ET in early August**, either by letting the decline count below full Kc (the 80% saturation in `CropEt` hides the rule's first weeks) or by a gentler Kc mid to Kc end slope as in FAO-56 (potato Kc end 0.75). One season of observed decline is thin evidence, so this needs care.
3. **Canopy in thermal time, or a later default for April emergence.** Readings already fix it for growers who enter them; the default curve (`docs/canopy/`) could grow by growing degree days, which the four seasons here are consistent with but can't fit on their own.
   *(Built 2026-11-20 on branch `gdd-canopy`: C23, `docs/canopy/07-thermal-time.md`.)*

Until one of these is decided, WISP 3's season total is right and its timing is not: wetter than the field in development and after vine kill, drier in early August.
