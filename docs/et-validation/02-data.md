# 02. The data

Downloaded 2026-11-19 from AmeriFlux (CC BY 4.0) into `tmp/ameriflux/` (not committed): one folder per site as unzipped, the original zips in `zips/`, and AmeriFlux's manifest, citations and network-wide site metadata in `meta/`. `scripts/inventory.py` produces the table below.

## Sites

| Site | What | Product | Measured season | Cite |
|---|---|---|---|---|
| US-CS1 | Heartland Farms, irrigated potato | FLUXNET (ONEFlux v1.3) | Jun 29 – Dec 2018 (tower stays to Apr 2019) | doi:10.17190/AMF/1881576 |
| US-CS3 | Heartland Farms, irrigated potato | FLUXNET | Apr 26, 2019 – Apr 2020 | doi:10.17190/AMF/1881578 |
| US-CS4 | Heartland Farms, irrigated potato | FLUXNET | Apr 11, 2020 – Feb 2021 | doi:10.17190/AMF/1881579 |
| US-CS5 | Heartland Farms, irrigated potato | FLUXNET | May 19 – Dec 2021 | doi:10.17190/AMF/2469447 |
| US-CS6 | Worzella Farms, irrigated potato | FLUXNET | Jun 22, 2022 – May 2023 | doi:10.17190/AMF/2469448 |
| US-CS8 | Worzella Farms, irrigated potato | FLUXNET | Jun 19 – Nov 2023 | doi:10.17190/AMF/2469449 |
| US-CC1 | Coloma, corn | BASE (unprocessed) | 51 days, Jun 25 – Sep 16, 2021 | Stoy (2022), doi:10.17190/AMF/1865475 |
| US-CC2 | Coloma, corn | BASE | 57 days, Aug 13 – Oct 10, 2021 | Stoy (2022), doi:10.17190/AMF/1865476 |
| US-DFK | Prairie du Sac, Kernza (rainfed) | FLUXNET | 2019–2020 | doi:10.17190/AMF/2571122 |
| US-DFC | Prairie du Sac, dairy farm (30 m tower) | FLUXNET | 2019–2024 | doi:10.17190/AMF/2006975 |
| US-CS2 | Tri-County school pine forest, Plainfield | FLUXNET | 2019–2022 | doi:10.17190/AMF/1881577 |
| US-Cst | Crossett Experimental Forest, Arkansas | FLUXNET | 2013–2017 | not used |

- **One portable tower, moved to that year's potato field each spring.** Each site is one potato season (the BADM: "20xx is Potatoes, 3-yr rotation"); the years after are the tower standing over the next crop or winter, mostly empty in May–September.
- **Six potato seasons**, one more than the paper: US-CS8 (2023) is new and independent of the correction's fitting. US-CS3, CS4 and CS5 start before emergence and cover canopy development; US-CS1, CS6 and CS8 start in late June, near full cover.
- **US-CC1 and US-CC2 are thin**: about 38 and 18 usable days, as the paper found, in the raw BASE format, with no air temperature (derivable from RH and VPD) or pressure (from elevation, FAO-56 eq. 7), and no soil heat flux at CC2. A sanity check for corn, not a test of its coefficient.
- **US-DFC's tower is 30 m tall** over a mixed farm (alfalfa, corn, soybean, wheat), so its footprint isn't one crop. US-DFK is rainfed Kernza with poor closure (0.52–0.56). Neither tests an irrigated crop; DFK can check the reference ET's grass end loosely.
- **US-CS2 (pine)** isn't a crop, but it stands among the potato fields 2019–2022 with its own weather instruments: a second record of the same weather, useful for checking the potato towers' radiation and humidity.
- **US-Cst** is in Arkansas and was picked up by its name; it can be deleted.

## What each season measured

May–September, the share of half-hours each variable was measured (FLUXNET QC 0; BASE present), energy balance closure, and June–August ET:

