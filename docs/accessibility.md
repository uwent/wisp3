# Accessibility

WISP 3 aims at WCAG 2.1 AA (PLAN.md, Phase 8 A). This file records the audit: what was checked, what was found, and how it was fixed.

## Automated checks

`e2e/accessibility.spec.ts` runs axe (`@axe-core/playwright`, WCAG 2.1 A and AA rules) on every page, signed out and signed in, in light (the desktop project) and dark (the phone project). It runs with the rest of `bin/e2e`, in CI too, and fails on any violation. `A11Y_REPORT=path.json bin/e2e accessibility.spec.ts` writes what it finds as JSON, one file per project.

Axe finds roughly a third of WCAG problems; the manual checks below cover the rest.

### First run (2026-10-22): found and fixed

| WCAG | Rule | Where | Fix |
|---|---|---|---|
| 2.5.3 Label in name | `label-content-name-mismatch` | Every grid cell (`EditableCell`): its name was "Rain, Thu, Oct 22" without the value it shows | The label is a visually hidden prefix of the button's content, so the name is "Rain, Thu, Oct 22: 0.45" |
| 2.5.3 | same | The operation switcher and account menu buttons, named "Switch farm operation" and "Account menu" while showing the operation's and user's names | Names lead with what they show: "Demo farms, switch farm operation" |
| 2.5.3 | same | Field cards' "Open field →", named "Open Cabbage" | "Open field: Cabbage" |
| 1.4.1 Use of color | `link-in-text-block` | Links inside sentences, underlined only on hover (field page, pivot page, empty states); MapLibre's attribution links | Underlined always; standalone links (← Setup) are left as they are |
| 1.4.3 Contrast | `color-contrast` | The irrigate red as text in dark mode (3.1:1); the caution badge's text, which turned light in dark mode; white on the OK green (4.0:1); the caution amber as text in light mode (2.2:1) | Text tokens `status-irrigate-ink` and `status-caution-ink`, lighter in dark mode; `on-caution` for text on the caution fill in both modes; the OK green darkened from 58% to 53% lightness (white on it 4.9:1) |
| 2.1.1 Keyboard | `scrollable-region-focusable` | The About page's equations (`pre`) and the admin weather table, which scroll sideways with nothing focusable inside | Focusable (`tabindex="0"`) with a name |
| 1.3.1 Info and relationships | (found by the scan's setup) | Sign-in, sign-up and the other account pages had no `main` landmark | `AuthLayout` wraps them in `main` |

Status colors as fills keep their values apart from the OK green; the chart palette (`--color-chart-*`) is separate and unchanged.

## Manual checks

To do, in this order (PLAN.md Phase 8 A). Record each finding here with the page, the WCAG criterion and the fix.

- [ ] Keyboard: every page by Tab alone (visible focus, sensible order, no traps), the grids, menus, the map's popups and phone sheets, the side list, the overlay panel, a skip link.
- [ ] Pivot picker: the typed fields cover everything the handles do.
- [ ] Charts: a table alternative and a text summary for each.
- [ ] Not by color alone: status, provenance, forecast shading, soil types.
- [ ] Screen readers: NVDA or Orca on desktop, VoiceOver on a phone.
- [ ] Reflow at 320 px and 200% text; `prefers-reduced-motion`.
- [ ] Emails.
- [ ] Accessibility statement on the About page.
