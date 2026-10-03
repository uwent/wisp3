# TODO (Ben)

Things only you can do, roughly in order. Details for each are in [PLAN.md](PLAN.md) and [docs/deployment.md](docs/deployment.md).

## Staging deploy (blocks seeing WISP 3 on dev.wisp)

- [x] **Back up the staging credentials key.** `config/credentials/staging.key` exists only on this machine and is not in git. Put a copy in your password manager.
- [x] **Create the Postgres role on staging** (needs a Postgres superuser on `dev.agweather.cals.wisc.edu`):
  1. Get the password locally: `bin/rails credentials:show --environment staging` (`database.password`)
  2. On the server: `CREATE ROLE wisp3 LOGIN CREATEDB PASSWORD '<that password>';`
- [x] **First `cap staging deploy`** (2026-10-03). Puma is answering on `127.0.0.1:3100`.
- [x] **Switch the nginx site** for `dev.wisp.cals.wisc.edu` to Puma on `127.0.0.1:3100` (new `sites-available/wisp3`; the legacy site's config is kept).
- [ ] Sign up on staging and check that the confirmation and sign-in-link emails arrive (sent with the host's `sendmail`).

## Legacy WISP

- [ ] If not done yet, run the rainfall backfill on production: `DRY_RUN=1 bundle exec rake precip:backfill`, review the output, then run it without `DRY_RUN`.
- [ ] Optional: tell the one sweet corn + LAI grower their 2026 water balance was wrong (PLAN.md C18).
- [ ] **After Nov 30, and before Feb 15:** take an archive `pg_dump` of legacy production. The next session can write the scripts that export golden-test fixtures and AgWeather data; you run them on the server (PLAN.md §10, §8.4).

## Waiting on other people (start early)

- [ ] **Sysadmin:** send the new production server requirements (PLAN.md §12 table). Target: ready by February.
- [ ] **Campus IT, email (Q6):**
  - Do mails from these hosts get DKIM-signed for `cals.wisc.edu`?
  - Does SPF cover these hosts?
  - Is a daily digest to a few hundred recipients OK?
- [ ] **Agronomist, LAI (Q2):** the five questions in PLAN.md §15 Q2. The most valuable answer is a potato canopy curve. Ideally get answers before Phase 4 (Dec–Jan).

## Decisions still open

- [ ] Production hostname for the new server (set as `PRODUCTION_HOST` when deploying).
- [ ] Legacy hostname after launch (PLAN.md suggests `legacy.wisp.cals.wisc.edu`).
