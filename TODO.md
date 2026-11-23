# TODO (Ben)

Things only you can do, roughly in order. Done items are removed (their record is in [docs/plans/](docs/plans/) and git history); steps you'd repeat on another setup are in [DEVELOPMENT.md](DEVELOPMENT.md) and [docs/deployment.md](docs/deployment.md).

## Now (launched 2026-11-19; the winter is the beta)

- [ ] **Restore an RDS snapshot** to a scratch instance once and check the app against it (docs/deployment.md, Production step 8; IT may need to do the restore).
- [ ] **Announcement email** to legacy users from the legacy app (new address, create a new account, sign-in links, the training session), its links tagged `utm_source=legacy&utm_medium=email&utm_campaign=launch` so GA credits it. **Training session.**
- [ ] **Screen reader walkthrough** (`docs/plans/7-launch.md`, Accessibility): the checklist in `docs/accessibility.md`, about an hour, with NVDA or Orca and VoiceOver on a phone. You or a tester.
- [ ] **Google Analytics settings** (`docs/plans/7-launch.md`, Analytics, H.1), in the new GA4 property: Enhanced measurement off (the whole toggle); Google signals off; ads personalization and data sharing off; event data retention 14 months; optionally your own visits as internal traffic. Mark `sign_up` and `example_open` as key events once they've appeared. Check the property's stream URL is `wisp.cals.wisc.edu`.
- [ ] Ask the large pivot growers whether importing from FieldNET or Valley 365 would decide whether they use WISP.
- [ ] **ET validation, the corn sites** (`docs/et-validation/05`): Paul Stoy's group, for US-CC1 and CC2 (2021): field or sweet corn, planting and harvest dates, irrigated or not. (06's suggested changes for potato were made as C22–C25; Desai's group has no more questions to answer.)
- [ ] **Canopy curves in growing degree days** (C23, `docs/canopy/07-thermal-time.md`): potato runs on degree days; the other crops stay on calendar days (Ben, 2026-11-19), with their conversions kept as `thermal_candidate:` in `db/reference/canopy_curves.yml`. After the 2027 season, check them against its readings (`docs/canopy/scripts/thermal_backtest.rb`) and rename a crop's `thermal_candidate:` to `thermal:` where degree days do better.
- [ ] **Reference ET in FAO-56 Rev.1's form** (C24, 2026-11-19): WISP's ET0 is on `et0-fao56 v2` (about 5% more than v1); AgWeather v2 still computes the 1998 form: once it adopts Rev.1, drop the swap from `docs/weather-corrections/v2_expected.py` and rerun it.

## Legacy shutdown (December 31, 2027)

- [ ] **Legacy archive:** take an archive `pg_dump` of legacy production before it's deleted.
- [ ] **Delete legacy** (`old.wisp.cals.wisc.edu`) with IT, and its DNS record.

## Waiting on others

- If a researcher's potato canopy model or LAI curves arrive after all, hand them to a session (`docs/plans/4-crop-and-weather-science.md` and PLAN.md's backlog: each goes into `canopy_curves.yml` or `CanopyModel` with its source).
