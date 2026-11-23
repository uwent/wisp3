# Phase 0: Legacy housekeeping

*A record of the build, frozen when it was folded out of `PLAN.md` on 2026-11-22: it says what was planned and done at the time, and later work may have changed or replaced it. For how the app works now, see [docs/architecture.md](../architecture.md) and [docs/engine.md](../engine.md); for why, [docs/decisions.md](../decisions.md). Section numbers (§) refer to the original design ([design.md](design.md)), except §2 and §15, now [docs/decisions.md](../decisions.md), and §9, now [docs/legacy-audit.md](../legacy-audit.md).*

Code committed on branch `phase0-hotfixes` in `../wisp` (`1abdb8f`, 268 specs passing); deployed and the backfill run (October 2026). Only the archive `pg_dump` remains.

- [x] Hotfix S1: every lookup driven by params or session goes through `current_group` (`ApplicationController#group_scope`); `spec/requests/tenant_isolation_spec.rb` (29 cross-tenant cases; 20 failed before the fix).
- [x] Hotfix C1: `Field#get_precip` condition corrected, with model specs.
- [x] `rake precip:backfill` (`DRY_RUN=1` to preview): refills AgWeather rainfall for current-season fields in Auto groups, keeps user entries, and lists Manual groups that received unwanted AgWeather rainfall while the bug was live.
- [x] Feb 15 `yearly:reset` cron disabled in `config/schedule.rb` (the task can still be run by hand).
- [x] Push, merge to `main`, `cap staging deploy`, smoke test, `cap production deploy`. Whenever's Capistrano hook rewrites the crontab, which removes the reset job. *(Done, October 2026.)*
- [x] Production: `DRY_RUN=1 bundle exec rake precip:backfill`, review, then run it for real (1 of 183 groups is set to Manual). *(Done, October 2026.)*
- [x] Usage query run on production (results in Q2). Only 1 sweet corn + LAI field and the season is over, so no C18 legacy hotfix.
- [ ] After Nov 30 (and before Feb 15): archive `pg_dump` of legacy production. *(The golden-test fixtures were exported 2026-10-03 (Phase 2), and the AgWeather comparison re-run at the real pivot locations (§8.4); only the archive remains, in TODO.md.)*
