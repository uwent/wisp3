# Handoff: G.10 field boundaries and import

Written 2026-11-11, at the end of G.5. Read PLAN.md's **G.10 Field boundaries (optional)** first: it holds the agreed design. This note covers where things stand, what the code already has, and what to settle with Ben before building. CLAUDE.md's rule applies: **propose a plan and wait for Ben's go-ahead before implementing.**

## Where things stand

- **Branch:** `beta-readiness`. G.1–G.5, G.9 and G.11 are done and committed there. Small leftovers stay open in their sections: G.2's Wisconsin timings, G.3's onion curve and About wording, and G.11's map pins, which come with G.10. **G.12, the weather page, hasn't been started**, although the build order put it before G.2; ask Ben whether it comes before or after G.10. Every check passes:
  - `bin/ci`: rspec 634, vitest 207, svelte-check, standardrb and eslint, typelizer freshness;
  - `bin/e2e`: 83 passed, 1 skipped.
- **Build order after G.10:** G.6 wording, G.13 forms, G.7 crops, G.8 operations and the example farm.
- **Pre-beta item added with this handoff** (Phase 8 D): review every demo farm, system and field so it sits on a real pivot or field in the imagery. Once G.10 lands, the demo fields need outlines that match the imagery too, so plan the seed's boundaries with that review in mind (or leave them for it).

## What G.5 changed that G.10 builds on

- **Any kind of irrigation system.** A `Pivot` in code is any irrigation system:
  - center pivot and linear move have a shape;
  - traveler, solid set, drip and "Location" are a point with no dimensions (`Pivot::POINT_KINDS`, `isPoint` in `lib/geo.ts`).
- **Outlines in `lib/geo.ts`:**
  - `pivotOutline(shape)` returns null for a point kind;
  - `shapeAcres` returns null for a point kind;
  - `surveyRing(shape)` gives the soil survey the outline, or a circle about 100 m across around a point.

  A field outline is the natural survey ring for a point-kind system's fields.

- **Words.** Growers see each kind's name ("Traveler: West lane", `kind_name`, `KIND_NAMES`, `KIND_NOUNS`) and "irrigation system" collectively. PLAN.md's G.10 text says "pivot" in places; use these words in the interface.
- **Irrigation groups** (`PivotGroup` in code) are drawn on the overview map as a convex hull (`groupOutline`, `groupFeatures` in `lib/map/pivots.ts`).
- **The overview map's layers** (`OverviewMap.svelte`):
  - `groups-*` (under everything of ours);
  - `pivots-fill`, `pivots-casing`, `pivots-line` (polygons only);
  - `pivots-point` (a circle layer for point kinds).

  Clicks query `PIVOT_LAYER` and `POINT_LAYER`, and `mapOverlays` skips probes on both. `isOwnSource` must list any new source, or a basemap switch drops it.

- **Badges.** `PivotMarker` puts each system's field badges at its location. PLAN.md says fields with an outline are filled by status and fields without one keep the badges, so decide how a system whose fields are partly outlined shows its badges.

## What the code already has

- **`fields.boundary`** (jsonb) has existed since the first migration (`20261003190100`, commented "GeoJSON, for areas that aren't the whole pivot circle"). Nothing reads or writes it, and no field has one. G.10 can validate and use it rather than add a column; check its null default and say so in the plan.
- **Plot pins:** `plantings.latitude` and `plantings.longitude` (check constraint `plantings_pin_both`) are stored and permitted by `PlantingsController`, with no interface. G.11's item 6 puts them on the map with G.10.
- **Geometry helpers in `lib/geo.ts`:**
  - `pointInPolygon` (outer ring and holes);
  - `convexHull`, `destination`, `distanceM`, `bearing`;
  - `pivotAcres` and `shapeAcres` (no general polygon area yet: G.10 needs a spherical-excess or equal-area polygon area for "Suggested area"; add it with vitests).
