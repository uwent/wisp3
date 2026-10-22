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

In this order (PLAN.md Phase 8 A). Each finding is recorded with the page, the WCAG criterion and the fix.

### Keyboard (2026-10-22)

Every signed-in page, the landing page, About and sign-in were tabbed through in a script that recorded each stop (its element, name, focus style and whether it was hidden). No traps, no focus on hidden elements, and a focus style on every stop. `e2e/keyboard.spec.ts` keeps the fixes below working.

| WCAG | Where | Found | Fix |
|---|---|---|---|
| 2.4.1 Bypass blocks | Every signed-in page | 13 stops (branding, theme, nav, menus) before the page's content | A "Skip to main content" link, the first stop, shown when focused |
| 2.1.1 Keyboard, 2.4.3 Focus order | Field page, field groups | Every grid cell was a tab stop: about 1,000 on a field page, between the summary and everything below the grid | A grid is one tab stop (roving tabindex): the cell last focused, else the first; arrow keys move inside it and Tab moves past. Tab while editing still saves and moves along the row. The grid notes say how |
| 2.1.1 | Account menu (desktop) | The arrow keys stopped on the operation switcher's items, which are hidden on wider screens, so Settings and Sign out couldn't be reached | Those items are left out of the menu on wider screens rather than hidden with CSS |
| 2.4.3 Focus order | Map | Selecting a pivot from the list or its marker opened its panel, but focus stayed behind, far from the panel in the tab order; closing it lost focus | From the keyboard, focus moves to the panel, and Escape or Close returns it to the card or marker that opened it. Pointer users stay where they are |
| 2.1.1, 4.1.2 | Map layers panel | Marked as a dialog without behaving like one; Escape didn't close it | A group that follows its button in the tab order; Escape and × close it and return focus to the button |
| 2.4.6 Headings and labels | Setup | "Edit", "Delete", "Add field", "Irrigation" and "+ Crop" repeated for every farm, pivot and field with nothing to say which | Names say what they act on ("Edit North 160", "Delete Cabbage"), starting with the visible text |
| 2.4.6, 1.3.1 | Daily entry | Each pivot's "Irrigation" and "Run hours" inputs had the same names | Each pivot's block is a group named by its heading |
| 2.1.1 | Pivot picker | The handles need a pointer | Already covered: latitude, longitude, radius, arc ends, length, travel and direction are all typed fields. The picker's prompt and the map's name now say so |

Checked and fine: dialogs (bits-ui: focus moves in, is held, Escape closes and returns it), the glossary's `Term` popovers (Enter or Space opens, Escape closes, focus stays on the term), menus once fixed, and the map's markers, controls and side list.

- [x] Keyboard: every page by Tab alone (visible focus, sensible order, no traps), the grids, menus, the map's popups and phone sheets, the side list, the overlay panel, a skip link.
- [x] Pivot picker: the typed fields cover everything the handles do.
- [ ] Charts: a table alternative and a text summary for each.
- [ ] Not by color alone: status, provenance, forecast shading, soil types.
- [ ] Screen readers: NVDA or Orca on desktop, VoiceOver on a phone. Known already: a `Term`'s definition has no role and isn't tied to the term (`aria-describedby`), so a screen reader announces "expanded" but not the definition.
- [ ] Reflow at 320 px and 200% text; `prefers-reduced-motion`.
- [ ] Emails.
- [ ] Accessibility statement on the About page.
