# Phase 6.5: Landing page and documentation

*A record of the build, frozen when it was folded out of `PLAN.md` on 2026-11-22: it says what was planned and done at the time, and later work may have changed or replaced it. For how the app works now, see [docs/architecture.md](../architecture.md) and [docs/engine.md](../engine.md); for why, [docs/decisions.md](../decisions.md). Section numbers (§) refer to the original design ([design.md](design.md)), except §2 and §15, now [docs/decisions.md](../decisions.md), and §9, now [docs/legacy-audit.md](../legacy-audit.md).*

Decided 2026-10-05 (Ben): replace the legacy PDF user guide with documentation in the app, and greet signed-out visitors with what WISP is instead of a sign-in form. Brought forward from Phase 8.

- [x] **Landing page** at `/` for signed-out visitors (signed in, `/` stays the dashboard): what WISP is and who it's for, how it works in a few steps (weather → water balance → when and how much to irrigate), what you enter, and sign-up / sign-in buttons. Its text is the introduction of the About page, shared rather than copied. *(`PagesController`, `Pages/Home`; `lib/docs/Introduction.svelte`.)*
- [x] **About page** (`/about`, public, in the nav after Setup; signed out, the nav shows only About with sign-in and sign-up buttons). Sections, each with an anchor:
  - Introduction (shared with the landing page).
  - How WISP works: the water balance (§5) in plain words; weather from Open-Meteo, the forecast and its scenarios; statuses and "Irrigate by".
  - Getting started: account, operations and members, farms → pivots → fields → plantings, quick setup, copying last season.
  - Day to day: dashboard, daily entry, field groups, the field page (grid, planned irrigation, chart, weather), the daily email (Alerts).
  - Ground-truthing: which readings matter and how often (`lib/guidance.ts`): soil moisture weekly, sensor depths, percent cover or LAI, rain gauges.
  - Crops: a table from the `plants` table: default root zone depth, canopy methods (percent cover; LAI with the growth curve or with readings only), suggested sensor depths, with the shared defaults (MAD 50%, season dates) noted.
  - Glossary: every entry in `lib/glossary.ts`, each with an anchor the tooltips can link to.
  - Credits and contact: UW-Madison Vegetable Entomology Lab, agweather@cals.wisc.edu.
  *(`Pages/About`; the crop table from `plants`, reading advice from `lib/guidance.ts`, glossary from `lib/glossary.ts`, so they follow the app.)*
- [~] Wording reviewed by Ben (agronomy, contact details). *(Folded into one wording review before the beta: Phase 8 D. Claude's review after G.6 and G.11 is done, 2026-11-12.)*
- **Later (Phase 8):** screenshots, a printable version, the methods detail (equations from §5) for agronomists, and a "More in the guide" link from each glossary tooltip.