| Site | Year | TA | VPD | WS | SW_IN | PA | Rn | G | H | LE | Closure (H+LE)/(Rn−G) | ONEFlux LE correction (median) | ET mm/d, gap-filled | ET mm/d, ONEFlux corrected |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| US-CS1 | 2018 | 61 | 61 | 61 | 60 | 61 | 61 | 0 | 53 | 43 | no G | – | 3.79 | – |
| US-CS3 | 2019 | 100 | 100 | 100 | 97 | 100 | 100 | 0 | 89 | 82 | no G | – | 3.14 | – |
| US-CS4 | 2020 | 98 | 98 | 98 | 97 | 98 | 98 | 0 | 80 | 77 | no G | – | 3.35 | – |
| US-CS5 | 2021 | 100 | 100 | 87 | 67 | 88 | 69 | 61 | 70 | 68 | 0.87 | 1.36 | 3.55 | 4.92 |
| US-CS6 | 2022 | 79 | 79 | 48 | 84 | 48 | 79 | 52 | 41 | 40 | 0.73 | 1.69 | 3.17 | 6.02 |
| US-CS8 | 2023 | 66 | 66 | 66 | 65 | 66 | 66 | 37 | 57 | 55 | 0.82 | 1.57 | 3.32 | 5.12 |
| US-CC1 | 2021 | 20 | 20 | 20 | 51 | 0 | 51 | 51 | 20 | 20 | 0.80 | – | – | – |
| US-CC2 | 2021 | 9 | 9 | 9 | 48 | 0 | 48 | 0 | 9 | 9 | no G | – | – | – |
| US-DFK | 2020 | 97 | 97 | 96 | 98 | 96 | 97 | 93 | 91 | 83 | 0.54 | 1.91 | 2.57 | 5.03 |

(June–August of a season that starts in late June covers July and August only.)

## Does it have what we need?

