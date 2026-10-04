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
- [x] **Export golden-test fixtures** from legacy production (done 2026-10-03; 30 fields, all passed; the tests have since been retired). You can delete `tmp/wisp_golden.json`.
- [ ] **After Nov 30, and before Feb 15:** take an archive `pg_dump` of legacy production.

## Phase 4 and 4.5 (next)

- [ ] **Push `main` and `bundle exec cap staging deploy`**, then click through on staging: dashboard, a field page (edit a cell, Escape cancels), daily entry, setup, a pivot's irrigation page. GitHub Actions now runs the Playwright smoke tests too (`bin/e2e` locally).
- [ ] **A stray `pnpm-lock.yaml`** appeared in the repo root during the 2026-10-03 session (not from Claude, which uses npm). It's untracked; delete it unless you're switching to pnpm.

## Staging (non-blocking)

- [x] **Add the Open-Meteo key to staging credentials** before deploying: `bin/rails credentials:edit --environment staging`, add
  ```yaml
  open_meteo:
    api_key: <your key>
  ```
  (Without it staging uses the free API, which also works.)
- [x] Push `main` and `bundle exec cap staging deploy` to get Phases 2 and 3 onto staging. The deploy loads plants and soil types; the jobs service then refreshes weather at 5am, 11am and 5pm Central. (The plantings migration enables `btree_gist`; checked that `wisp3` may do that on staging.)
- [x] Make yourself an admin on staging, to see `/admin/weather`: `ssh -p 216 deploy@dev.agweather.cals.wisc.edu`, then `cd ~/wisp3/current && RAILS_ENV=staging bin/rails runner 'User.find_by!(email: "you@…").update!(admin: true)'`.
- [x] Optional: `RAILS_ENV=staging bin/rails demo:seed EMAIL=you@… PASSWORD=…` in the same place, then `RAILS_ENV=staging bin/rails weather:refresh`, for a demo account with farms, fields and a season of weather.

## Weather (Phase 3 follow-ups)

- [ ] **Put your Open-Meteo key in `.env`** (copy `.env.example`; `.env` is gitignored): `OPEN_METEO_API_KEY=…`. Then `bin/rails weather:refresh` and check `/admin/weather` says "commercial API key" with no errors (the local demo user `demo@example.com` / `demo-password-1` is an admin). Tell the next session if it fails.
- [ ] **Review `docs/weather-comparison.md` and the model decision** (NBM, then best_match; PLAN.md §8.2, §8.4). Change with `OPEN_METEO_MODELS` if you disagree.
- [ ] **Look into the early first irrigation:** on all three Open-Meteo models the standard field's first irrigation comes 10–16 days earlier than on AgWeather (season totals are close). Worth knowing whether AgWeather's early-season ET is low, or its spring rain high, before growers compare the two.
- [ ] Optional, before the beta: re-run the comparison at real pivot locations. On legacy production (read-only): `cd ~/wisp/current && RAILS_ENV=production bundle exec rails runner 'puts "name,lat,lng"; Pivot.where(cropping_year: 2025..).where.not(latitude: 43, longitude: -89).distinct.pluck(:latitude, :longitude).map { |a, b| [a.round(2), b.round(2)] }.uniq.each_with_index { |(a, b), i| puts "pivot_#{i},#{a},#{b}" }' > /tmp/pivots.csv`, copy it to `tmp/pivots.csv`, then `bin/rails weather:compare POINTS=tmp/pivots.csv` (with the key; a few hundred points is fine on the commercial API).
- [ ] Sysadmin requirement (PLAN.md §12) is unchanged: outbound HTTPS to `*.open-meteo.com`.

## Waiting on other people (start early)

- [ ] **Sysadmin:** send the new production server requirements (PLAN.md §12 table). Target: ready by February.
- [ ] **Campus IT, email (Q6):**
  - Do mails from these hosts get DKIM-signed for `cals.wisc.edu`?
  - Does SPF cover these hosts?
  - Is a daily digest to a few hundred recipients OK?
- [ ] **Agronomist, LAI (Q2):** the five questions in PLAN.md §15 Q2. The most valuable answer is a potato canopy curve. Ideally get answers before Phase 4 (Dec–Jan).

## Decisions still open

- [ ] **Group member roles** (PLAN.md Q8): owner vs member, before group invitations.
- [ ] Production hostname for the new server (set as `PRODUCTION_HOST` when deploying).
- [ ] Legacy hostname after launch (PLAN.md suggests `legacy.wisp.cals.wisc.edu`).
