# TODO (Ben)

Things only you can do, roughly in order. Done items are removed (their record is in [PLAN.md](PLAN.md) and git history); steps you'd repeat on another setup are in [DEVELOPMENT.md](DEVELOPMENT.md) and [docs/deployment.md](docs/deployment.md).

## Before the beta

- [ ] **Restore an RDS snapshot** to a scratch instance once and check the app against it (Eric may need to; docs/deployment.md, Production step 8).
- [ ] **Wording review in the app**, one pass: the About page (including cuttings and the glossary's canopy curve entry, G.3), the crop cards and canopy curves' notes (`db/reference/canopy_curves.yml`), and "How … is modeled" on a planting page. Contact details on About.
- [ ] **Screen reader walkthrough** (Phase 8 A): the checklist in `docs/accessibility.md`, about an hour, with NVDA or Orca and VoiceOver on a phone. You or a tester.
- [ ] **Recruit the open beta** (Phase 8 D): every existing WISP user, plus growers of every scale and extension agents who didn't use it, each setting up their own operation on production (anyone can sign up). Ask the large pivot growers whether importing from FieldNET or Valley 365 would decide whether they use WISP.

## Launch (by about March 20, 2027)

- [ ] **Legacy archive:** after Nov 30 and before Feb 15, take an archive `pg_dump` of legacy production.
- [ ] **Decide legacy's hostname** after launch (PLAN.md suggests `legacy.wisp.cals.wisc.edu`).
- [ ] **Launch steps** (PLAN.md §13, Phase 8 D): legacy read-only (sign-ups off, a banner pointing to WISP 3); `wisp.cals.wisc.edu` to the EC2 server and `APP_HOST` changed in `/opt/wisp/.env` (docs/deployment.md, Production step 3); the announcement email to legacy users from the legacy app.

## Waiting on others

- If a researcher's potato canopy model or LAI curves arrive after all, hand them to a session (PLAN.md Phase 6.7 and After launch: each goes into `canopy_curves.yml` or `CanopyModel` with its source).
