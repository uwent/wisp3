# Handoff: G.14 Setup and the map, tidied after G.10

Written 2026-11-12, at the end of G.10. Read PLAN.md's **G.14** first: it is the agreed work list (Ben, 2026-11-12, after trying G.10), and its questions are settled (below). This note covers where things stand, where the code is, and what to watch.

## Where things stand

- **Branch:** `beta-readiness`. G.1–G.5 and G.9–G.12 are done. G.10 landed in six commits (`fdc5b53` … `ddeeed7`); nothing is pushed.
- **Checks:** `bin/ci` passes, including the browser suite (95 passed, 1 skipped as before).
- **After G.14:** G.6 wording (its Delete item moved here), G.13 forms, G.7 crops, G.8 operations and the example farm.

## Settled with Ben (2026-11-12)

1. **Location** is a triangle on the map.
2. **The map's panel stays** on wide screens.
3. **Selecting a farm or irrigation group** only zooms the map to its systems: no panel, no other highlight.
4. **Pivots and linears keep a minimum size** zoomed out (about 16 px across), drawn as their kind's glyph below that, rather than shrinking to specks at their true size.

## Part 1: one polygon per field

- **Server:** `app/services/field_boundary.rb`. `normalize` and `errors` accept `Polygon` only. Make `polygons` the one ring, or remove it, and keep the error wording mirrored in `boundaryErrors` (`lib/geo.ts`).
- **Browser:** in `lib/geo.ts`, the `Boundary` type is used everywhere outlines are. The callers of `boundaryPolygons` and `boundaryOf` are:
  - `lib/outlines/OutlineMap.svelte` (parts, `hasHoles`, the `outline` source);
  - `read.ts`;
  - `problems.ts`;
  - `references.ts`;
  - `lib/map/pivots.ts`;
  - `lib/soils.ts` (`areaWkt`);
  - `Fields/Outline.svelte` (`fixed`, the part buttons).
- **Import:** `shapesFrom` in `read.ts` is where to drop holes and keep the largest part, before `simplifyBoundary`. Add a note to `ImportedShape` for the row to show.
- **Migration:** reduce stored outlines to their largest part's outer ring, in plain SQL or Ruby over `fields.boundary`. `DemoSeed`'s generated outlines are already single rings.

## Part 2: Setup

- **Rows** (`pages/Setup/Show.svelte`): the snippets are `fieldRow` and `pivotCard`. The farm header buttons are around the "Group systems" button, and the irrigation group header is inside `{#each farm.pivot_groups}`. `destroy()` there does the confirmation, and Delete is owner-only (`owner`).
- **Dialogs** (in the same file):
  - the farm and irrigation group forms are inline in the `<Dialog>` at the bottom;
  - the field form is `lib/setup/FieldForm.svelte`;
  - the planting dialog's Delete (`lib/setup/PlantingDialog.svelte`) is the existing pattern to match.
- **The pivot's edit page:** `pages/Pivots/Form.svelte`. Add Delete there, then redirect to Setup.
- **Outline links to remove:** the field row's "Add outline"/"Outline" link (its `aria-label` was made to match its text for axe). The field header's link (`FieldHeader.svelte`) can stay.
- **Shape thumbnail:** a new `ShapeThumbnail.svelte`. It projects the ring to the SVG `viewBox`, with x scaled by cos(latitude), and draws a path in the system color.
- **Field acres:** `field.boundary_acres` is already serialized. The outline page offers it, so the dialog doesn't need to.
- **Quick setup:** the "Set up an irrigation system" link at the top goes. The empty states still link to quick setup: Setup's "No farms yet", and the dashboard's.

## Part 3: the map's drawing (`lib/map/OverviewMap.svelte`, `pivots.ts`, `PivotMarker.svelte`)

