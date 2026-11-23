# Phase 1: Foundation

*A record of the build, frozen when it was folded out of `PLAN.md` on 2026-11-22: it says what was planned and done at the time, and later work may have changed or replaced it. For how the app works now, see [docs/architecture.md](../architecture.md) and [docs/engine.md](../engine.md); for why, [docs/decisions.md](../decisions.md). Section numbers (§) refer to the original design ([design.md](design.md)), except §2 and §15, now [docs/decisions.md](../decisions.md), and §9, now [docs/legacy-audit.md](../legacy-audit.md).*

- [x] `rails new` (Rails 8.1, Postgres, no Hotwire/importmap/asset pipeline) in `wisp3`; git; public GitHub repo `uwent/wisp3`; CI (`bin/ci`, run by GitHub Actions).
- [x] `vite_rails`, `inertia_rails` (Inertia v3), Svelte 5 + TS, Tailwind v4 (`@tailwindcss/vite`), `bits-ui`, Alba + Typelizer (types and route helpers).
- [x] App shell: layout, navigation, user menu, group switcher, status color tokens, light/dark (follows system), responsive at phone widths.
- [x] Devise + Inertia auth pages (sign up, sign in, confirmation, password reset, settings with email/password change and account deletion), **sign-in links and codes**, rate limits (Rails `rate_limit` + Rack::Attack).
- [x] Group / membership / `Current.group` tenancy, with cross-tenant request specs.
- [x] Capistrano config, systemd user units, nginx example, staging credentials; first-time setup steps in `docs/deployment.md`.
- [x] First deploy to staging (2026-10-03): Puma answers on 127.0.0.1:3100 and both services are enabled. nginx serves it at https://dev.wisp.cals.wisc.edu.
- [x] Send the §12 server requirements to the sysadmin so the new production box is ready by February. *(Production went to AWS instead: EC2, RDS, ECR and SSM, ready October 2026; deployed with Docker, `bin/production`.)*
- **Exit:** a user can sign up, confirm, sign in by password or link, and see an empty dashboard on staging. *(Verified locally in a headless browser, desktop and phone/dark; staging live 2026-10-03; sign-up and the confirmation email checked on staging.)*