- **Soil survey** (`lib/soils.ts`):
  - `soilQuery(ring)` and `fetchSoilSurvey(ring)` already take any ring and return area-weighted map units, so "dominant soil in the outline" is mostly passing the field's ring;
  - `fetchSoilAreas(bounds)` and `wktPolygons` draw the Soil types layer.

  G.11's item 10 wants each soil's share of a field in the plot soil menu; that's the same query on the field's ring.

- **Map plumbing:**
  - `loadMapLibre()` loads MapLibre on demand with its Vite-bundled worker;
  - `PivotMap.svelte` is the setup picker (handles via `followPointer`, not MapLibre draggables; see the gotcha in CLAUDE.md);
  - `basemaps.ts` and `setBasemap` re-add our sources after a style change.

## Constraints that shape the choices

- **Content Security Policy:** scripts load only from WISP. terra-draw and shpjs must be npm dependencies bundled by Vite and loaded on demand (dynamic `import()`, like MapLibre), never from a CDN. Connections and images may go to any https source.
- **Nothing goes to the server but the result.** Parse shapefiles, GeoJSON and KML in the browser. A shapefile zip needs its `.prj` for reprojection, which shpjs handles. KML needs a parser: `@tmcw/togeojson` is small, MIT and widely used; check its version and license before adding it.
- **Tenancy:** any new controller or action (an import endpoint, say) loads fields through `Current.group` and gets a cross-tenant request spec.
- **Seasons keep their values** (G.9): an outline's acres can be offered for `fields.area_acres`, but never change a past planting's area. Editing a field updates open plantings only (`Field#update_open_plantings`); check that boundary edits go through the same path.
- **Validation lives on the server** (PLAN.md): closed rings, a vertex cap (simplify on import), coordinates inside `Pivot::LATITUDES` and `LONGITUDES`, and a plausible maximum size. Mirror the limits in `lib/geo.ts`, as the pivot size limits are.
- **Accessibility:**
  - drawing needs a mouse or touch, so the About page's accessibility note (the pivot handles already have boxes below the map) needs an equivalent: import, or "Same as the irrigation system";
  - add the import and draw pages to `e2e/accessibility.spec.ts`;
  - watch the 320 px reflow test (it caught Setup's farm buttons in G.5).

## Decided since PLAN.md's G.10 text was written

- **Problems list** (Ben, 2026-11-11; in PLAN.md G.10): a system never moves with its field (moving it would change the weather cell). Setup lists fields whose outline is far from, or not under, their system's point or shape ("Home North's outline is 2.1 mi from Traveler: Lane 3"), to fix by hand.
- **"Same as the irrigation system"** only makes sense for a pivot or linear. A point kind has no outline to copy, so offer drawing or import there.

## Questions to put to Ben in the plan

1. **Scope of this step.** Import and draw are both listed; import comes first. Should both land in G.10, or import plus "Same as the irrigation system" first, with free drawing (terra-draw) as a follow-up?
2. **Import matching.** Imported shapes are matched to existing fields or create new ones under a chosen system. How does a new field from an import get its system: pick one, or suggest the system the shape sits under (point in outline, or nearest point kind)?
3. **The overview map with outlines.** Fields filled by status, systems as outlines on top with an "Irrigation systems" layer toggle. When some of a system's fields have outlines and some don't, does the system keep its badge marker for the rest?
4. **Area.** When a field gets an outline, should the field's area follow it automatically for open plantings, or only be offered ("Use 38.2 ac from the outline")? PLAN.md says offered.
5. **The problems list.** What distance counts as "far" for a point kind (say a quarter mile from the outline), and is the list on Setup only, or also a dashboard notice?
6. **Branch:** stay on `beta-readiness` (recommended; G.11's map pins and G.8's example farm build on it).

## Suggested commits

1. Model and validation (`fields.boundary`, limits), polygon area, and the soil survey on the outline.
2. Import (parse, match, preview, save).
3. "Same as the irrigation system", and drawing if in scope.
4. The overview map (fields by status, systems on top, pins for plots).
5. The problems list.
6. The demo seed's outlines, which the pre-beta location review may redo.
