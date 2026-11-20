# TODO (Ben)

Things only you can do, roughly in order. Done items are removed (their record is in [PLAN.md](PLAN.md) and git history); steps you'd repeat on another setup are in [DEVELOPMENT.md](DEVELOPMENT.md) and [docs/deployment.md](docs/deployment.md).

## Now (launched 2026-11-19; the winter is the beta)

- [ ] **Deploy legacy's retirement changes** (`../wisp`, written 2026-11-19): review, commit and push, then `cap production deploy`. Check on `old.wisp.cals.wisc.edu` that the banner shows, Sign up goes to the new WISP, and a password reset email links to `old.wisp…`.
- [ ] **Restore an RDS snapshot** to a scratch instance once and check the app against it (docs/deployment.md, Production step 8; IT may need to do the restore).
- [ ] **Announcement email** to legacy users from the legacy app (new address, create a new account, sign-in links, the training session), its links tagged `utm_source=legacy&utm_medium=email&utm_campaign=launch` so GA credits it. **Training session.**
- [ ] **Wording review in the app**, one pass: the About page (including cuttings and the glossary's canopy curve entry, G.3), the crop cards and canopy curves' notes (`db/reference/canopy_curves.yml`), and "How … is modeled" on a planting page. Contact details on About.
- [ ] **Screen reader walkthrough** (Phase 8 A): the checklist in `docs/accessibility.md`, about an hour, with NVDA or Orca and VoiceOver on a phone. You or a tester.
- [ ] **Google Analytics settings** (PLAN.md H.1), in the new GA4 property: Enhanced measurement off (the whole toggle); Google signals off; ads personalization and data sharing off; event data retention 14 months; optionally your own visits as internal traffic. Mark `sign_up` and `example_open` as key events once they've appeared. Check the property's stream URL is `wisp.cals.wisc.edu`.
- [ ] **Privacy wording** on the About page (Privacy, drafted), and whether UW–Madison asks anything more of a site using Google Analytics.
- [ ] Ask the large pivot growers whether importing from FieldNET or Valley 365 would decide whether they use WISP.
- [ ] **ET validation, the whole season** (`docs/et-validation/06-season.md`): decide which of 06's suggested changes to WISP 3's crop ET to make, if any (soil evaporation at low cover and after vine kill, ET in early August, canopy timing for April emergence). Desai's group's crop dates, irrigation and canopy cover arrived 2026-11-19 and are used as far as they hold up (02); no more questions to them. Still open: Paul Stoy's group, for US-CC1 and CC2 (2021): field or sweet corn, planting and harvest dates, irrigated or not (05).
- [ ] **Canopy curves in growing degree days** (C23, `docs/canopy/07-thermal-time.md`): potato runs on degree days; the other crops stay on calendar days (Ben, 2026-11-19), with their conversions kept as `thermal_candidate:` in `db/reference/canopy_curves.yml`. After the 2027 season, check them against its readings (`docs/canopy/scripts/thermal_backtest.rb`) and rename a crop's `thermal_candidate:` to `thermal:` where degree days do better. After deploying, `bin/rails weather:normals` fetches every cell's normals at once (otherwise the weather jobs fetch them as cells are looked at).
- [ ] **Potato's and corn silage's FAO-56 Rev.1 rows** (C25, `db/reference/plants.yml`): potato takes the long-season row (Kcb end 0.30), which puts August 7–18% below the towers; the short-season row (0.50) is closer through August and 2 points higher over the season (`docs/et-validation/06-season.md`, last section). Corn silage takes the high-moisture grain row; Rev.1 also has a silage row (Kcb 1.10 / 0.80).
- [ ] **Reference ET in FAO-56 Rev.1's form** (C24, 2026-11-19): after deploying, `bin/rails weather:recorrect` (then `CONFIRM=yes`) on staging and production refetches stored days so every day is on `et0-fao56 v2` (about 5% more ET0 than v1). AgWeather v2 still computes the 1998 form: once it adopts Rev.1, drop the swap from `docs/weather-corrections/v2_expected.py` and rerun it.

## Legacy shutdown (December 31, 2027)

- [ ] **Legacy archive:** take an archive `pg_dump` of legacy production before it's deleted.
- [ ] **Delete legacy** (`old.wisp.cals.wisc.edu`) with IT, and its DNS record.

## Waiting on others

- If a researcher's potato canopy model or LAI curves arrive after all, hand them to a session (PLAN.md Phase 6.7 and After launch: each goes into `canopy_curves.yml` or `CanopyModel` with its source).
