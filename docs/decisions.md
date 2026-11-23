# Decisions

Why WISP 3 is built the way it is: the recorded decisions (D1–D15) and the questions that were put to Ben and settled (Q1–Q11), formerly `PLAN.md` §2 and §15. Code cites them by ID (`D12`, `Q10`); keep the IDs stable. A decision that's replaced stays in the table, struck through, with what replaced it, and a new one takes the next number with its date and reasons.

The deliberate changes from legacy WISP's behavior (C1–C25) are in [legacy-audit.md](legacy-audit.md); section numbers (§) below refer to the original design ([plans/design.md](plans/design.md)). For how the app works now, see [architecture.md](architecture.md) and [engine.md](engine.md). Phase numbers in it are the ones the work was planned under; [plans/README.md](plans/README.md) maps them to the regrouped record.

## Decisions

| # | Decision | Date |
|---|---|---|
| D1 | **Rails 8 + Inertia.js + Svelte 5 + Tailwind CSS v4**, built with Vite |
| D2 | **Fresh app in this directory (`wisp3`)**; legacy code is ported selectively and every ported method is audited (see §9) |
| D3 | **Keep all seasons**; no yearly wipe. Season setup is copied forward instead |
| D4 | Devise email/password stays; **add one-time login links** |
| D5 | Phased delivery. All phases (including alerts and map) target the 2027 launch, with time left for polish |
| D6 | **Retire AgWeather entirely.** Open-Meteo is the only weather source, behind a provider interface. *(Ben, 2026-11-19: once AgWeather v2 (`../agweather2`) is complete and deployed, consider switching WISP to it as its weather provider: it serves several gridded sources, each chosen for the best match to Wisconsin stations and corrected, and outside them falls back to Open-Meteo with the same corrections WISP applies (D12). The provider interface and the tower validation, D14, are what such a switch would be checked with.)* |
| D7 | Open-Meteo **commercial API key is optional config**; without it, the free endpoints are used |
| D8 | **LAI method is kept**, pending the agronomy review in Q2 |
| D9 | ~~**Pivot-level irrigation entry**: irrigation entered once on a pivot applies to every field under it (or a chosen subset), with per-field overrides (§4)~~ Replaced by D15 (2026-11-22) |
| D10 | **No data migration.** Users register and set up their farms fresh in WISP 3. Legacy data is used only offline, for engine validation (§10) and the weather comparison (§8.4) |
| D11 | **New production server** for the 2027 season. Provisioned by CALS IT in AWS (EC2, RDS; October 2026) and deployed with Docker, images built on the server (Ben, 2026-10-29: ECR, SSM and SES dropped, as they needed AWS permissions IT was slow to grant); staging stays on Capistrano (§12). The old production box is out of scope |
| D12 | **Open-Meteo's shortwave and humidity are corrected against ground stations, and ET0 is computed here from the corrected shortwave** (Ben, 2026-10-31, from AgWeather v2's comparison with 80 Wisconet stations): its shortwave reads 15–20% high, so its ET0 reads 16% high; its RH runs dry. Each correction is a versioned table copied from AgWeather v2, applied as hours are aggregated, with the raw values kept and the corrections applied recorded on each day (§8.5). Since 2026-11-19 ET0 takes FAO-56 Rev.1's hourly form (C24); recomputed on both sides, the corrected ET0 stays 1.03 × the stations' (April–October), as the corrections were fitted to shortwave and humidity, not to ET0 |
| D13 | **AGPL-3.0-or-later** (Ben, 2026-10-31), as AgWeather v2 (its D53): anyone who distributes a modified version, or runs one for others over a network, must offer its source. Copyright the Board of Regents of the University of Wisconsin System (`LICENSE`, README, `package.json`). Open-Meteo's data is CC BY 4.0, so the about page credits it | 2026-10-31 |
| D14 | **Crop ET is FAO-56 Penman-Monteith grass reference ET0 × FAO-56 crop coefficients, not legacy's Priestley-Taylor in either form** (2026-11-19; `docs/et-validation/`). Legacy WISP's ET (AgWeather, Diak et al. 1998; crop coefficient 1 at full cover) and its "adjusted" variant (Talib et al. 2024, WPVGA-funded, emissivity refitted to Central Sands flux towers) were checked with WISP 3's method against six seasons of AmeriFlux eddy-covariance towers over irrigated potato (US-CS1–CS8, 2018–2023). At full cover (July) the towers measure 0.87 × FAO-56 ET0 as recorded and close 80% of the energy balance; with the rest put back, potato's coefficient is 1.09–1.12 at the best-instrumented seasons (up to about 1.2 on more generous readings), against WISP's 1.15 (1.12 adjusted for humidity and wind). WISP 3 against the closure-corrected towers: +3% on the towers' weather, +9% on its own corrected Open-Meteo weather (+3% without the 2023 drought); its reference ET is 1.05 × the towers' (Open-Meteo's own 1.18). AgWeather classic +13%, adjusted −15% (as recorded: +42% and +7%, the paper's finding). Talib et al.'s diagnosis of legacy's net longwave holds against the towers' radiometers; its ET is low because the towers weren't closure-corrected. Keeps C21. Corn (US-CC1, CC2) is too short to test. The whole season (06, 2018–2021): total within 1–6%, but low at low cover and after vine kill (soil evaporation) and high in early August. Fixed by C22 (FAO-56's dual crop coefficient, 2026-11-19): full cover −1%, decline +2%, development +10%, vine kill to harvest +11%, season +5%. C24 (FAO-56 Rev.1's hourly ET0, 2026-11-19) raises the towers' ET0 and WISP's by 4–6% alike, so full cover's measured / ET0 drops from 0.87 to 0.83 (closure-corrected 1.09 to 1.04) and WISP's ratio to the towers' reference ET stays near 1.05; 03–06 have the numbers. The crop coefficients are FAO-56 Rev.1's (2025) since C25, potato's short-season row (Kcb 1.05 / 0.50; Ben, 2026-11-19): with C24's reference ET and the canopy in degree days, on sand: development +12%, full cover −2%, decline −1%, vine kill to harvest +10%, season +4% (06) | 2026-11-19 |
| D15 | **Irrigation is stored per field and per plot, in inches, never inherited** (Ben, 2026-11-22; replaces D9): every planting's irrigation on a day is its own number, the field's entry (`field_entries.irrigation_in`) for the field and its whole-field planting, a plot's own (`planting_entries.irrigation_in`). An irrigation system no longer stores irrigation (`pivot_irrigations` dropped, its rows moved into the entries); its row in daily entry, the week grid and the system page fills its fields' boxes, showing their shared amount or "varies", and a calculator works out inches from run hours (pump capacity over the chosen fields' acres) or the percent timer (depth at 100%), filling all the system's fields or the ones chosen. A field's irrigation saved from anywhere but daily entry's plot rows also sets its plots that had the field's amount. Rain stops at the system on daily entry (a system's fields share a gauge), still stored per field. Why: inheritance (field_ids, a field's season moving systems, conversion when read, three levels of fallback) was most of irrigation's complexity, and growers couldn't see where an amount went. Trade-off: a corrected pump capacity or depth at 100% no longer revises past amounts | 2026-11-22 |

## Questions

| # | Question | Status | Needed by |
|---|---|---|---|
| Q1 | Alert threshold and lead-time defaults | **Resolved**: recommendation adopted | – |
| Q2 | How LAI should work, and for which crops | **A adopted for 2027** (B dropped in Phase 6.7); curves per crop (option C) built in Phase 6.7. No outside review coming (2026-11-10): literature, our own work and 2027 readings instead. Percent cover curves run by growing degree days since 2026-11-20 (C23, `docs/canopy/07-thermal-time.md`; branch `gdd-canopy`): clearly better for potato at the towers, neutral to slightly worse for the other crops on the 2026 readings, so which crops keep it is Ben's call | After launch |
| Q3 | Display units | **Resolved**: inches by default, per-user inch/mm toggle in Settings | – |
| Q4 | Pivot-level irrigation | **Resolved** → D9, §4 `pivot_irrigations` | – |
| Q5 | Can the deploy user run `systemd --user` services? | **Resolved**: yes on staging; new production server provisioned with it (D11, §12) | – |
| Q6 | Alert email sender and DKIM | **Resolved**: Amazon SES over SMTP with DKIM, out of the sandbox (2026-11) | – |
| Q7 | Per-field rainfall correction | **Resolved**: per-day overrides shown next to modeled values; no multiplier; per-field entered-only setting (2026-10-07) | – |
| Q8 | Group member roles | **Resolved** (2026-10-04): owner and member; deleting a planting or irrigation group also open to its creator (G.15) | – |
| Q9 | The percent-cover regressions (§5.4) were fitted to the old API's ET; with Open-Meteo's shortwave corrected (D12), ET0 is about 7% below it (1.032 vs 1.114 against station FAO-56, April–October, Wisconsin). Use corrected ET0 as is, or scale crop ET to the old API's level? | **Resolved** (Ben, 2026-10-31): corrected ET0 as is. The regressions' provenance is unknown and likely over a decade old, so the best available is the most accurate weather; a computational refit is under After launch | – |
| Q10 | The ensemble projection's ET0 (§8.5): compute it per member from corrected shortwave, or scale the members by the deterministic run's correction? | **Resolved** (Ben, 2026-11-10): **scale by ratio**, evaluated after a season. The ensemble API has every input for all 31 members, but each member counts as a variable, so per member takes a cell's ensemble from about 7 calls a refresh to about 21 (each refresh from about 14 to 28). The members are one model's perturbed runs, interchangeable by design, so storing more per member wouldn't show which forecasts are better; the archive's daily ET0 and rain per member serve accuracy tracking either way. `Weather::Ensemble.corrected` scales each member by the deterministic forecast's corrected/raw ratio for the day (the mean ratio where that day's raw ET0 is under 0.01 in), keeps the ratios (`et0_ratio`) and records `et0-ensemble-ratio v1`. Revisit with the evaluation page (After launch): if the band's coverage is poor, compute per member with the ensemble refreshed once a day, which costs about what three ratio refreshes do | – |
| Q11 | With corrected ET0 the standard potato field gets 3.3 fewer irrigations a season than WISP 2026 and 4.5 fewer than AgWeather, mostly at full cover in midsummer, where the percent-cover table's Kc (about 1.0 on corrected ET0) is below FAO-56's 1.15–1.20 (Phase 8 E step 8). Ship as is (Q9) and refit after launch, scale full-cover crop ET up for 2027 as a stopgap, or bring the refit (After launch, Allen and Pereira 2009) forward before the beta? | **Resolved** (Ben, 2026-11-17: under-counting water use is the wrong side to err on): C21, each crop's FAO-56 Kc mid scaled in with cover and adjusted for wind and humidity; the standard potato field is back to 1.3 irrigations a season below AgWeather (WISP 2026: 1.2). Validation against measured ET stays under After launch (the refit) | – |

### Q1. Alert defaults: resolved (recommendation adopted)

*Update 2026-10-04:* Phase 6 is now a daily digest of every included field rather than alerts for crossings, so the probability and dedupe settings below don't apply. The threshold (target, else AD = 0) and the 3-day lead time live on as the projection's "Irrigate by" and caution status (§6 "As built").

**What it decides:** when a user gets an email saying a field is heading for irrigation.

**Recommendation:**
- **Threshold:** the field's target (`target_ad_pct`) if set; otherwise AD = 0, the MAD trigger point, which matches legacy "AD < 0" problem reporting.
- **Lead time:** 3 days.
- **Ensemble probability:** alert when ≥ 50% of members cross the threshold within the lead time.
- **Delivery:** one digest per user per day at 6 am CT, listing every flagged field; nothing is sent if nothing is flagged.
- All of these can be changed per user, and the beta (Phase 8) is the time to tune them.

### Q2. LAI (leaf area index) method: A adopted; curves per crop built (Phase 6.7); no outside review

**Background.** WISP estimates crop water use as reference ET × a crop coefficient (Kc), and Kc grows with the canopy. There are two ways to describe the canopy:
- **Percent cover** (used by almost everyone): the grower enters canopy cover on a few dates, and Kc comes from the A3600 Table C regressions.
- **LAI**: leaf area per unit of ground, turned into Kc with a Beer's-law curve: Kc = 1.1 × (1 − e^(−1.5·LAI)). LAI normally comes from a growth curve, so the grower doesn't have to enter canopy data.

**How much it's used (legacy production, 2025–2026 fields):** 29 of 525 fields (5.5%) use LAI, by crop:

| Crop | LAI fields | What legacy actually computed |
|---|---|---|
| Potato | 14 | Field corn canopy curve |
| Soybean | 8 | Field corn canopy curve |
| Field corn | 6 | Field corn canopy curve (the only correct case) |
| Sweet corn | 1 | Negative ET (C18) |

So 23 of the 29 LAI fields were modeled with a *corn* canopy. Potato is the main case to get right: it is the largest LAI group and a major irrigated crop in the Central Sands.

**What the legacy app actually does:**
- **Field corn and every other crop except sweet corn:** the corn curve from the WIS v6.3.11 spreadsheet, based on calendar days since emergence. It gives LAI ≈ 0.25 at day 30, 1.95 at day 50, 4.07 at day 80 (peak), 3.25 at day 100 and 0.86 at day 140. Kc reaches about 1.0 by day 50. So soybeans, potatoes, onions and the rest under LAI all use a *corn* canopy.
- **Sweet corn:** the placeholder curve, which is broken (C18): negative ET, or none.
- **No way to enter LAI.** There is a column for it, but no screen writes observations to it.

**Questions for an agronomist** (for example the A3600 authors or UW BSE / Soil Science extension):
1. Is the WIS corn curve still a reasonable default for Wisconsin field corn? Should it be driven by **growing degree-days** instead of calendar days, so planting date and a cool or warm year shift the canopy? (WISP 3 can compute GDD from Open-Meteo temperatures; AgWeather isn't needed.)
2. The extinction coefficient of 1.5 and maximum Kc of 1.1: what is their source, and do they suit crops other than corn? Published canopy extinction coefficients are usually lower (about 0.4–0.8), so confirm which formulation the spreadsheet intended.
3. For sweet corn: use the field corn curve shortened to the earlier harvest, a GDD-based curve, or percent cover only?
4. Are there trustworthy curves for potato, snap bean or soybean, the other big Wisconsin irrigated crops? If not, those crops should only be offered percent cover, or LAI with entered observations.
5. Is it useful to let growers **enter LAI readings** (from a ceptometer or app) that override the curve, as they can with percent cover?

**Options:**

| Option | What growers get | Risk |
|---|---|---|
| A. Corn curve for field corn only; everything else uses percent cover | Simple and honest | Loses LAI for other crops; little value lost if nobody uses it |
| B. A + entered LAI observations allowed for any crop | Flexible for advanced users | Needs a good help page on how to measure LAI |
| C. GDD-based curves per crop | Most realistic | Needs validated curves, which we don't have yet |

**Decision:** ship **A + B** for 2027 (already reflected in §5.3). *Revised 2026-10-15 (Phase 6.7): B is dropped; LAI only for crops with an LAI curve.* An agronomist has been contacted with the questions above. **C (curves per crop, by GDD or calendar days) is brought forward to Phase 6.7 (2026-10-15).**

Groundwork in the meantime: Phase 3 stores daily tmax/tmin and calculates daily and cumulative GDD (base 50 °F, 86 °F cap, the standard corn method). GDD-based curves then need no new data plumbing, and GDD can be shown in the UI.

**Production usage query** (run on the legacy production server; it only reads):
```bash
cd ~/wisp/current && RAILS_ENV=production bundle exec rails runner '
  recent = Field.joins(:pivot).where(pivots: {cropping_year: 2025..})
  puts "Fields by ET method: #{recent.group(:et_method).count.inspect}  (1 = pct cover, 2 = LAI)"
  lai = recent.where(et_method: 2).includes(crops: :plant).map { |f| f.crops.max_by(&:emergence_date)&.plant&.name }.tally
  puts "LAI fields by crop: #{lai.inspect}"
  puts "Groups set to Manual rainfall: #{Group.where(precip_use_agwx: false).count} of #{Group.count}"
  puts "irrigation_events rows: #{IrrigationEvent.count}"
  puts "Fields per pivot (fields => pivots): #{Pivot.joins(:fields).where(cropping_year: 2025..).group(:id).count.values.tally.sort.inspect}"
  puts "Pivots still at default 43,-89: #{Pivot.where(latitude: 43, longitude: -89).count} of #{Pivot.count}"
'
```
**Given the numbers:**
- Option A alone would move 23 fields (mostly potato) to percent cover, which is arguably *more* correct than the corn curve they had.
- A + B lets those growers keep LAI if they enter readings.
- A potato canopy curve would be the single most valuable result of the agronomy review (question 4).

Ask for the review in Phase 2 so its answer can land in the engine before the Phase 4 UI.

### Q3. Display units: resolved

- **Storage stays in inches** everywhere. Units are a display and input concern only.
- **Per-user setting** `users.unit_system` (`imperial` default | `metric`) in a Settings menu, applying to:
  - water depths (in ↔ mm)
  - temperatures (°F ↔ °C)
  - area (ac ↔ ha)
  - pump capacity (gpm ↔ L/s)
- Percent values (soil moisture, cover, MAD) don't change.
- **Implementation:**
  - A small `units.ts` module of formatters and parsers, used by every display and input.
  - Conversion happens only at that edge.
  - Serializers always send inches.
  - The editable grid parses user input in the chosen unit and converts back to inches before submitting.
  - Phase 4.

### Q4. Pivot-level irrigation: resolved

Use case (from you): a pivot covers 1–2 fields (a split for two crops or two varieties), and usually all of them get the same water. The design is in §4 (`pivot_irrigations`) and D9:
- Entered once on the pivot, as inches or run hours.
- Applies to every field under the pivot, or a chosen subset.
- Applied when read, so editing the pivot entry updates every field.
- A per-field value overrides it.

The legacy `irrigation_events` table had no routes, so nothing should be in it; the usage query above confirms.

### Q5. `systemd --user` on the servers: resolved

- **Staging:** `Linger=yes`, and user services work. WISP 3 staging runs `wisp-jobs.service` (and optionally `wisp-web.service`) as `deploy`.
- **Old production:** both checks failed; out of scope, since WISP 3 production goes on a new server (D11). Its requirements in §12 include `loginctl enable-linger deploy`.
- **Before handing the new server over,** re-run the check from the staging test (start a throwaway user service, log out, log back in, confirm it's still active).

### Q6. Alert email sender and DKIM

*Resolved (2026-11):* production sends through Amazon SES's SMTP interface with the sender verified and DKIM passing, out of the sandbox (Phase 8 D, `docs/deployment.md` step 7). Staging still uses the host's sendmail. The questions below were for the old campus setup.

The app currently sends as `agweather@cals.wisc.edu` through local `sendmail`. Ask campus IT:
1. Is mail from these hosts relayed through a campus server that signs DKIM for `cals.wisc.edu`?
2. Does the SPF record cover these hosts?
3. Is a daily digest to a few hundred recipients acceptable volume?

If any answer is no, use an authenticated SMTP relay (campus relay or a transactional email provider) in the production Action Mailer config. Sending a test to a Gmail address and reading "Show original" will show SPF/DKIM pass or fail.

### Q7. Rainfall corrections: resolved

- **Per-day overrides only**, plus the group-level modeled/manual switch. No multiplier: rainfall is highly localized, so a fixed ratio wouldn't hold from storm to storm.
- **Modeled values always stay visible next to entered corrections**:
  - **Daily grid:** an overridden rain cell shows the entered value with the modeled value beside it in muted text (e.g. `0.80  (model 0.35)`); hovering or tapping shows both and their difference.
  - **Chart:** an entered rain bar is drawn solid, with the modeled amount as an outlined "ghost" bar behind it.
  - **Field summary:** season totals of entered vs modeled rain over the days with entries, so growers can see how their gauge compares with the model.
- The resolver (§4) already keeps both values; it returns `rain_model_in` alongside the resolved `rain_in` and its provenance.
- Revisit a correction factor after a season of gauge-vs-model data.

**Added (2026-10-07, Ben):** the modeled/manual switch can also be **set per field** (Phase 6.6). It is a setting read when the balance runs; it never copies or deletes entries, so switching back restores the modeled rain exactly.
- **Entered-only applies through today; the projection still uses forecast rain.** Nobody can enter future rain, and the forecast is expected to be roughly right; growers choosing entered-only mostly want exact amounts, or know storms often miss their field. This changes the existing group-level switch too (it zeroed forecast rain).
- **Entered-only fields also show a "no rain" projection**: the same balance with no forecast rain (planned irrigation kept), so the grower sees both the forecast case and the dry case. Status, "Irrigate by" and the digest follow the forecast case.
- Field rain entries and field-group rain entries both count as entered.

**Changed (2026-11-19, Ben): the setting is a farm's and an irrigation group's, not the operation's or a field's.** Irrigation groups (G.4) came after the per-field setting, and are the systems sharing a rain gauge, so whether to trust that gauge alone belongs with them; a farm is a compact area where rain runs alike, while an operation can span several far apart. `farms.use_model_precip` (default true, copied from the operation's) and `pivot_groups.use_model_precip` (nullable; NULL follows the farm's) replaced `groups.use_model_precip` and `fields.use_model_precip`, with no field data to move (production not yet announced). `Pivot#use_model_precip?` resolves it; a planting reads its own system's (`Planting#system`, the season's even after its field moved), daily entry and the field page the field's system now. Set in the farm's and group's dialogs in Setup, by anyone who can edit them (this loosens Q8: the rainfall setting was owner-only as the operation's); the operation page keeps only its name. The field page's "Rainfall preferences" section is gone: its rain grid notes an entered-only setting, and "Change this" (there and on the planting page) opens the group's dialog, or the farm's for a system in no group (`lib/rainSetting.ts`). Setup's farm and group rows, and daily entry's farm heading and group rows (`rainNote`, where a group differs from its farm), note the setting.

### Q8. Group member roles

Today every member of a group can do everything: rename it, switch its rainfall setting, and delete farms, pivots and fields. That's fine while each group has one person, but invitations (Phase 8 stretch) need a decision. Suggestion: **owner** (everything, including managing members and deleting) and **member** (data entry and setup, but not deleting farms or the group, or managing members). `memberships.admin` already exists and could become the owner flag.

**Decided (2026-10-04):** owner and member as suggested. `memberships.admin` is renamed `owner`. Owners only: the group's name (and its rainfall setting, until that moved to farms and irrigation groups on 2026-11-19, Q7), adding and removing members and changing roles, and deleting farms, pivots, fields or the group (`AuthenticatedController#require_owner`). Members can do everything else, including deleting plantings, irrigation and field groups. Members are added by the email of an existing, confirmed account; there are no invitations for people without one. A group always has an owner: the last owner can't step down or leave, and deleting the account of a group's only owner hands it to its longest-standing member.
