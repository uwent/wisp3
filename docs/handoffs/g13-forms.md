# Handoff: G.13, forms that explain themselves and don't lose edits

Written 2026-11-16, at the end of G.6. Read PLAN.md's **G.13** first: its **Plan** paragraph is agreed with Ben (2026-11-16), and this note adds where the code is and what to watch. Make it two commits on `beta-readiness`, the change prompt first, then the info tips. Ben checks each in the app before `bin/ci`.

## Where things stand

- **Branch:** `beta-readiness`, not pushed. G.6 is done (its follow-ups and the weather page's location addresses are in the same commit), and G.14 before it.
- **Outside services were down on 2026-11-16:** the USDA soil survey (`sdmdataaccess.sc.egov.usda.gov`, 502, so the browser reports a CORS error) and the National Map basemap (404). While they're down, `bin/ci`'s browser tests fail on every page that loads the survey (the shape page, a system's edit page, Setup's field dialog, outline import) and on the four field shape smoke tests, the same on the commit before G.6. Check them before reading a failure as yours: `curl -s -o /dev/null -w "%{http_code}" -X OPTIONS https://sdmdataaccess.sc.egov.usda.gov/Tabular/post.rest`.
- **Settled with Ben:**
  - Dialogs get an in-dialog prompt: **Save changes / Discard / Keep editing**, with the list of changes.
  - Pages keep `window.confirm`, now listing the changes; no in-app prompt for links (it would need save-then-follow).
  - The info tip wording is reviewed by Ben in the app as it lands, not as a list first.

## 1. Asking before dropping changes

- **What asks today:** `lib/unsaved.svelte.ts` (`confirmUnsavedChanges(isDirty)`, `UNSAVED_MESSAGE`). Its callers:
  - `pages/Pivots/Form.svelte`, `pages/Setup/Start.svelte`, `pages/Fields/Outline.svelte`, `pages/Setup/ImportOutlines.svelte`;
  - `pages/DailyEntries/Show.svelte`, which also calls `confirm(UNSAVED_MESSAGE)` itself before changing date;
  - `lib/setup/FieldForm.svelte` (`edited`), which asks before its "Edit shape" link leaves Setup.
- **`lib/formChanges.ts`** (new, vitest under jsdom: run vitest from the repo root, or `getComputedStyle` is missing):
  - `snapshot(form)` reads the visible, labelled controls; `changes(form, snapshot)` returns `{label, from, to}` and a `describe` that words "Area: 40 ac → 30 ac".
  - **Labels:** `control.labels[0]`, then a radio group's `<legend>`, then `aria-label`. Leave out the label's hint and error text (`NumberField`/`SelectField` put them in sibling `<p>`s, not in the label, so `labels[0].textContent` is clean).
  - **Values:** a select's selected option text; Yes/No for a checkbox; for a date input, `formatDate`; blank as "None"; a textarea as "Notes: changed".
  - **Units:** `NumberField` (`lib/components/NumberField.svelte`) shows the unit in a sibling span (`suffix`), so add `data-unit={suffix}` on its visible input. Its hidden stored-unit input carries `name`, and the visible one may have none, so key controls by `id`, not `name`.
  - Skip `type="hidden"` and `disabled` controls, and anything inside `[hidden]`.
  - Cut long lists to about 6 lines, then "and N more" (daily entry and quick setup have many rows).
- **`lib/components/Dialog.svelte`** (bits-ui `Dialog`): add an opt-in `guard`.
  - bits-ui's `Dialog.Content` takes `onEscapeKeydown` and `onInteractOutside` (call `preventDefault()` to stay open); the ✕ is a `Dialog.Close`, so make it a plain button that runs the same check. Check the props in `node_modules/bits-ui` rather than guessing.
  - Snapshot the first `<form>` inside the content when it opens (after `tick()`). With changes, hide the form (keep it mounted, so its values survive) and show the prompt in its place, focus on its heading or Keep editing.
  - **Save changes:** `form.requestSubmit()`. On a refusal the form comes back with its errors (show it again); on success the page's own code closes the dialog by setting `open`, which doesn't go through the guard.
  - **Keep editing:** show the form, focus the first changed control.
  - **Re-snapshot:** `PlantingDialog` (`lib/setup/PlantingDialog.svelte`) rebuilds its form in a `{#key key}` for "Add the next planting", so it needs to snapshot again; expose a `resnapshot` (or snapshot whenever the form element changes, with a MutationObserver).
- **Dialogs that get it:** `pages/Setup/Show.svelte`'s one `Dialog`, which holds the farm, field (`FieldForm`) and irrigation group forms by `dialog.kind`, and `PlantingDialog`. The delete dialogs in `pages/Groups/Show.svelte` and `pages/Admin/Users/*` have no inputs: leave them unguarded.
- **Pages:** `confirmUnsavedChanges` takes an optional form getter and adds the list to its `confirm()` text. Closing or reloading the tab keeps `beforeunload` (its text can't be changed).
- **Interplay to check:**
  - `FieldForm`'s "Edit shape" link already asks through `confirmUnsavedChanges`; keep one prompt, not two.
  - `PivotMap` now starts locked on a saved system (G.6, `locked` on `PivotMap`/`PivotShapeFields`): Cancel there restores the shape, which should leave the pivot form unchanged.

## 2. Info tips on labels

- **`lib/components/InfoTip.svelte`** exists (used by `lib/charts/ChartCard.svelte`): an (i) button with hover, click to pin, Escape, and blur. Its tooltip is `absolute` in its parent, so it's clipped inside a dialog, whose content scrolls (`overflow-y-auto`). Move it onto bits-ui's `Popover` with a portal, as `lib/components/Term.svelte` does (`openOnHover`, `Popover.Portal`, `role="tooltip"`, `aria-describedby` while open), and check `ChartCard` still works.
- **Fields:** `TextField`, `NumberField` and `SelectField` (`lib/components/`) each render their own `<label>`. Give them `info?: string` and one shared label row: the label at the left, the (i) at the far end, outside the `<label>` (a button inside a label would focus the input), named "About {label}".
  - The radio groups and dates are hand-written in `lib/setup/PlantingForm.svelte` (about 20 radio and fieldset uses) and `lib/setup/FieldForm.svelte`: use the same row there.
- **Wording:** in `lib/fieldInfo.ts`, functions where a value needs units (`units(user.unit_system)`). Sources: the About page (`pages/Pages/About.svelte`, `lib/docs/`), `lib/guidance.ts`, `lib/glossary.ts`, and the legacy user guide in `../wisp`. A vitest keeps each tip to two sentences or fewer and every key used.
- **Order:** Setup's forms (farm, pivot form, irrigation group, field, planting), then quick setup, then Settings and Alerts. Keep hints that must be read before typing under the box; tips for the rest.

## Tests

- **Vitests:** `formChanges` (labels, units, selects, radios, dates, blank, the cut list), a `Dialog` component test (Escape with and without changes, each button), `fieldInfo`.
- **Smoke** (`e2e/smoke.spec.ts`): edit a field's area in Setup, press Escape, see "Area: … → …", Discard; again with Keep editing, the value kept. Playwright dismisses `window.confirm` by default, so a page test that leaves a changed form needs `page.once('dialog', …)`.
- **Axe** (`e2e/accessibility.spec.ts`): the prompt open in a dialog, and an open tip, in light and dark.
- **Keyboard** (`e2e/keyboard.spec.ts`): Tab reaches an (i), Enter opens it, Escape closes it; focus moves into the prompt and back to the control.
