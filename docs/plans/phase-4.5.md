# Phase 4.5: Review fixes and polish

*A record of the build, frozen when it was folded out of `PLAN.md` on 2026-11-22: it says what was planned and done at the time, and later work may have changed or replaced it. For how the app works now, see [docs/architecture.md](../architecture.md) and [docs/engine.md](../engine.md); for why, [docs/decisions.md](../decisions.md). Section numbers (§) refer to the original design ([design.md](design.md)), except §2 and §15, now [docs/decisions.md](../decisions.md), and §9, now [docs/legacy-audit.md](../legacy-audit.md).*

From a review of Phases 1–4 (2026-10-03): bugs, plan items that slipped, and rough edges to finish before the projection work builds on these pages.

Done 2026-10-03; the staging deploy followed, and the member roles were decided (Q8, 2026-10-04). Also fixed: GitHub CI failed because `db:prepare` seeds reference data into a freshly created test database; `spec/rails_helper.rb` now clears it before the suite.

Bugs:
- [x] **Escape in a grid cell saves the draft.** Chromium fires `blur` when the focused input is removed, and `EditableCell`'s `onblur` calls `commit()` without checking that editing was cancelled. Reproduced in Playwright on the field grid (typing a note, then Escape, sent the PATCH). The jsdom test passes because jsdom doesn't blur on removal. Guard `commit` (a cancelled flag or `if (!editing) return`) and cover it in the Playwright smoke tests. *(Fixed; a Vitest case simulates the blur, and the e2e test fails without the fix.)*
- [x] Setup: "Delete this crop" closes the dialog even when the confirm is cancelled.

Slipped from the plan:
- [x] **Field-group percent cover** (§4 precedence: "group pct-cover entries become CanopyObservations on each member planting"). The field group grid has rain, irrigation, moisture and notes, but no cover column. *(A Cover column when a member has a percent-cover crop; saving writes `CanopyObservation.record` on each member's percent-cover planting that day; the grid shows their shared reading or "varies".)*
- [x] Playwright smoke tests in CI (carried over from Phase 4): sign in, the demo group, every page, one grid edit, one daily entry save, Escape-cancels. *(`bin/e2e`: own database `wisp3_e2e`, demo account with synthetic weather from `e2e/seed.rb`, desktop and phone/dark; a step in `bin/ci` and GitHub Actions, which uploads the report on failure.)*
- [x] Deploy Phases 4 and 4.5 to staging and smoke test there (each phase ends deployed to staging). *(Ben: push, then `bundle exec cap staging deploy`; TODO.md.)* *(Done.)*
- [x] Give unassigned §11/§12 items a phase, or cut them: admin users list, CSV, announcements and impersonation; the public landing and about pages; the admin email when a job fails or a cell's weather is more than 24 h stale. Suggest Phase 8 for all of them. *(Added to Phase 8.)*
- [x] Plan housekeeping: Phase 7's "moving a pivot triggers a backfill" already shipped in Phase 3 (`Pivot#backfill_weather`; the balance is recalculated on read). The Phase 1 and Phase 3 exit notes still say staging sign-up and email delivery and the commercial key are "still to check", but TODO.md marks them done. Reconcile both. *(Done.)*

Polish:
- [x] **Weather-pending state.** A new pivot shows blank ET and a flat AD line until its backfill lands, with no explanation. Show "Weather for this pivot is on the way" on the field page and dashboard card while the cell has no days. *(`PlantingStatus#weather_pending?`.)*
- [x] Daily entry: changing the date (arrows or picker), or leaving the page, silently drops unsaved values. Use `confirmUnsavedChanges` (the form already tracks `isDirty`).
- [x] Weather panels cover the whole season while the soil-water chart opens on the last 30 days. On a phone that's eight dense season-long charts. Open them on the same window as the main chart (or link their zoom), and consider collapsing them by default on narrow screens. *(Same window, scroll or pinch for more, collapsed on phones.)*
- [x] Phone header: the group switcher and user menu wrap to a second row, so about 140 px of chrome sits above the content. Fold them into one compact menu at phone widths. *(Two rows; the group switch moves into the account menu.)*
- [x] Pivot irrigation page: "Add an irrigation" for a date that already has one silently replaces it. Warn, or switch the form to editing that day. *(Warns, with "Edit that one instead".)*
- [x] Copy last season: plantings that fail validation are skipped silently. Report how many were skipped and why. *(The realistic case is a season running into the next year, whose copy overlaps it.)*
- [x] Farm notes exist in the model but can't be edited (the farm dialog has only the name).
- [x] Charts draw with the body font when they are built. If Red Hat Text hasn't loaded yet, canvas text falls back to the system font, so rebuild once `document.fonts.ready` resolves.
- [x] CSV export: prefix cells starting with `=`, `+`, `-` or `@` with `'` (spreadsheet formula injection from field, farm and note text).
- [x] Dashboard runs the full balance for each field, about 5 queries per field (~50 ms for 2 fields locally). Measure with 50+ fields and batch the loads before Phase 5 adds forecast and ensemble runs to every card. *(60 fields: 368 queries / ~830 ms → 13 queries / ~220 ms in the test environment, via `DailyInputs.preload` and `WeatherDay.balance_inputs_by_cell`. What remains is the balance itself; Phase 5 should run projections from the same preloaded inputs.)*
- [x] Membership roles: any member can rename the group, change its rainfall setting or delete farms. Decide on owner/member roles before group invitations (Phase 8 stretch). *(Q8 decided 2026-10-04: owner and member; shipped with the operation page.)*
- [x] Specs: a `PlantingCsv` unit spec (columns, totals, sources), `SeasonCopy` edge cases (leap day, overlap), and Vitest coverage for `weatherCharts.ts` and `dates.ts`.
- **Exit:** the bugs are fixed with tests, Playwright runs in CI, Phase 4 is live on staging, and every unassigned plan item has a phase.