- **The field click bug:** `onClick` takes `queryRenderedFeatures(...)[0]`, which is the top-most feature whatever order the `layers` option lists. The systems' `pivots-fill` is above `fields-fill` and is still hit at opacity 0. Query each layer in priority order instead. The same function decides whether `mapOverlays` probes a click (it skips clicks on our layers).
- **Colors:**
  - `statusColor()` paints `pivots-fill`, `pivots-line` and `pivots-point`; switch those to the system color.
  - Fields and pins keep the status colors.
  - Tokens that JavaScript reads must sit in the `@theme static` block in `application.css` and be read through `readPalette()` (MapLibre can't parse `oklch`).
  - Validate the new color for color blindness, light and dark, as the chart tokens were.
- **Point kinds** are `pivots-point`, a circle layer sized in pixels. That's why a traveler doesn't keep its size on the ground.
  - The recommended way: a symbol layer with SDF icons drawn on a canvas (`map.addImage(id, imageData, { sdf: true })`). Give it `icon-size` as `['interpolate', ['exponential', 2], ['zoom'], …]` to match 50 ft at the system's latitude, with a pixel minimum. `isOwnSource` already carries the source over a basemap switch, but images aren't carried: re-add them after `setBasemap`.
  - Keep `POINT_LAYER` exported; `mapOverlays` uses it.
- **Minimum size for pivots and linears:** they're polygons in `pivots-fill`/`pivots-line`, so they shrink with the map. Two ways to swap in the glyph below the zoom where one is under ~16 px:
  - Compute that zoom per system from its size and latitude (meters per pixel = 156543.03 × cos(lat) / 2^zoom). Give each feature a `minZoom` property, and filter the polygon layers with `['>=', ['zoom'], ['get', 'minZoom']]` and the glyph layer with `<`. Zoom expressions in filters must be top-level comparisons; check MapLibre accepts this, or else split the features into two sources by zoom band.
  - Or draw every system as a glyph symbol sized `max(true size, minimum)` with an exponential zoom interpolation, and the polygon only from the zoom it's larger. Either way the click query in `onClick` must include the glyph layer.
- **Badge cluster:** `PivotMarker`'s badge span is a wrapping flex row (`max-w-36 flex-wrap`). Lay out rows of ⌈√n⌉, centered. Zoomed out (`data-far`) it's one status dot; keep that.

## Part 4: the map's list (`pages/Map/Show.svelte`, `lib/overview.ts`, `FieldCard.svelte`, `PivotPanel.svelte`)

- **Today's list:** `items: ListItem[]` is a flat list of field cards, filtered by `matches` and the window, then sorted by `sortItems(prefs.sort)`.
- **Today's selection:**
  - `selectedPivotId` and `selectedFieldId`, with `isSelected`;
  - `selectPivot(pivotId, fieldId)` is the map's callback;
  - `selectField` is the list's;
  - `focusPanel` and `opener` handle keyboard focus.

  Replace them with one `selection: { level: 'farm' | 'group' | 'system' | 'field'; id } | null`.
- **The tree:** build it in `lib/overview.ts` (farms › `pivot_groups` › pivots › field cards; systems not in a group sit directly under the farm, as on Setup). Sort and filter it there, with vitests replacing `sortItems`'.
- **FieldCard:** with `onselect`, the whole card is a select button and "Open field →" is a separate link. Rename that link to **View**. In the panel it's used without `onselect` (`compact`), so it renders as a link: pass `onselect` there too.
- **Selected state on the map:**
  - `OverviewMap` takes `selectedId` (system) and `selectedFieldId`;
  - a farm or group selection needs a highlight, which can be the irrigation group outline layer (`groups-*`) for a group, and a fit (`fit(pivots)`) for either.
- **Tests:** the smoke test "the map shades outlined fields…" and "the map lists the fields and selects a pivot from the list" will need updating, and so will the keyboard test for the layers panel if the list's structure changes focus order.

## Gotchas found in G.10

- **Indexed names for lists in forms:** Inertia's `<Form>` sends JSON, and `rows[][name]` arrives as `{"" => …}`. Use `rows[0][name]`, and read it with `indexed_list` (`InertiaController`).
- **terra-draw takes the map's pointer events:** MapLibre's `click` doesn't fire on the outline page; it uses a capture listener on the canvas container. Its `change` events fire for features loaded from code, which is why there's a `loading` flag. See CLAUDE.md.
- **The e2e smoke tests share one seeded database and run in file order.** The G.10 import test leaves Market garden with an outline near Arlington, and its "Outlines to check" assertion relies on that. If a test needs a clean field, remove the outline first, as the drawing test does.
- **Playwright matches role names by substring:** "Move its pin" also matched "Remove its pin". Use `exact: true`.
- **Clicking a button lower on the page can scroll the map off screen**, which is why "Place its pin" calls `map.show()`. Keep that in mind for selection from the list.
- **Don't run Prettier on PLAN.md:** it reformats every table; lint-staged leaves Markdown alone.
