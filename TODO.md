# TODO (Ben)

Things only you can do, roughly in order. Details for each are in [PLAN.md](PLAN.md) and [docs/deployment.md](docs/deployment.md).

## Staging deploy (blocks seeing WISP 3 on dev.wisp)

- [x] **Back up the staging credentials key.** `config/credentials/staging.key` exists only on this machine and is not in git. Put a copy in your password manager.
- [x] **Create the Postgres role on staging** (needs a Postgres superuser on `dev.agweather.cals.wisc.edu`):
  1. Get the password locally: `bin/rails credentials:show --environment staging` (`database.password`)
  2. On the server: `CREATE ROLE wisp3 LOGIN CREATEDB PASSWORD '<that password>';`
- [x] **First `cap staging deploy`** (2026-10-03). Puma is answering on `127.0.0.1:3100`.
- [x] **Switch the nginx site** for `dev.wisp.cals.wisc.edu` to Puma on `127.0.0.1:3100` (new `sites-available/wisp3`; the legacy site's config is kept).
- [x] Sign up on staging and check that the confirmation and sign-in-link emails arrive (sent with the host's `sendmail`). Confirmation arrives; scanners using up the link is fixed.
- [ ] **Turn off SES click/open tracking.** Postfix on the staging host relays through Amazon SES (`email-smtp.us-west-2.amazonaws.com`), which rewrites every link through `awstrack.me`. Ad blockers flag that, and it affects ag-weather's daily emails too. In the SES configuration set the mail uses (likely the identity's default), remove the **Click** and **Open** event types from its event destination; keep Bounce, Complaint and Delivery. Bounce handling and the suppression list don't depend on tracking.

## Legacy WISP

- [x] If not done yet, run the rainfall backfill on production: `DRY_RUN=1 bundle exec rake precip:backfill`, review the output, then run it without `DRY_RUN`.
- [x] Optional: tell the one sweet corn + LAI grower their 2026 water balance was wrong (PLAN.md C18).
- [x] **Export golden-test fixtures** from legacy production (done 2026-10-03; 30 fields, all tests pass).
- [ ] **Decide whether the golden fixtures can go in the public repo.** `spec/fixtures/legacy/*.json` (2.9 MB, local only for now) holds no names, locations or IDs, but does hold real per-field daily rain, irrigation, soil parameters and crop. They are gitignored until then (remove the line in `.gitignore` to commit them). If they can't be public, they stay local, and CI on GitHub skips the golden tests (`bin/ci` runs them on any machine that has them).
- [ ] Optional: re-run the export for better coverage. 18 of the 30 exported fields never received reference ET, so they only test a flat line; the script now picks only fields with at least 60 days of reference ET. Same commands as before (`scp -P 216 script/legacy/export_golden_fixtures.rb deploy@wisp.cals.wisc.edu:/tmp/`, then `rails runner` on the server), then `bin/rails golden:import FILE=tmp/wisp_golden.json` (delete the old `spec/fixtures/legacy/*.json` first).
- [ ] **After Nov 30, and before Feb 15:** take an archive `pg_dump` of legacy production. The AgWeather comparison export (PLAN.md §8.4) is still to be written, in Phase 3.

## Staging (non-blocking)

- [ ] Push `main` and `bundle exec cap staging deploy` to get Phase 2 onto staging. The deploy now also loads plants and soil types. (The plantings migration enables `btree_gist`; checked that `wisp3` may do that on staging.)
- [ ] Optional: `cd ~/wisp3/current && RAILS_ENV=staging bin/rails demo:seed EMAIL=you@… PASSWORD=…` on the server, for a demo account with farms and fields there (nothing shows them until Phase 4).

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
