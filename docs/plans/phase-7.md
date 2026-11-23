# Phase 7: Map

*A record of the build, frozen when it was folded out of `PLAN.md` on 2026-11-22: it says what was planned and done at the time, and later work may have changed or replaced it. For how the app works now, see [docs/architecture.md](../architecture.md) and [docs/engine.md](../engine.md); for why, [docs/decisions.md](../decisions.md). Section numbers (§) refer to the original design ([design.md](design.md)), except §2 and §15, now [docs/decisions.md](../decisions.md), and §9, now [docs/legacy-audit.md](../legacy-audit.md).*

Proposed 2026-10-17 (Ben): a **Map** tab next to Dashboard showing the operation's current state at a glance: every pivot where it is, its fields' status badges, a popup per pivot with its fields' cards, the usual map controls, and a few optional public layers (radar, observed and forecast rain, drought). It reads the same data as the dashboard, with nothing new stored.

**Decided 2026-10-17 (Ben):** the map is its own tab, and the dashboard keeps its layout. Fields are badges on the pivot, not pie wedges (wedges would suggest where each field is). A collapsible side list of field cards. The public layers may be flaky as long as a failure is caught and reported gently. The soil survey comes into Phase 7 (G); weather zones and a map in the email go to later.

- [x] Moving a pivot (or changing its cell) triggers a backfill and recalculation. *(Shipped in Phase 3: `Pivot#backfill_weather` on a cell change; the balance is recalculated on read.)*

**Fields on the map.** We know where pivots are but not where their fields are (`fields.boundary` exists in §4 but nothing sets it). So the map stays honest: the pivot is drawn to scale, and its fields are shown as badges *on* it rather than as made-up areas.
- The pivot's circle or arc, to scale, outlined and lightly filled with its **most urgent** field's status color (irrigate > caution > ok > full; grey when no field is in season or the pivot has no fields).
- At the center, a screen-sized marker (HTML, not to scale) holding one `StatusBadge` per field in season, in name order, with a "Season ended" or "No crop" chip otherwise. Below a zoom threshold (pivots a few pixels across) it collapses to a single dot in the most urgent color with the field count.
- Pivot names label the outline at closer zooms, as in the picker. *(As built: the marker shows the name from zoom 13, badges from 11.5, a dot below; fields not in season are gray dots.)*
- *Later, not Phase 7:* drawing fields as sectors of their pivot (a start and end bearing per field, set in the picker; most split pivots are halves or quarters). Then each sector takes its own color. Only once growers ask for it.

## A. Shared map pieces (refactor first)
- [x] `lib/map/`: the MapLibre loader (worker URL, dynamic import), the basemap styles (USGS imagery, OpenFreeMap streets), `switchBase` keeping our own sources and layers, and a `BasemapToggle` component. `PivotMap` (the picker) moves onto them with no change in behavior. *(`lib/map/maplibre.ts`, `basemaps.ts` with `setBasemap`, `BasemapToggle`, `PlaceSearch`.)*
- [x] `FieldCard.svelte` from the dashboard's card, with a `compact` variant for the popup. The dashboard uses it unchanged. *(`lib/components/FieldCard.svelte`, with `onselect` for the side list; `StatusCounts` too.)*
- [x] `FieldStatuses` loading moves out of `DashboardController` into a small query object (`OperationOverview`?) used by both pages, so the map and the dashboard can't drift. *(`OperationOverview`.)*

