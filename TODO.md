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
- [ ] **ET validation, waiting on Desai's group** (`docs/et-validation/02-data.md`, asked 2026-11-19): canopy cover, planting, emergence, vine kill and harvest dates for US-CS1, CS3, CS4, CS5, CS6 and CS8 (2018–2023), irrigation records if kept, and how they handled energy balance closure (CS1, CS3 and CS4 have no soil heat flux in AmeriFlux). Also worth asking: the low albedo at CS6 and CS8 (0.07–0.12) and CS8's large soil heat flux (03). And Paul Stoy's group, for US-CC1 and CC2 (2021): field or sweet corn, planting and harvest dates, irrigated or not (05).

## Legacy shutdown (December 31, 2027)

- [ ] **Legacy archive:** take an archive `pg_dump` of legacy production before it's deleted.
- [ ] **Delete legacy** (`old.wisp.cals.wisc.edu`) with IT, and its DNS record.

## Waiting on others

- If a researcher's potato canopy model or LAI curves arrive after all, hand them to a session (PLAN.md Phase 6.7 and After launch: each goes into `canopy_curves.yml` or `CanopyModel` with its source).
