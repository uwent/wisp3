# Handoff: G.14 part 7(b), a field away from its irrigation system

Written 2026-11-12, at the end of part 7(a). Read PLAN.md's **G.14 part 7** first. Its (b) items are agreed with Ben (2026-11-12) and this note adds where the code is and what to watch. Make it its own commits on `beta-readiness`, in this order: planting-held systems first (the menu needs them), then the warning and menu, then the arrow.

## Where things stand

- **Branch:** `beta-readiness`. Part 7(a) (the shape editor, the shared area and soil inputs, basemap switching) is committed with the outlines → shapes wording. Nothing is pushed.
- **Settled with Ben:**
  - Fields stay the land: not season-scoped, and not copied forward each year.
  - Nothing limits how far a shape may move. The "doesn't touch" warning is the guard.
  - "Unlink" means moving the field to another system: `fields.pivot_id` is required.
  - Saving is still allowed with the field kept on a system it doesn't touch.

## 1. Plantings hold their system

This lifts G.9's last lock. Today `Field#pivot_kept_with_history` (`app/models/field.rb`) refuses a pivot change for a field with ended plantings, because system irrigation is matched by the field's *current* pivot.

- **Column:** add `plantings.pivot_id` (not null, FK, indexed), filled by a migration from each planting's field.
  - Copy it in `Planting#copy_from_field` with `weather_cell_id`.
  - `Field#update_open_plantings` already moves `weather_cell_id` for open plantings when `saved_change_to_pivot_id?`; move `pivot_id` there too.
- **Matching:** `PivotIrrigation#applies_to?(field)` becomes a question about a planting.
  - It applies when the planting's `pivot_id` is the irrigation's, and the field is in `field_ids` (or that's nil).
  - Callers:
    - `DailyInputs#days` (via `Records.pivot_irrigations`);
    - `DailyInputs.preload`, which groups irrigations by `field.pivot_id`: group by the plantings' `pivot_id` instead;
    - `PlantingsController` around line 115.
- **Grouping by system:** `irrigated_fields` and `irrigated_acres` (run hours over the acres in season) should take the plantings in season that day with that `pivot_id`, not `pivot.fields`.
- **"Applied to" lists:** `field_ids` can name a field that has since moved to another system. `PivotIrrigation#fields_under_pivot` (the "must be fields on this pivot" validation) would then refuse to save an edit to that old irrigation, so accept fields that had a planting on the system on the irrigation's date.
  - The "Applied to" checkboxes (daily entry, `PivotIrrigationsController`) list the system's fields today. For a past date, list the fields whose plantings were on it then.
- **What goes:** `pivot_kept_with_history` and its spec, and the field form's locked system menu and its hint ("The 2026 season stays with North 160…", `lib/setup/FieldForm.svelte`, `endedYears`). The "Seasons that have ended keep…" note can say the system too.
- **Engine:** `spec/services/legacy_engine_spec.rb` must keep passing; it reads inputs only, so it should. If any balance changes, give it a fix ID in PLAN.md §9.
- **Pages that preload** (`FieldStatuses.for`, `DailyEntryPage`, the digest) go through `DailyInputs.preload`, so check their query counts in their specs.

## 2. The warning and the transfer menu (the shape page)

- **Detecting it:** use `outlineProblems` in `lib/outlines/problems.ts`, which already words Setup's list. It covers a pivot or linear shape that doesn't overlap the field, and a point kind more than a quarter mile away. For the menu you also need **which systems the shape touches**: `overlaps` (shape kinds) and `distanceToBoundaryM` (point kinds) are there, so export them or add `systemsTouching(boundary, systems)`.
- **Props:** `FieldOutlinesController#show` already sends `pivot` and `other_pivots` with their shapes (`PivotSerializer::SHAPE`); `other_pivots` needs `kind_name` and `weather_cell_id`, to say when a move changes the weather.
- **Wording:** "This field doesn't touch its irrigation system, Lane 3. All fields must have an irrigation system." The menu is labeled with `systemName` ("North 160 (pivot)"):
  - **Keep with Lane 3** (the default);
  - each other system the shape touches;
  - **Location only**, with "You can change its kind and details later in Setup."
- **Where it goes:** under the map, above the Area and Soil cards, shown only while the shape is away from its system, and only when the map isn't drawing or editing. It's sent with the form:
  - `outline[pivot_id]` for an existing system;
  - `outline[new_location]=1` for Location only.
- **Saving** (`FieldOutlinesController#update`), in one transaction:
  - an existing system: look it up through `Current.group.pivots` (never `Pivot.find`), and add a cross-tenant spec;
  - Location only: create a `point` system on the field's farm at `boundaryCenter` (sent from the browser, or computed in Ruby from `FieldBoundary`), named after the field.
  - Moving the field updates its open plantings' system and weather cell (part 1). When the weather cell changes, the page says so before saving ("Its 2027 season will use this location's weather").
- **Setup's problem list** comes from the same function, so it clears once the field moves.

## 3. The arrow back to the system

- In `OutlineMap.svelte`, while the shape doesn't touch its system and the map isn't drawing: draw a dashed line from the shape's nearest edge point to the system's nearest point (its location, for a point kind), with an arrowhead and the label "Lane 3 · 0.4 mi" (`formatReach`).
- **Nearest points:** `segmentDistanceM` in `problems.ts` finds the distance, not the point; add a version that returns the point. For a pivot or linear, use the nearest point of `pivotOutline`.
- **Drawing it:** add a GeoJSON source (`shape-arrow`) to `OWN_SOURCES` so it survives basemap switches. The arrowhead can be a symbol layer with `symbol-placement: line-center` and a "▶" text, or a small SDF icon as in `lib/map/glyphs.ts`. Color it the system color on its casing (`references.ts` has both).
- Update it from the same `$effect` that feeds `shape-edge`.

## Tests

- **Specs:** a planting keeps its system after its field moves; system irrigation on an ended season still applies; run hours over the right acres; a field with history moves freely; the outline update moves to another system or makes a Location, cross-tenant refused.
- **Vitests:** `systemsTouching` and the nearest-point helper.
- **Smoke:** move a field's shape away, see the warning and arrow, choose Location only, save, and see Setup.
