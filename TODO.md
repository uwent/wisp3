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
- [x] **Turn off SES click/open tracking.** Postfix on the staging host relays through Amazon SES (`email-smtp.us-west-2.amazonaws.com`), which rewrites every link through `awstrack.me`. Ad blockers flag that, and it affects ag-weather's daily emails too. In the SES configuration set the mail uses (likely the identity's default), remove the **Click** and **Open** event types from its event destination; keep Bounce, Complaint and Delivery. Bounce handling and the suppression list don't depend on tracking.

## Legacy WISP

- [x] If not done yet, run the rainfall backfill on production: `DRY_RUN=1 bundle exec rake precip:backfill`, review the output, then run it without `DRY_RUN`.
- [x] Optional: tell the one sweet corn + LAI grower their 2026 water balance was wrong (PLAN.md C18).
- [x] **Export golden-test fixtures** from legacy production (done 2026-10-03; 30 fields, all passed; the tests have since been retired). You can delete `tmp/wisp_golden.json`.
- [ ] **After Nov 30, and before Feb 15:** take an archive `pg_dump` of legacy production.

## Phase 4 and 4.5

- [x] **Push `main` and `bundle exec cap staging deploy`**, then click through on staging: dashboard, a field page (edit a cell, Escape cancels), daily entry, setup, a pivot's irrigation page. GitHub Actions now runs the Playwright smoke tests too (`bin/e2e` locally).

## Phase 6: daily email (next)

- [x] **Deploy and check the digest on staging.** It goes out at 6 am Central to every confirmed user with a field in season (daily by default; users can pick "Only when irrigation is needed" or "Never" on the Alerts page). Before the first morning, preview it and send yourself a test from the Alerts page; admins can preview anyone's from their user page.
- [x] **SPF and DKIM (Q6):** in Gmail, open the digest → "Show original" and check SPF and DKIM both say PASS. If not, ask campus IT (PLAN.md Q6). Also try the one-click "Unsubscribe" Gmail shows next to the sender.
- [x] **Exit check:** on staging, set up test fields for a rain refill, a sudden heat spell, and planned irrigation pushing back "Irrigate by", and check the digests read right.

## Phase 6.6: field rain setting and season details

- [x] **Deploy to staging** (`bundle exec cap staging deploy`); it runs the new migration (`fields.use_model_precip`).
- [x] **Exit check:** on staging, pick a field with a few weeks of rain gauge readings (or enter some), then:
  - At the bottom of its page, switch it to "Only the rain you enter" and save. The summary card should say "Rain: only what you enter…", and the season details show the modeled rain left out of the balance.
  - Check the projection shows both cases: the dotted "If no rain falls" line on the soil-water chart, the "AD if no rain" column in the forecast table, and "If no rain falls: irrigate by …" in the outlook (and in the daily email) when that's sooner.
  - Check the precipitation chart (weather section) and the season details agree with the daily grid: entered rain beside the model's, outlined modeled rain where it isn't used.
  - Switch back to "The operation's setting" and check the balance and season totals return to what they were.

## Phase 6.7: canopy curves, tasks and the daily email

