# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

WISP 3: a rewrite of the Wisconsin Irrigation Scheduling Program (legacy app in `../wisp`). The design, decisions (D1–D11) and phases are in `PLAN.md`; check it before starting a phase, and update its checklists as work lands.

## Commands

```bash
bin/dev                          # Rails :3000 + Vite dev server
bin/ci                           # full CI: standardrb, svelte-check/tsc, typelizer freshness, vitest, rspec
bundle exec rspec spec/path_spec.rb
npm test                         # vitest
npm run check                    # svelte-check + tsc
bin/rails typelizer:generate     # after changing serializers or routes; commit the output
```

## Architecture

- Rails controllers render Svelte pages with Inertia: `render inertia: "Folder/Page", props: {...}` maps to `app/frontend/pages/Folder/Page.svelte`. Pages under `Auth/` use `AuthLayout`; everything else uses `AppLayout` (`app/frontend/entrypoints/inertia.ts`).
- Shared props (`auth.user`, `auth.group`, `auth.groups`) come from `InertiaController`; `page.flash` carries `notice` and `alert`.
- Page props are built with Alba serializers in `app/serializers`; Typelizer generates their TypeScript types (`@/types/serializers`) and typed route helpers (`@/routes`, returning `{url, method}` for `<Form action>` and `<Link href>`).
- Forms: use Inertia's `<Form>` component with Rails-style input names (`user[email]`). On validation failure, controllers redirect back with `redirect_with_errors(path, record)`.
- Devise controllers live in `app/controllers/users/` and render Inertia pages through `InertiaDeviseResponses`. Passwordless sign-in (`MagicLinksController`) emails a one-time link (`User.generates_token_for(:magic_login)`) and a six-digit code (`User#generate_sign_in_code!`). Wrap links in emails with `email_link_to` (adds `ses:no-track`).

## Rules

- **Tenancy:** every signed-in controller inherits `AuthenticatedController`. Load group-owned records only through `Current.group` (e.g. `Current.group.farms.find(params[:id])`), never `Model.find(params[:id])`. The legacy app's worst bug was unscoped lookups. Add a cross-tenant request spec for every new controller.
- **Units:** store water depths in inches. Unit conversion (Q3: `users.unit_system`) happens only at the display and input edge in the frontend.
- **Missing data is NULL, never 0.** A value the user entered as zero is 0.0.
- **Legacy code:** when porting from `../wisp`, check each method against the audit in `PLAN.md` §9 before reusing it.
- Ruby style is Standard; prefer small, plain-Ruby service objects for domain math (no ActiveRecord callbacks cascading recalculation).
