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

## What could change in WISP 3 (as proposed; 1 and 2 were made as C22, below)

Each would be a deliberate change to the balance: a fix ID in PLAN.md §9, a `LegacyEngine` switch, and the About page's wording.

1. **Count soil evaporation at low cover and after vine kill.** The simplest option is a floor on the crop coefficient near FAO-56's Kc ini for potato. A floor of 0.4 alone brings vine kill to harvest from −49% to −7% (curve), but leaves development with measured cover at −15%, because the table is also low at 10–30% cover. The fuller option is FAO-56's dual coefficient (Kcb plus an evaporation term Ke that rises after rain or irrigation and decays as the surface dries), which matches the wet/dry pattern above. It's also more machinery, and its inputs (wetted fraction, readily evaporable water for each soil) are more for growers to get wrong.
2. **Reduce ET in early August**, either by letting the decline count below full Kc (the 80% saturation in `CropEt` hides the rule's first weeks) or by a gentler Kc mid to Kc end slope as in FAO-56 (potato Kc end 0.75). One season of observed decline is thin evidence, so this needs care.
3. **Canopy in thermal time, or a later default for April emergence.** Readings already fix it for growers who enter them; the default curve (`docs/canopy/`) could grow by growing degree days, which the four seasons here are consistent with but can't fit on their own.
   *(Built 2026-11-20 on branch `gdd-canopy`: C23, `docs/canopy/07-thermal-time.md`.)*

Until one of these is decided, WISP 3's season total is right and its timing is not: wetter than the field in development and after vine kill, drier in early August.

## After the change: FAO-56's dual crop coefficient (C22)

2026-11-19. Ben chose the fuller option for points 1 and 2: crop ET is now FAO-56's dual crop coefficient (chapter 7), (Kcb + Ke) × ET0, for every planting with a crop (PLAN.md §9 C22, `CropEt`, `SoilEvaporation`, `WaterBalance`):

- **Kcb** (transpiration, with the surface dry) comes from the canopy by FAO-56 eq. 98: Kc min 0.15 plus the share of full cover's Kcb that the canopy's effective shade gives, Kd = min(1, 2·fc, fc^(1/(1+h))). Bare ground is 0. Potato's full-cover Kcb is Table 17's 1.10, adjusted for wind and minimum RH (eq. 70) like Kc mid before it. From the curve's decline start (potato: July 25, or full cover if later) it falls in a straight line to Table 17's Kcb end, 0.65, at harvest.
- **Ke** (soil evaporation) runs day by day: a 0.10 m surface layer holds TEW = (θFC − 0.5 θWP) × Ze (eq. 73, from the planting's own soil), evaporating at Kc max − Kcb while it has lost less than REW (Table 19's middle: sand 4.5 mm, loamy sand 6 mm), then in proportion to what's left. Rain and irrigation refill it. Its share of the surface is what the canopy leaves exposed (1 − fc) and the water wetted (all of it for rain and sprinklers, 35% for drip).

`season.rb` now runs both methods. The dual coefficient's layer is carried from emergence through every day, kept or not, wetted by the tower's own rain gauge (which catches the pivot's water), with sand's soil values (TEW 8 mm, REW 4.5 mm) and loamy sand's (TEW 12 mm, REW 6 mm), the Central Sands' two textures. Nothing was fitted to the towers: every value is FAO-56's or the soil file's.

### By phase, all four seasons

ET / ET0, and the bias against closure-corrected ET. "Old" is C21's percent cover table, as in the tables above.

| Phase | Days | Corrected | Old, measured cover | Old, curve | Old, readings | C22 sand, measured cover | C22 sand, curve | C22 sand, readings | C22 loamy sand, curve |
|---|---|---|---|---|---|---|---|---|---|
| Development | 115 | 0.88 | 0.69 (−21%) | 0.86 (−1%) | 0.71 (−19%) | 0.96 (+10%) | 1.01 (+16%) | 0.97 (+10%) | 1.05 (+20%) |
| Full cover | 159 | 1.05 | 1.12 (+7%) | 1.11 (+6%) | 1.11 (+6%) | 1.04 (−1%) | 1.03 (−1%) | 1.04 (0%) | 1.04 (0%) |
| Decline | 30 | 0.86 | 0.98 (+14%) | 1.07 (+25%) | 1.09 (+27%) | 0.82 (−5%) | 0.88 (+2%) | 0.88 (+2%) | 0.88 (+2%) |
| Vine kill to harvest | 96 | 0.54 | 0.54 (−1%) | 0.27 (−49%) | 0.29 (−46%) | 0.69 (+27%) | 0.60 (+11%) | 0.60 (+12%) | 0.66 (+22%) |
| **Season** | 400 | 0.88 | 0.87 (−2%) | 0.87 (−1%) | 0.83 (−6%) | 0.93 (+5%) | 0.93 (+6%) | 0.92 (+4%) | 0.96 (+9%) |

The Python prototype checked before building it (TEW 8 mm, REW 4 mm) gave the same within a point or two: development +9% / +15% (measured cover / curve), full cover −1%, decline −5% / +2%, vine kill to harvest +26% / +10%, season +5%.

### By cover (US-CS4 and CS5, measured cover, emergence to vine kill)

| Cover % | Days | Corrected | Corrected, wet days | Corrected, dry days | Old | C22 sand | C22 sand, wet days | C22 sand, dry days | C22 loamy sand |
|---|---|---|---|---|---|---|---|---|---|
| 0–10 | 7 | 0.47 | 0.73 | 0.40 | 0.17 | 0.76 | 0.98 | 0.70 | 0.92 |
| 10–30 | 21 | 0.55 | 0.62 | 0.40 | 0.33 | 0.68 | 0.74 | 0.55 | 0.75 |
| 30–50 | 18 | 0.91 | 0.97 | 0.78 | 0.72 | 0.85 | 1.04 | 0.49 | 0.87 |
| 50–80 | 14 | 1.08 | 1.17 | 0.91 | 1.00 | 0.94 | 1.05 | 0.74 | 0.99 |
| 80–99 | 34 | 0.99 | 0.99 | 0.97 | 1.13 | 1.05 | 1.05 | 1.01 | 1.05 |
| 100 | 64 | 1.02 | 1.02 | 0.97 | 1.12 | 1.06 | 1.06 | 1.01 | 1.06 |

### Through the summer (the curve)

| | Days | Corrected | Old | C22 sand | C22 loamy sand |
|---|---|---|---|---|---|
| July 1–15 | 52 | 1.09 | 1.12 | 1.06 | 1.07 |
| July 16–31 | 60 | 1.05 | 1.12 | 1.06 | 1.06 |
| August 1–15 | 54 | 0.97 | 1.10 | 0.97 | 0.99 |
| August 16–31 | 23 | 0.86 | 1.01 | 0.79 | 0.80 |

(Days before vine kill only.)

### After vine kill, wet and dry days (the curve)

| Site | Wet days | Corrected | C22 sand | C22 loamy sand | Dry days | Corrected | C22 sand | C22 loamy sand |
|---|---|---|---|---|---|---|---|---|
| US-CS1 | 8 | 0.82 | 0.74 | 0.73 | 11 | 0.40 | 0.30 | 0.47 |
| US-CS3 | 13 | 0.70 | 0.83 | 0.82 | 5 | 0.39 | 0.56 | 0.79 |
| US-CS4 | 15 | 0.57 | 0.81 | 0.78 | 9 | 0.27 | 0.31 | 0.53 |
| US-CS5 | 20 | 0.69 | 0.88 | 0.86 | 15 | 0.38 | 0.23 | 0.30 |

### What it shows

1. **The phases now agree with the towers to within the season total's margin, except development and the days after vine kill, which run high instead of low.** Full cover went from +6–7% to −1%, the decline from +14–27% to −5% to +2%, and early August from 1.10 to the towers' 0.97. Development went from −21% to +10% with the measured canopy, vine kill to harvest from −49% to +11% with the curve. The season total is +4–6% on sand (it was −1% to −6%, by cancelling errors).
2. **Bare and nearly bare ground runs high.** Below 10% cover the dual coefficient gives 0.76 against the towers' 0.47 (7 days, two of them wet), and 10–30% gives 0.68 against 0.55. Its wet days are close to the towers' (0.98 against 0.73 below 10% and 0.74 against 0.62 at 10–30%, but on 2 and 14 days); its dry days are high (0.70 against 0.40 below 10%), as if the sand's surface dries faster than TEW 8 mm allows, or the towers' footprint at low cover includes drier ground than the planted rows. These are few days, and the share of the season they carry is small, so the development phase is +10%.
3. **After vine kill the wet/dry pattern is right in kind,** wet days 0.74–0.88 against the towers' 0.57–0.82, and dry days lower. It's high on wet days at US-CS3 and CS4 (0.83 and 0.81 against 0.70 and 0.57) and low on dry days at CS1 and CS5 (0.30 and 0.23 against 0.40 and 0.38), so the layer's drying isn't off the same way at every site; the gauge's rain and irrigation (02) are its only wetting, and a pass it under-catches leaves the layer drier than the field. With the measured cover it's +27%, but 2019's cover after vine kill is a template (02).
4. **The late season's straight line to Kcb end at harvest is close through mid-August** (0.97 against 0.97) and a little low in late August (0.79 against 0.86, before vine kill), which Table 17's potato note (Kcb end about 0.35 with vine kill) wouldn't help; 0.65 at harvest is kept.
5. **Loamy sand's larger TEW (12 mm) adds 3–4 points** in development and 10 after vine kill (+20% and +22% with the curve). Sand's values fit these fields better; a grower's soil type sets which a field gets.
6. **Weekly readings no longer hurt.** With the canopy right, development is +10% (it was −19%), the same as with the measured cover: the error that readings exposed (point 3 above) is what C22 fixes.

Still open: point 3 of the proposals (canopy in thermal time) is separate work; the curve's early canopy for April emergence is why development with the curve (+16%) runs higher than with readings (+10%).

## With the canopy in degree days too (C22 and C23)

The canopy curve now runs in growing degree days (C23, `docs/canopy/07-thermal-time.md`), which puts potato's development closer to these four seasons' timing (days to 50% and 80% cover off by 7 days on average, against 14 by the calendar). `season.rb` runs it as a fourth canopy, "curve, degree days": the season's temperatures at each tower and normals from the 20 years before, from Open-Meteo's archive, with the late stage starting where that curve declines.

| Phase | Days | Corrected | Old, curve | Old, curve in degree days | C22 sand, curve | C22 sand, curve in degree days | C22 loamy sand, curve in degree days |
|---|---|---|---|---|---|---|---|
| Development | 115 | 0.88 | 0.86 (−1%) | 0.73 (−17%) | 1.01 (+16%) | 0.96 (+10%) | 1.01 (+16%) |
| Full cover | 159 | 1.05 | 1.11 (+6%) | 1.11 (+6%) | 1.03 (−1%) | 1.03 (−1%) | 1.05 (0%) |
| Decline | 30 | 0.86 | 1.07 (+25%) | 1.07 (+25%) | 0.88 (+2%) | 0.88 (+2%) | 0.88 (+2%) |
| Vine kill to harvest | 96 | 0.54 | 0.27 (−49%) | 0.27 (−49%) | 0.60 (+11%) | 0.60 (+11%) | 0.66 (+22%) |
| **Season** | 400 | 0.88 | 0.87 (−1%) | 0.83 (−6%) | 0.93 (+6%) | 0.92 (+4%) | 0.95 (+7%) |

The two changes needed each other. With the old table, timing the canopy right made development worse (−1% to −17%): the calendar curve had been hiding the missing soil evaporation by running ahead. With the dual coefficient, the degree-day curve brings development from +16% to +10%, the same as the measured canopy gives (+10%), so what's left in development is the dual coefficient's own excess on nearly bare ground (point 2 above), not the canopy's timing. On sand, every phase is now within −1% to +11% of the corrected towers, and the season +4%.

**2026-11-19: FAO-56 Rev.1's hourly ET0 (PLAN.md §9 C24).** With the towers' ET0 in the second edition's form (about 5% higher), `season.rb` on the same coefficients gives, for C22 on sand with the calendar curve: development +21%, full cover +3%, decline +6%, vine kill to harvest +14%, season +10% (402 days; closure-corrected ET / ET0 0.84 for the season, 1.00 at full cover). Potato's coefficients are being moved to Rev.1's at the same time, and the tables in this note will be redone on both.


**2026-11-19, FAO-56 Rev.1's crop coefficients (C25).** Potato now takes Rev.1's long-season row (Kcb 1.05 mid, 0.30 at harvest, in place of Table 17's 1.10 and 0.65; Kc mid 1.10 for the old method) and its canopy Table 6.10's 30 °C upper temperature (was AquaCrop's 26 °C; days to 10, 50 and 80% cover change by a day at most). On this note's tower ET0, C22 on sand with the curve goes from +16% to +12% in development, −1% to −7% at full cover, +2% to −10% in the decline, +11% to +5% from vine kill to harvest, and +6% to 0% over the season (in degree days: +10%, −7%, −10%, +5%, −2%). So the lower Kcb end undoes point 4's fit in the decline (0.78 against the towers' 0.86) and full cover drops below the towers. On the towers' ET0 recomputed with Rev.1's hourly method (C24, run before merging, with different kept days), the same change goes +21% → +17%, +3% → −3%, +6% → −6%, +14% → +7% and +10% → +4%. The tables above are from before both; they're to be redone once C24 and C25 are merged.