**Yes, for the main question** (FAO-56 ET0 from the towers' own weather against measured ET at full potato cover):

- Every input to hourly FAO-56 ET0 is measured at each potato site: air temperature and VPD (2.5–3 m; 1.5 m at CS6), wind (2.5–3 m, adjusted to 2 m by FAO-56 eq. 47), incoming shortwave, pressure. ONEFlux fills short gaps (MDS) and flags them, so measured hours can be kept apart.
- The four radiation components (SW_IN, SW_OUT, LW_IN, LW_OUT) and NETRAD are there, so step 5 (FAO-56's net longwave against the radiometers) can be done as the paper did for Idso's.
- Wind height and the other instrument heights are in each site's `BIFVARINFO` file.

**Gaps:**

1. **Crop dates and canopy cover: not in AmeriFlux.** The BADM gives only the crop and year. Desai's group has since sent vine kill and harvest dates and canopy cover for 2018–2021 (below; their planting dates turned out to be the towers' installation). For US-CS6 and CS8 the full-cover period still has to be estimated from the towers themselves (ET/ET0 rising to a plateau, the albedo from SW_OUT/SW_IN as the canopy closes).
2. **No soil heat flux at US-CS1, CS3 and CS4** (the paper's three training sites), so ONEFlux couldn't correct their ET for closure (no `LE_CORR`). Closure there has to be estimated: from daytime sums with G modeled (FAO-56's hourly 0.1 Rn by day, 0.5 Rn at night), or from the closure measured at CS5, CS6 and CS8, the same instruments and crop in later years.
3. **Closure is low and the correction is uncertain.** Measured closure at the potato sites is 0.73–0.87 over May–September (CS6's 0.73 has only half the season). ONEFlux's half-hourly correction runs larger (median 1.36–1.69, and corrected June–August ET of 4.9–6.0 mm a day), likely because the correction is largest at low-flux hours and its days aren't the same as the gap-filled ones. Note 03 has to settle which closure to use, with both bounds shown: uncorrected ET is a floor, Bowen-ratio-corrected ET with the measured seasonal closure the likely value.
4. **Irrigation isn't in AmeriFlux.** The towers' rain gauges catch the pivot (June–August totals of 400–700 mm against about 300 mm of normal rain). Desai's group has since sent the pivots' logs for 2018, 2020 and 2021 (below); for the other seasons the gauge marks irrigation days, so wet-canopy days, when ET runs above the crop's transpiration-limited rate, can still be flagged.
5. **Soil moisture only at US-CS5.** The fields were irrigated potato, so water stress should be rare; CS5 can confirm it for one season.
6. **Corn is two short, raw records.** Enough to see whether corn's measured coefficient sits near FAO-56's 1.20, not to fit one.

7. **Instrument doubts at the Worzella sites** (found in 03): midday albedo of 0.07–0.12 at US-CS6 and CS8 (0.21–0.22 at the Heartland sites), and US-CS8's soil heat flux about 10 times CS5's and CS6's. Worth asking Desai's group about.

## Crop dates, irrigation and canopy cover

Received from Desai's group 2026-11-19 as two workbooks, `US_CS_sites_dates_harvest.xlsx` and `US_CS_sites_irrigation_canopy_cover.xlsx`, kept as received in `tmp/ameriflux/desai/` (not committed: the data are the group's and unpublished). We use what holds up against the towers' own records and leave the rest, rather than go back with questions about records several years old. `scripts/season_data.py` writes the CSVs beside the workbooks:

| File | What |
|---|---|
| `seasons.csv` | **What the analysis uses**, per potato season: emergence, full cover, vine kill, harvest, how far to trust the canopy cover, and where irrigation comes from |
| `sites.csv` | Per tower: crop, position and the dates, as given |
| `irrigation.csv` | The pivot logs' entries (2018, 2020, 2021), as given |
| `irrigation_daily.csv` | The same per day, first entry to harvest, 0 on a day with none |
| `canopy_cover.csv` | Canopy cover in percent, April to October, as given |

The irrigation and canopy sheets have no site column; each year is that year's potato tower (2018 US-CS1, 2019 CS3, 2020 CS4, 2021 CS5). The winter rows (canopy 1%, irrigation 0) are filler and left out.

| Site | Emergence | Full cover | Vine kill | Harvest | Canopy cover | Irrigation |
|---|---|---|---|---|---|---|
| US-CS1 2018 | May 23 | Jul 1 – Aug 27 | Aug 29 | Sep 29 | phases only | pivot log, 11.8 in |
| US-CS3 2019 | May 8 | Jul 8 – Aug 19 | Aug 18 | Sep 7 | phases only | tower gauge |
| US-CS4 2020 | Apr 25 | Jun 23 – Jul 27 | Aug 27 | Sep 23 | observed (about every other day) | pivot log, 18.2 in |
| US-CS5 2021 | Apr 21 | Jul 3 – Aug 15 | Aug 18 | Sep 24 | observed (daily) | pivot log, 15.3 in |
| US-CS6 2022 | – | from the tower | – | Sep 30 | none | tower gauge |
| US-CS8 2023 | – | from the tower | – | – | none | tower gauge |

What's kept, what isn't, and why:

- **Emergence comes from canopy cover** (the first day above the 1% the sheet holds for bare ground), not from the "plantation date". That column is each tower's installation date (it matches the group's record start at every site, to the day), and it can't be planting: 2021's canopy and irrigation start two weeks before it, and 2018's canopy rises five days after it.
- **Full cover, vine kill and harvest are kept.** The towers' midday albedo, though a weak sign of canopy over this sand, peaks within the 100% windows and falls with each decline in all four years, and canopy begins to drop within days of the first vine kill date (2020 excepted: its canopy falls from late July and mostly by mid-August, before the Aug 27 vine kill). Where vine kill has several dates (successive desiccant passes), the first is used.
- **2018 and 2019's canopy cover is used for its phases only** (emergence, the full-cover window, the decline), not as day-by-day readings: the two years share values day for day in mid-June though planted weeks apart, and step down through the same sequence, so the values between are a template, not observations. 2020 and 2021 are observed and can test `Canopy` through development: 2020 against the tower from emergence, 2021 from May 19, when its tower starts (22% cover).
- **2019's "irrigation" sheet isn't used.** It's hourly, in 0.01 in steps, and follows the storms, not the pivot: a rain record. 2019's irrigation days come from the tower's gauge, as CS6's and CS8's do.
- **The pivot logs are kept.** The tower's gauge catches at least half the logged amount on 35 of 37 logged days in 2021 and 33 of 44 in 2020. 2020's eleven 0.09 in passes are likely chemigation. 2018's log matters only from June 29, when its tower starts.
- **US-CS6 and CS8 have no canopy record**, and CS8's "planting" (June 19, 2023) is its tower's installation; their full-cover periods stay estimated from the towers, as in 03. US_CS7's longitude is given as east; `sites.csv` corrects the sign.

## Daily file

`scripts/et0.py` writes `tmp/ameriflux/daily.csv`: per site and day, FAO-56 ET0 from the tower's weather (WISP's hourly chain, `Weather::Fao56`, ported and checked against FAO-56 Example 19), the share of half-hours with every input measured, the tower's ET (gap-filled, measured share, ONEFlux-corrected), the energy balance terms and closure, midday albedo, measured and FAO-56 net longwave, rain, and the day's mean temperature, vapor pressure, wind at 2 m, minimum RH and shortwave. Results are in 03.
