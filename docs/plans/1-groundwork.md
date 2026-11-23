# Phase 1: Groundwork

October 2–3, 2026. The legacy app's hotfixes before its last season ended, and the new app's foundation: Rails, Inertia and Svelte, sign-in, tenancy, CI and staging.

*A record of the build, frozen on 2026-11-22. It was planned and written in phases 0–9, regrouped here by theme; each section's heading gives its old number, and [README.md](README.md) maps every old phase and section ID to its place. Cross-references inside the text ("G.14 part 7", "Phase 6.7", "§5.3") use the old numbers. Later work may have changed what's described: for how the app works now, see [docs/architecture.md](../architecture.md) and [docs/engine.md](../engine.md); for why, [docs/decisions.md](../decisions.md).*

## Legacy housekeeping (was Phase 0)

Code committed on branch `phase0-hotfixes` in `../wisp` (`1abdb8f`, 268 specs passing); deployed and the backfill run (October 2026). Only the archive `pg_dump` remains.

- [x] Hotfix S1: every lookup driven by params or session goes through `current_group` (`ApplicationController#group_scope`); `spec/requests/tenant_isolation_spec.rb` (29 cross-tenant cases; 20 failed before the fix).
- [x] Hotfix C1: `Field#get_precip` condition corrected, with model specs.
- [x] `rake precip:backfill` (`DRY_RUN=1` to preview): refills AgWeather rainfall for current-season fields in Auto groups, keeps user entries, and lists Manual groups that received unwanted AgWeather rainfall while the bug was live.
- [x] Feb 15 `yearly:reset` cron disabled in `config/schedule.rb` (the task can still be run by hand).
- [x] Push, merge to `main`, `cap staging deploy`, smoke test, `cap production deploy`. Whenever's Capistrano hook rewrites the crontab, which removes the reset job. *(Done, October 2026.)*
- [x] Production: `DRY_RUN=1 bundle exec rake precip:backfill`, review, then run it for real (1 of 183 groups is set to Manual). *(Done, October 2026.)*
- [x] Usage query run on production (results in Q2). Only 1 sweet corn + LAI field and the season is over, so no C18 legacy hotfix.
- [ ] After Nov 30 (and before Feb 15): archive `pg_dump` of legacy production. *(The golden-test fixtures were exported 2026-10-03 (Phase 2), and the AgWeather comparison re-run at the real pivot locations (§8.4); only the archive remains, in TODO.md.)*

---

## Foundation (was Phase 1)

- [x] `rails new` (Rails 8.1, Postgres, no Hotwire/importmap/asset pipeline) in `wisp3`; git; public GitHub repo `uwent/wisp3`; CI (`bin/ci`, run by GitHub Actions).
- [x] `vite_rails`, `inertia_rails` (Inertia v3), Svelte 5 + TS, Tailwind v4 (`@tailwindcss/vite`), `bits-ui`, Alba + Typelizer (types and route helpers).
- [x] App shell: layout, navigation, user menu, group switcher, status color tokens, light/dark (follows system), responsive at phone widths.
- [x] Devise + Inertia auth pages (sign up, sign in, confirmation, password reset, settings with email/password change and account deletion), **sign-in links and codes**, rate limits (Rails `rate_limit` + Rack::Attack).
- [x] Group / membership / `Current.group` tenancy, with cross-tenant request specs.
- [x] Capistrano config, systemd user units, nginx example, staging credentials; first-time setup steps in `docs/deployment.md`.
- [x] First deploy to staging (2026-10-03): Puma answers on 127.0.0.1:3100 and both services are enabled. nginx serves it at https://dev.wisp.cals.wisc.edu.
- [x] Send the §12 server requirements to the sysadmin so the new production box is ready by February. *(Production went to AWS instead: EC2, RDS, ECR and SSM, ready October 2026; deployed with Docker, `bin/production`.)*
- **Exit:** a user can sign up, confirm, sign in by password or link, and see an empty dashboard on staging. *(Verified locally in a headless browser, desktop and phone/dark; staging live 2026-10-03; sign-up and the confirmation email checked on staging.)*
