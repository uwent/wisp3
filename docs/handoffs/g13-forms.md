# Handoff: G.13, forms that explain themselves and don't lose edits

Written 2026-11-16 at the end of G.6, and updated at the end of the session that built part 1. Read PLAN.md's **G.13** first: its **Plan** paragraph is agreed with Ben (2026-11-16). Parts 1 and 2 are done (2026-11-16; PLAN.md G.13, *As built*), and part 3 below (2026-11-16, with G.7); this handoff is kept for the record. Ben reviews the wording in the app as it lands, before `bin/ci`.

## Where things stand

- **Branch:** `beta-readiness`, not pushed. The last commits: the CI split, the browser tests' stubs, G.13 part 1, and the map tidied again (PLAN.md G.14 *(c)*).
- **CI is two parts now:** `bin/ci` (lint, types, vitest, rspec; about 3.5 minutes) and `bin/e2e` (about 7 minutes), separate jobs on GitHub Actions. Run the browser tests the change touches while working (`bin/e2e e2e/smoke.spec.ts -g … --project desktop`), all of `bin/e2e` before committing a change to shared components (the field components are).
- **Browser tests import `test` and `expect` from `e2e/test.ts`**, which answers the soil survey and the USGS imagery tiles, so outages no longer fail them (the soil survey was still returning 502 on 2026-11-16; the browser shows that as a CORS error). The phone project runs only tests tagged `@phone`: give the info tip's axe scan the tag.
- **Settled with Ben:** the info tip wording is reviewed in the app as it lands, not as a list first.

## 1. Asking before dropping changes (done)

What was built is in PLAN.md (G.13, *As built*). For part 2:

- `lib/formChanges.ts` reads a control's label from `control.labels[0]` without its `.text-ink-muted` text, buttons and `[data-change-ignore]`. The (i) goes **outside** the `<label>` (as planned), so the prompt's wording isn't affected; if anything inside a label must be left out, mark it `data-change-ignore`.
- A radio group is named by its `role="radiogroup"`'s `aria-label`, else its fieldset's `<legend>`; the legend's words are read the same way.
- **Wording to settle with Ben:** the field dialog's area box is now labelled "Field area" (his choice), inside a fieldset whose legend is also "Field area" (`FieldForm`), so the phrase shows twice. The info tip work touches that legend's row; ask whether the legend should change (e.g. "Area and shape").

## 2. Info tips on labels

- **`lib/components/InfoTip.svelte`** exists (used by `lib/charts/ChartCard.svelte`): an (i) button with hover, click to pin, Escape, and blur. Its tooltip is `absolute` in its parent, so it's clipped inside a dialog, whose content scrolls (`overflow-y-auto`). Move it onto bits-ui's `Popover` with a portal, as `lib/components/Term.svelte` does (`openOnHover`, `Popover.Portal`, `role="tooltip"`, `aria-describedby` while open), and check `ChartCard` still works.
- **Fields:** `TextField`, `NumberField` and `SelectField` (`lib/components/`) each render their own `<label>`. Give them `info?: string` and one shared label row: the label at the left, the (i) at the far end, outside the `<label>` (a button inside a label would focus the input), named "About {label}".
  - The radio groups and dates are hand-written in `lib/setup/PlantingForm.svelte` (about 20 radio and fieldset uses) and `lib/setup/FieldForm.svelte`: use the same row there.
- **Wording:** in `lib/fieldInfo.ts`, functions where a value needs units (`units(user.unit_system)`). Sources: the About page (`pages/Pages/About.svelte`, `lib/docs/`), `lib/guidance.ts`, `lib/glossary.ts`, and the legacy user guide in `../wisp`. A vitest keeps each tip to two sentences or fewer and every key used.
- **Order:** Setup's forms (farm, pivot form, irrigation group, field, planting), then quick setup, then Settings and Alerts. Keep hints that must be read before typing under the box; tips for the rest.

## Tests

- **Vitests:** `fieldInfo` (each tip two sentences at most; every key used).
- **Axe** (`e2e/accessibility.spec.ts`): an open tip, in light and dark (tag `@phone`).
- **Keyboard** (`e2e/keyboard.spec.ts`): Tab reaches an (i), Enter opens it, Escape closes it. A tip inside a guarded dialog: Escape must close the tip, not ask about the dialog's changes (bits-ui's nested layers should handle it; check).

## 3. A first pass that isn't intimidating (done, with G.7)

Built 2026-11-16 after Ben reviewed the planting form with G.7's season length; PLAN.md G.13 *Part 3* has the list. For whoever builds on it:

- **Required and optional:** give a required control `required` and an optional one `optional`; `TextField`, `SelectField` and `NumberField` mark them (`FieldLabel`'s `missing` dot while empty, its "Optional"). Hand-written labels use `FieldLabel` with `missing`/`optional` directly. Both marks sit outside the `<label>` text, so tests still find inputs with `getByLabel(label, { exact: true })` and change lists read the plain label. Don't write "Optional." at the start of a hint any more.
- **Defaults as placeholders:** `NumberField`'s `blankValue` (stored units) shows a default in a blank box and in change lists (`data-blank`); add `submitBlankValue` when the column needs a value (root zone, MAD), leave it off when blank means NULL and follow the default (season length, field capacity).
- **The planting form** (`lib/setup/PlantingForm.svelte`) shows its sections only once a crop is chosen (`{#if !plant}`), so a test of a new planting picks the crop first; the canopy and water settings are inside a `<details>` ("Settings"), so a test opens it (`dialog.locator('summary').click()`) before using them. Inputs in the closed `<details>` are still submitted and tracked.
- **Dates:** `dateProblems` and `canReplace` (`lib/plantings.ts`) mirror `Planting#dates_in_order` and `PlantingsController#replace_overlapping`: harvest after the season start and emergence (emergence may be on or before the start). Change them together.
- **Setup's timeline bars** open a bits-ui menu (View this planting, Edit planting) anchored where the bar was clicked (`customAnchor` in `SeasonTimeline`); menus share their classes through `lib/components/menu.ts`. `/setup?planting=ID` opens that planting's form; the dialog's link out asks first through `Dialog#changes` and `changesMessage` (`lib/unsaved.svelte.ts`).
- **Left for later:** Ben may want the same sections on other long forms (the field dialog, the system page); nothing else is open.