- [x] **Deploy to staging** (`bundle exec cap staging deploy`). Three migrations run: non-corn LAI plantings switch to percent cover (their readings kept), `plantings.canopy_interpolation`, and `users.digest_scope` with the new "Daily all year" frequency.
- [ ] **Exit check on staging:**
  - A percent cover planting with no readings now follows its crop's curve (the dashed line on the field page's canopy panel), and its water use rises with it. Fields that had no readings will show more ET than before.
  - Enter a few readings and check the canopy passes through them; enter one that runs well ahead of the curve, or drops, and check the warning on the field page, the dashboard card and the email.
  - Read the About page's "Canopy curves" section and the crop cards, and the "How … is modeled" text on a field page. Change any wording you don't like (the curves' notes are in `db/reference/canopy_curves.yml`).
  - On the Alerts page, try each "Fields in the email" choice and "Daily all year", and check the preview: the hierarchy, the collapsed operation/farm line, the to-do lines and the counts in the footer.
- [ ] **Potato canopy model from the researcher:** when it arrives, send it to the next session. It replaces the AquaCrop potato curve and the August 1 decline rule (`db/reference/canopy_curves.yml`, `potato`), checked against the 2026 readings (`docs/canopy/`) and documented on the About page with its source.
- [ ] **LAI curves from the other researcher:** each one goes into `CanopyModel` (`app/services/canopy_model.rb`) with its source, and the crop's `canopy_model` in `db/reference/plants.yml`; that crop then gets the LAI option. Say which crops and what each curve is driven by (days since emergence or degree-days).
- [ ] **Agronomist review** of the curves: the questions under "For the agronomist" in `docs/canopy/03-crop-curves.md` (onion, the k = 1.5 LAI formula, winter wheat). An answer replaces a curve or its confidence label; nothing needs to wait for it.
- [ ] You can delete `tmp/legacy_wisp/` (the legacy cover readings export; what it showed is in `docs/canopy/01-legacy-readings.md`).

## Phase 7: map and soil types

- [x] **Deploy to staging** (`bundle exec cap staging deploy`; no migrations). The deploy reloads the soil types: four new ones, and new values for sandy loam, loam, silt loam and clay loam, so staging fields on those soils that don't set their own values change (PLAN.md Phase 7 F).
- [x] **Exit check on staging:** the Map tab shows every pivot with its fields' badges; selecting a field in the list and a pivot on the map select each other; "Needs water within 7 days" dims the rest; each layer loads with its legend and time, and pointing at the map gives its value (compare "Rain, last 24 hours" with a gauge you trust). In setup, place a pivot you know and check the suggested soil and the Soil types layer.
- [x] **About page:** read the new Soils section and its table, and the Map entry under Day to day.

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

- [x] **Put your Open-Meteo key in `.env`** (copy `.env.example`; `.env` is gitignored): `OPEN_METEO_API_KEY=…`. Then `bin/rails weather:refresh` and check `/admin/weather` says "commercial API key" with no errors (the local demo user `demo@example.com` / `demo-password-1` is an admin). Tell the next session if it fails.
- [x] **Review `docs/weather-comparison.md` and the model decision** (NBM, then best_match; PLAN.md §8.2, §8.4). Change with `OPEN_METEO_MODELS` if you disagree.
- [x] **Look into the early first irrigation:** on all three Open-Meteo models the standard field's first irrigation comes 10–16 days earlier than on AgWeather (season totals are close). Worth knowing whether AgWeather's early-season ET is low, or its spring rain high, before growers compare the two.
- [x] Optional, before the beta: re-run the comparison at real pivot locations. On legacy production (read-only): `cd ~/wisp/current && RAILS_ENV=production bundle exec rails runner 'puts "name,lat,lng"; Pivot.where(cropping_year: 2025..).where.not(latitude: 43, longitude: -89).distinct.pluck(:latitude, :longitude).map { |a, b| [a.round(2), b.round(2)] }.uniq.each_with_index { |(a, b), i| puts "pivot_#{i},#{a},#{b}" }' > /tmp/pivots.csv`, copy it to `tmp/pivots.csv`, then `bin/rails weather:compare POINTS=tmp/pivots.csv` (with the key; a few hundred points is fine on the commercial API).
- [x] Sysadmin requirement (PLAN.md §12) is unchanged: outbound HTTPS to `*.open-meteo.com`.

## Waiting on other people (start early)

- [ ] **Sysadmin:** send the new production server requirements (PLAN.md §12 table). Target: ready by February.
- [x] **Campus IT, email (Q6):**
  - Do mails from these hosts get DKIM-signed for `cals.wisc.edu`?
  - Does SPF cover these hosts?
  - Is a daily digest to a few hundred recipients OK?
- [ ] **Agronomist, LAI (Q2):** the five questions in PLAN.md §15 Q2, now with the Phase 6.7 research (see the Phase 6.7 section above). The potato curve may come from your researcher contact instead.

## Decisions still open

- [ ] **Group member roles** (PLAN.md Q8): owner vs member, before group invitations.
- [ ] Production hostname for the new server (set as `PRODUCTION_HOST` when deploying).
- [ ] Legacy hostname after launch (PLAN.md suggests `legacy.wisp.cals.wisc.edu`).