## B. Map page (`/map`, `MapController#show`, `Map/Show`)
- [x] Nav: "Map" after Dashboard. Props: `today`, and farms › pivots (location, radius, arc, weather cell) › field cards, as on the dashboard. A cross-tenant request spec. *(`MapController`, `spec/requests/map_spec.rb`; each pivot also gets its zone's `WeatherSummary` totals.)*
- [x] Map as tall as the window, with the side list (below) on the left.
- [x] Farm filter (as on the dashboard): it fits the map to that farm's pivots.
- [x] Status counts above the map, as on the dashboard, and a legend for the status colors. *(The status counts, with their labelled badges, serve as the legend.)*
- [x] **"Needs water within" control:** today / 3 days / 7 days. Highlights the pivots with a field whose `crossing.days` falls in the window and dims the rest, so a grower can plan the week's irrigation by place. This uses `crossing`, which the summary already carries, so no new logic.
- [x] Empty states: no pivots (link to quick setup), off season (every field greyed, "Season ended" in popups; the weather layers still work).
- [x] The last view (center, zoom, basemap, overlays, sort, sidebar open or closed) remembered per browser (localStorage, wrapped in try/catch). The first visit fits all pivots. *(`lib/map/prefs.ts`, per operation.)*

**Side list** (the common map-and-list pattern)
- [x] Every field in the farm filter, as the compact `FieldCard` (A), each card naming its pivot.
- [x] Sort: **Most urgent** (default): irrigate, then caution, ok and full, each soonest "Irrigate by" first; then upcoming, season ended, and no crop. Or **North to south**: by pivot latitude, the order the pivots appear on the map, with a pivot's fields together.
- [x] Expands and collapses (a button on its edge; collapsed, the map takes the width). On phones it's a sheet under the map that pulls up. *(On phones the list sits under the map with Hide/Show rather than a pull-up sheet.)*
- [x] Selecting is shared both ways: clicking a card flies to its pivot, outlines the pivot and opens its popup; clicking a pivot on the map highlights its fields' card borders and scrolls the first into view. One selection at a time; Escape or a click on empty map clears it.
- [x] A filter box (pivot or field name) narrows the list.

## C. Pivot popup
- [x] Opens on a click on the pivot or its marker; on phones it's a bottom sheet instead of a floating popup.
- [x] Header: pivot name and farm, links to View, Edit and to daily entry for this pivot. *(View and Edit only: daily entry has no per-pivot view to link to.)*
- [x] Each field's compact card: status, AD today with the sparkline, the outlook headline ("Irrigate by …"), last rain and irrigation, due tasks; it links to the field page. *(The compact card leaves out last rain and irrigation.)*
- [x] The pivot's weather in one line: rain over the last 7 days and forecast for the next 7, ET over the last 7 (from `weather_days` and the latest forecast for its cell, already preloaded).
- [x] With the drought layer loaded: the pivot's Drought Monitor category (point in polygon in the browser).

## D. Controls
- [x] Zoom in and out (`NavigationControl`), **fit all pivots**, **my location** (`GeolocateControl`; useful in the truck), fullscreen, scale bar.
- [x] Basemap: Satellite / Map, the picker's toggle (A).
- [x] Layers button: a panel with the overlays (E), each with on/off, opacity, its legend and valid time, and a link to the source.
- [x] Find a place (the picker's geocoder); pivots and fields are found with the side list's filter. *(Hidden on phones, where the map has no room for it.)*

## E. Optional overlays (all off by default, loaded by the browser, never by our server)
Each overlay lives in a registry (`lib/map/overlays.ts`: id, name, tile URL builder, attribution, legend stops, refresh interval, description), unit tested for its URLs. All of these were checked on 2026-10-17: they answer with CORS headers and serve Web Mercator.

**When a source fails** (decided: depend on them, but fail gently): MapLibre's `error` events are caught per source. The layer stays switched on but is marked "unavailable" in the panel, a small notice shows on the map for a few seconds ("Radar isn't loading right now; try again later"), and the map, pivots and other layers carry on. One notice per layer per page visit, not one per tile. The layer retries at its next refresh, or when it's switched off and on.

| Overlay | Source | Notes |
|---|---|---|
| **Radar now** | Iowa Environmental Mesonet NEXRAD composite tiles (`mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/{z}/{x}/{y}.png`) | Every 5 minutes; the panel shows the time. A loop over the last hour (IEM's `-m05m`…`-m55m` layers) is a stretch goal |
| **Rain, last 24 h / 72 h** (radar estimate) | IEM MRMS accumulation tiles (`q2-p24h`, `q2-p72h`); *as built (H): NOAA's MRMS image service (`obs/mrms_qpe`)* | Good next to WISP's own numbers: did the gauge, the model and the radar agree? |
| **Forecast rain**, day 1 / days 1–3 / days 1–7 | NOAA WPC QPF (`mapservices.weather.noaa.gov/vector/rest/services/precip/wpc_qpf/MapServer`, `export` with `{bbox-epsg-3857}`) | A human forecaster's product; it can differ from the Open-Meteo forecast WISP uses, and the legend says so |
| **Drought Monitor** | USDM current polygons (`services5.arcgis.com/0OTVzJS4K09zlixn/.../USDM_current/FeatureServer/0/query`, GeoJSON; as built, loaded once for the area 3° around the operation's pivots) | Weekly (Thursday); the panel shows the map date. USDM's standard D0–D4 colors |

Not proposed: RainViewer (its free tier is limited) and NWS warnings (useful, but a crowded layer; maybe later for frost and freeze).

## F. Soil survey in setup
USDA NRCS Soil Data Access (SSURGO) has both a map layer and a query API, free and CORS enabled (checked 2026-10-17: a point in the Central Sands returns "Plainfield sand, 0 to 2 percent slopes", Plainfield 90%, surface texture Sand, AWC 0.08).
- [x] **Soil layer** on the pivot picker (and as an overlay on the Map tab): map-unit outlines from the WMS (`SDMDataAccess.sc.egov.usda.gov/Spatial/SDM.wms`, layer `mapunitpoly`), visible from about zoom 13, with each unit's name on click. *(A "Soils" toggle on the picker and a layer on the Map tab. No click-to-identify, as clicks place or select pivots; the survey box lists the map units under the pivot instead.)*
- [x] **Suggest the soil type** for a pivot's fields: query the map units under the pivot's circle or arc (`Tabular/post.rest`, `SDA_Get_Mukey_from_intersection_with_WktWgs84` with the polygon from `pivotRing`). Take each unit's area share and its dominant component's surface texture, and show "Soil survey: mostly Plainfield sand (82%), some Richford loamy sand (18%) → Sand". The field form and quick setup preselect that soil type when the user hasn't chosen one, and never overwrite a choice. The user can always change it. *(`lib/soils.ts`, `SoilSurvey.svelte`: area shares from `mupolygon` intersected with the pivot's polygon in one query, about 5 s. Quick setup's fields and a new field in Setup take the suggestion until the user picks a soil; the pivot form shows it for information.)*
- [x] **Soil types reviewed** (Ben, 2026-10-17): Loamy Sand, Sandy Clay Loam, Silty Clay Loam and Muck added, and sandy loam, loam, silt loam and clay loam updated, from Wisconsin SSURGO medians and Saxton & Rawls (2006). The legacy values had no known source. Each entry in `soil_types.yml` gives both sources' values and the legacy one.
- [x] **Texture mapping** to our eleven soil types, as a table in `lib/soils.ts`, unit tested: each USDA texture to its class, with modifiers dropped (fine sand and coarse sand → Sand, loamy fine sand → Loamy Sand, fine sandy loam → Sandy Loam), muck and mucky peat → Muck, and no suggestion for peat or textures we don't have (silty clay, sandy clay).
- [x] Failure is quiet: no suggestion and a short "Soil survey unavailable" note; setup never waits on it. Outside the survey's coverage (Canada) there's no suggestion.
- [x] **About page:** a Soils section: what the soil type sets, the setup suggestion, and a table of every type's field capacity, wilting point, available water and where its values come from (`basis` in `soil_types.yml`). The Day to day section describes the Map tab.
- [x] **Thin organic surface layers skipped** (Ben, 2026-10-19): Friendship loamy sand was suggested as Muck, because its top horizon in the survey is 2 cm of leaf litter ("moderately decomposed plant material"). The surface texture is now the top horizon only for organic soils (Histosols: Markey, Seelyeville), and otherwise the first mineral horizon (`SURFACE_TEXTURE` in `lib/soils.ts`). Checked against Soil Data Access in Portage and Waushara counties: Friendship, Plainfield, Roscommon and Newson come out as their mineral textures, and the Histosols stay Muck. Minocqua muck (3 cm of muck over silt loam) now suggests Silt Loam.
- [~] *Maybe:* show the survey's available water capacity next to the soil type's default field capacity and wilting point, as a check. Not used in the balance. *(Moved to After launch.)*

## H. Revisions after trying it (Ben, 2026-10-17)
- [x] **No soil layer on the Map tab.** The survey's map unit codes meant little and loaded slowly. The pivot picker's layer shows **WISP's soil types** instead: the survey's polygons around the pivot (or the view, zoomed in), colored coarse to fine and labeled by the type each unit's surface texture suggests, with the unit's name on hover and a legend of the types present (`lib/soils.ts` `fetchSoilAreas`, about 5–7 s for the area around a pivot).
- [x] **Values under the pointer:** resting the mouse on the map (or tapping it, off the pivots) shows each shown layer's value there (`MapOverlays.probe`, `OverlayTooltip`). Radar: read from the same Iowa Environmental Mesonet tile the map draws, whose colors are IEM's N0Q palette (index 1 is −32 dBZ, 0.5 dBZ an index; `lib/map/radar.ts`), described as light to very heavy rain. NOAA's radar image service was tried first, but it stores rendered colors with no table back to dBZ, and its default raster is the oldest. Recent rain: NOAA's MRMS image service (`obs/mrms_qpe`), which the 24- and 72-hour layers now come from too, drawn with NOAA's own classes so the picture and the value agree (its pixel values are millimeters, checked against WISP's weather at North 160). Forecast rain: a point query on WPC's layer, giving its class (0.25–0.50 in). Drought: the loaded polygons. Where a layer has nothing, the tooltip says so ("No rain", "No drought"); outside the US, "No data outside the US" (a simplified outline, us-atlas 3.0.1 from Census Bureau boundaries, `lib/map/us-outline.json`, loaded on first use).
- [x] ~~"None" shown as light gray over the US~~: tried and removed (Ben): with values under the pointer, the gray only dimmed the map.

## I. Pivot shapes (Ben, 2026-10-19)
- [x] **Partial circles on the map:** a partial circle has a handle at each end of its arc in the picker, dragged to set its start and end (whole degrees, at least 5° swept); the typed angles still work.
- [x] **Linear moves:** `pivots.kind` (`center` or `linear`) with `length_ft`, `travel_ft` and `travel_bearing_deg`. The picker draws a linear as a rectangle with handles on its front left and back right corners (northwest and southeast for one traveling north); dragging one keeps the opposite corner and the direction fixed, and a corner can't cross the opposite one. A round handle past its front end turns it, in whole degrees, snapping to north–south or east–west within 2° (`resizeLinear`, `snapBearing`). The pivot form and quick setup share `PivotShapeFields` (kind, map, soil survey, coordinates, sizes, arc). The Map tab, the soil survey and the other-pivot outlines draw either kind (`pivotOutline` in `lib/geo.ts`).
- [x] **Maximum sizes** (§4, pivots), enforced by `Pivot` validations, check constraints and the picker's handles.
- [x] Placing a pivot with a click zooms the picker to fit it and its handles.
- [x] **Rotated linears** (Ben, 2026-10-19): plenty of linears don't run north–south or east–west, so a linear has a direction of travel.
- [x] **Handle polish:** handles move only where the shape puts them (no flicker between the pointer and the shape); a double-ended arrow along a linear's travel, 80% of its length (`travelArrow`); cursors drawn for each handle, circling arrows for those that turn about the center and a double arrow along the drag for those that resize (`lib/map/cursors.ts`).

## G. Ideas for later (Phase 8 polish or after launch)
- Field sectors (above).
- A **WISP weather zones** layer: the O1280 cells with the operation's pivots, colored by WISP's own 7-day rain or ET, which shows which pivots share weather and matches what the balance uses. The cell edges come from `Weather::Grid.cell_for` (ported from Ben's R code; cell width depends on the latitude ring), so they are served with the pivots and not recomputed in the browser.
- The map in the daily email (a static image per farm).
- A radar loop over the last hour.

- **Exit** *(met 2026-10-17; `bin/ci` passes, with the map, failing-layer, drought and soil suggestion tests in `e2e/smoke.spec.ts`)*: every pivot in the demo seed is drawn where it is, with its fields' badges and a popup matching their dashboard cards. The side list sorts both ways and selects with the map. The map fits the farm filter. Each overlay loads with its legend and time, and a blocked source shows its notice without breaking the map (Playwright, with the route aborted). Playwright opens the map, picks a field in the list, sees its pivot selected and follows the field link. The pivot picker suggests Sand for a Central Sands pivot (a vitest with a recorded Soil Data Access response). Editing a location updates its weather within one job cycle.
