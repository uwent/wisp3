# 05. Corn

US-CC1 and US-CC2 (Coloma, 2021; Stoy, Brevert and Khan) are AmeriFlux BASE files: not gap-filled, with no air temperature (derived from RH and VPD) and no pressure (from elevation). Whole days of measured ET are rare, so `scripts/corn.py` uses daytime sums: measured ET over FAO-56 ET0 (from the tower's weather, as `et0.py`) for 08–18 local standard time, over hours with LE and every input measured, on days with at least 16 of the 20 half-hours. It runs the potato towers the same way as a check: their daytime ratios (0.80–0.90) match the whole-day ones in 03 (0.82–0.92).

```bash
python3 -I docs/et-validation/scripts/corn.py
```

| Site | Window | Days | Daytime ET / ET0 | Daytime closure | Corrected | Closure, G = 0.1 Rn where unmeasured | Corrected |
|---|---|---|---|---|---|---|---|
| US-CC1 | Jul 10 – Aug 31 | 16 | 0.82 | 0.88 | 0.93 | 0.88 (G measured) | 0.93 |
| US-CC2 | Aug 14 – Aug 31 | 14 | 0.93 | 0.75 | 1.23 | 0.84 | 1.11 |

2026-11-19, with FAO-56 Rev.1's hourly ET0 (PLAN.md §9 C24): the daytime hours keep their sign of Rn, so ET0 changes little here: US-CC1 0.81 / corrected 0.91, US-CC2 0.92 / 1.22 (1.10 with G = 0.1 Rn).

FAO-56's Kc mid is 1.20 for field corn (1.15 for sweet corn), which WISP adjusts to about 1.17 in a humid Central Sands summer.

**Inconclusive.** Thirty days at two fields, one season, with the crop's stage, type (field or sweet corn) and irrigation unknown. US-CC2's corrected 1.11–1.23 brackets FAO-56; US-CC1's 0.93 is well below it. A coefficient of 0.93 at full canopy would be low for well-watered corn, so CC1 may not have been at full canopy or fully watered over these weeks, or (like the corn sites in Talib et al. 2024, whose fit was worst there) its record is too short to say. Worth asking Paul Stoy's group what was grown, when, and whether it was irrigated, before reading anything into it. WISP 3's corn coefficient stays as FAO-56 gives it.
