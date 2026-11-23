# WISP 3: the original design

*The design written before the build (October 2026), amended along the way with "as built" notes, and frozen when it was folded out of `PLAN.md` on 2026-11-22. Where it and the code disagree, the code is right: for how the app works now, see [docs/architecture.md](../architecture.md) and [docs/engine.md](../engine.md); for why, [docs/decisions.md](../decisions.md). Section numbers are kept from `PLAN.md`: §2 (decisions) and §15 (open questions) are now [docs/decisions.md](../decisions.md), §9 (the legacy audit) [docs/legacy-audit.md](../legacy-audit.md), and §14 (the phases) the phase files beside this one, regrouped by theme ([README.md](README.md) maps the old phase numbers).*

## 1. Goals

- **Modern, maintainable codebase**: Rails 8 backend with Svelte 5 + Tailwind v4 frontend; no jQuery, jqGrid, or Google Charts.
- **Correct, testable water-balance engine**: a pure function of inputs, with no callback cascades, stored derived values, or magic epsilon values.
- **Weather from Open-Meteo** (observed, forecast, ensemble), with **no dependency on AgWeather**.
- **Forecast-driven projection**: run the real checkbook model forward through the forecast, with ensemble uncertainty bands instead of a straight-line estimate.
- **Better charts**: season view, forecast region, thresholds, rain and irrigation bars, uncertainty band.
- **Email login kept** (password + confirmation), plus **one-time login links**.
- **Email alerts** for projected depletion.
- **Map view** of farms, pivots and fields, colored by status.
- **Multi-season history kept**, replacing the Feb 15 wipe.

### Non-goals (for the 2027 launch)

- Native mobile apps. The UI must work well on phones, and a PWA is optional later.
- Soil-moisture sensor integrations.
- Rebuilding AgWeather. That is a separate project, and WISP 3 must not depend on it.

---

## 3. Architecture and stack

```
Browser (Svelte 5 pages, Tailwind v4, ECharts, MapLibre)
   │  Inertia protocol (JSON page props over normal Rails requests; session cookie + CSRF)
Rails 8.1 (Ruby 4.0)
   ├── Controllers → Inertia responses (render inertia: "Fields/Show", props: …)
   ├── Devise (+ magic-link strategy)
   ├── Domain services: WaterBalance, PlantingStatus (projection), EnsembleProjection, Canopy, Weather::Fetcher, digest
   ├── Weather::OpenMeteo client (free / customer endpoints)
   ├── Solid Queue (jobs + recurring schedule), Solid Cache
   └── Action Mailer (sendmail on existing hosts)
PostgreSQL 16
```

### Backend

| Concern | Choice | Notes |
|---|---|---|
| Framework | Rails 8.1, Ruby 4.0.x | Same toolchain as legacy, so the deploy knowledge carries over |
| Frontend bridge | `inertia_rails` | Server-side routing, no separate API or token auth |
| Assets | `vite_rails` | Replaces Sprockets, sassc, coffee, terser |
| Auth | Devise (`database_authenticatable, confirmable, recoverable, registerable, rememberable, trackable, validatable, timeoutable`) + magic links (§7) | Users re-register (D10) |
| Serialization / types | Alba serializers + `typelizer` | Generates TypeScript types for page props from serializers |
| Route helpers in JS | Typelizer route helpers (`@/routes`) | Typed `{url, method}` helpers that Inertia's `<Form action>` and `<Link href>` accept directly; replaces `js-routes` |
| Jobs | Solid Queue + `config/recurring.yml` | Backed by Postgres, no Redis. Runs as a systemd service (§12) |
| Cache | Solid Cache | Replaces the Redis added recently |
| HTTP client | `Net::HTTP` via a thin wrapper, or `faraday` with retry middleware | Timeouts, retries and 429 backoff in one place |
| Rate limiting | `WindowLimit` (fixed windows in Solid Cache) on sign-in emails and codes + `rack-attack` | Keep the current rack-attack rules |
| Lint / test | Standard, RSpec, FactoryBot, WebMock | Same as legacy |

### Frontend

| Concern | Choice | Notes |
|---|---|---|
| UI | Svelte 5 (runes) + TypeScript, `@inertiajs/svelte` | Pages in `app/frontend/pages`, components in `app/frontend/lib` |
| Styling | **Tailwind CSS v4** via `@tailwindcss/vite`, CSS-first config (`@theme` in `app/frontend/entrypoints/application.css`) | Design tokens for status colors (full/ok/caution/irrigate) defined once |
| Headless components | `bits-ui` | Accessible dialogs, selects, popovers, date pickers |
| Charts | Apache ECharts (`echarts/core`, tree-shaken) wrapped in a small Svelte `use:chart` action | Mixed bar and line charts, `markArea` for the forecast region, `markLine` for thresholds, `dataZoom` for scrolling through the season, touch tooltips |
| Map | MapLibre GL JS (`svelte-maplibre-gl` or a thin wrapper) | Base layers: USGS National Map imagery (public domain, good rural coverage) + OpenFreeMap vector streets |
| Tables | Custom editable grid component | Replaces jqGrid; keyboard navigation, tab to move between cells, sized for phones |
| Forms | Inertia `useForm` | Server validation errors flow back as props |
| JS tests | Vitest + `@testing-library/svelte`; Playwright for e2e | |

---

## 4. Domain model (new schema)

Principle: **store only what users enter or what arrives from weather providers; calculate everything else.** No `ad`, `adj_et`, `deep_drainage` or `calculated_pct_*` columns.

```
User ──< Membership >── Group (an "account": farm operation)
                          ├──< Farm
                          │     └──< Pivot (location, geometry)
                          │           ├──< PivotIrrigation (dropped by D15: irrigation is each field's and plot's own entry)
                          │           └──< Field (soil, area)
                          │                 └──< Planting (one crop-season: plant, dates, MRZD, MAD, ET method)
                          │                       └──< CanopyObservation (date, pct_cover | lai)
                          │                 └──< FieldEntry (date: rain override, irrigation, soil moisture obs, notes)
                          ├──< FieldGroup >──< FieldGroupMember (Field)
                          │     └──< FieldGroupEntry (date: same columns as FieldEntry)
                          └── AlertPreference (per user)
WeatherCell (ECMWF O1280 grid cell) ──< WeatherDay (date: et0, precip, temperature, humidity, wind, cloud, soil temp/moisture…, model, fetched_at, final)
                              └──< WeatherForecast (issued_at, model, daily arrays, ensemble members jsonb)
Plant, SoilType (reference data, seeded from YAML)
AlertDelivery (dedupe log), MagicLinkToken (if not using stateless tokens), Announcement (replaces Blog)
```

### Table notes

- **groups**: `name`, `use_model_precip` (boolean, default **true**; replaces the inverted `precip_use_agwx`, §9). Users can belong to several groups, with a group switcher in the UI. The legacy app hard-coded `groups.first`.
- **farms**: no `year` column. Farms persist across seasons.
- **pivots**: `name, kind, latitude, longitude, radius_ft, arc_start_deg, arc_end_deg (nullable = full circle), length_ft, travel_ft, travel_bearing_deg, equipment, pump_capacity_gpm, inches_at_100 (a pivot's or linear's depth at 100% on the percent timer, for the irrigation calculator; 2026-11-22), notes`.
  - **Kind** (Phase 7 I): `center` (a circle, or an arc for a partial circle, around its location) or `linear` (a linear move: a machine `length_ft` long traveling `travel_ft` along `travel_bearing_deg`, an integer 0–179 from north since it runs both ways; a rectangle centered on its location). Each kind keeps only its own dimensions. Size limits, in the model, the database and the picker: a center pivot's radius at most 3,000 ft (the longest sold are about 2,900 ft); a linear machine at most 3,300 ft long (the longest about 3,200 ft) and its travel at most a mile.
  - **Location is required and has no default.** In legacy production, 215 of 443 pivots (49%) were still at the default 43, −89, so half of all fields got weather for the wrong place.
  - Pivot creation therefore starts with a map picker (click the pivot center, drag the radius) or typed coordinates, validated to fall within a US-and-Canada bounding box (latitude 18–84, longitude −180 to −52). Weather coverage is global, so this can widen later.
- **fields**: `name, area_acres, soil_type_id, field_capacity, perm_wilting_pt` (nullable, so NULL means "use the soil type default"; the legacy code used 0.0 for that), `notes`, optional `boundary` (GeoJSON jsonb) for non-pivot or partial areas, `use_model_precip` (nullable boolean, Phase 6.6: NULL follows the group's setting; true or false overrides it for this field).
- **plantings**: `field_id, plant_id, variety, season_start (default Apr 1), emergence_date, end_date (harvest/kill, default Nov 30), max_root_zone_depth, mad_frac, et_method (pct_cover | lai), target_ad_pct, initial_moisture_pct (nullable, NULL = start at field capacity), notes`. The season year is `season_start.year` (no separate column to disagree with it). Plantings on the same field can't overlap in time (model validation plus a Postgres exclusion constraint). This supports double-cropping properly (replacing the legacy `current_crop` "latest emergence" hack). Emergence may precede `season_start` (perennials).
- **canopy_observations**: `planting_id, date, pct_cover (0–100) | lai (≥0)`. These are anchor points for interpolation (§5.3).
- **field_entries**: `field_id, date, rain_in, irrigation_in, soil_moisture_pct, notes`. All nullable, NULL = not entered, **0.0 = user entered zero** (removes the legacy `CHANGE_EPSILON` workaround). Unique on `(field_id, date)`.
- **field_group_entries**: the same columns, keyed on `(field_group_id, date)`. These apply to member fields **when read**, not copied in on save.
- **pivot_irrigations** (D9; dropped 2026-11-22 by D15, its rows moved into field and plot entries): `pivot_id, date, inches, run_hours, field_ids (bigint[], NULL = every field under the pivot), notes`. Unique `(pivot_id, date)`.
  - **Use case:** a pivot is often split into 2 fields (two crops, or two varieties of one crop) that get the same water. The grower enters the irrigation once on the pivot instead of once per field.
  - **Legacy production:** 53 of 443 pivots had 2 or more fields; 34 had 2, and one had 7. The "applies to" picker must handle 7+ fields cleanly (checkbox list, all checked by default).
  - **Applied when read, not copied** into each field. Editing or deleting the pivot entry updates every field at once, and a per-field entry still wins for days when one field got a different amount (end-gun off, a sector skipped).
  - **Run hours instead of inches:** if only `run_hours` is given, inches are calculated as `pump_capacity_gpm × run_hours × 60 / (27,154 × irrigated acres)`, where irrigated acres is the sum of `area_acres` over the fields it applied to. This needs pump capacity and field areas; if they are missing, the form asks for inches. (27,154 gallons = 1 acre-inch.)
  - **UI:** the pivot's daily row shows one irrigation cell; each field's grid shows the value with a "from pivot" badge and an override. *(Superseded by D15, 2026-11-22: the system's row fills its fields' boxes, and nothing is inherited.)*
- **weather_cells**: `latitude, longitude` of an ECMWF IFS O1280 grid cell center (~9 km; `Weather::Grid`, ported from Ben's R client), plus `timezone` and `elevation_m` from Open-Meteo and the last fetch/error. Pivots get their cell when created or moved (`pivots.weather_cell_id`), which queues a backfill. Requests go to the cell center, so every pivot in a cell shares one series.
- **weather_days**: `weather_cell_id, date`, daily values built from hourly data in the cell's local day: `et0_in, precip_in, rain_in, snowfall_in, snow_depth_in, tmax_f, tmin_f, tmean_f, dew_point_f, rh_mean/min/max_pct, vpd_max_kpa, pressure_msl_hpa, wind_speed(_max)_mph, wind_gust_max_mph, wind_direction_deg, cloud_cover(_low/_mid/_high)_pct`, soil temperature (°F) and moisture (m³/m³, comparable with field capacity) at 0–7, 7–28, 28–100 and 100–255 cm; `model, soil_model, hours, fetched_at, final`. Unique `(cell, date)`. Missing values are **NULL**, never 0.
- **weather_forecasts**: `weather_cell_id, issued_at, model, kind (deterministic|ensemble), payload jsonb` (deterministic: `{"days": [{date, <weather_days columns>}, …]}`; ensemble: `{"dates": [...], "members": [{"et0_in": [...], "precip_in": [...]}, …]}`, one entry per member). Keep the most recent 14 issues of each kind per cell for later checks of forecast accuracy, and prune older ones.
- **users** (beyond Devise columns): `first_name, last_name, admin, unit_system (imperial|metric, default imperial)`.
- **Daily digest** (Phase 6, replacing event-based alerts; decided 2026-10-04): `users.digest_frequency` (`never | daily | needed`, default never since 2026-10-07; changed from an on/off switch 2026-10-05), `users.digest_sent_on` (so a rerun of the job doesn't send twice) and `users.digest_test_sent_at` (the test email's 5-minute cooldown). **digest_exclusions**: `user_id, subject (Group | Farm | Field)`, unique. Every field in the user's operations is covered unless it, its farm or its operation is excluded; saving the settings leaves out a farm or operation whole when none of its fields are picked, so fields added there later stay out, and otherwise excludes single fields, so new ones join.

### Precedence when resolving a day's inputs for a field

```
rain       = field_entry.rain_in ?? group_entry.rain_in ?? (use_model_precip || date > today ? weather.precip_in : 0.0)
             where use_model_precip = pivot_group.use_model_precip ?? farm.use_model_precip   (Phase 6.6; Q7; farms and irrigation groups since 2026-11-19)
irrigation = field_entry.irrigation_in ?? pivot_irrigation.inches (if this field is included) ?? group_entry.irrigation_in ?? 0.0
             since D15 (2026-11-22): (a plot's planting_entry, else field_entry).irrigation_in ?? 0.0
et0        = weather.et0_in            (NULL → gap fill, §5.4)
moisture   = field_entry.soil_moisture_pct ?? group_entry.soil_moisture_pct   (resets balance, §5.2)
canopy     = interpolated from canopy_observations (§5.3); group pct-cover entries become CanopyObservations on each member planting
```

A pivot entry outranks a field-group entry because it describes water that physically reached that field; field groups are a convenience for shared data entry.

Every resolved value carries a **provenance tag** (`entered`, `pivot`, `group`, `model`, `forecast`, `gap_fill`) that the UI shows, replacing the legacy "E" suffix. *(Since D15, 2026-11-22, irrigation's are only `entered` or `none`; field groups and `pivot` are gone.)*

---

## 5. Water-balance engine

A plain-Ruby module with no ActiveRecord dependency: `WaterBalance.run(params, days) → [DayResult]`. It is fast enough to recalculate on every request (≈250 days × a few floating-point operations) and is the single source of truth for the UI, alerts, CSV export and projections.

Units: **inches** internally (matching the legacy app and its users). Open-Meteo data is requested in metric and converted explicitly (`mm / 25.4`, `°C → °F`).

### 5.1 Static parameters (per planting)

```
FC, PWP     = field override ?? soil_type default        (fractions, validated 0 < PWP < FC < 0.6)
MRZD        = planting.max_root_zone_depth (in)          (validated > 0)
MAD         = planting.mad_frac                          (validated 0.05–0.95)
TAW         = (FC − PWP) × MRZD
AD_max      = MAD × TAW
AD_pwp      = −(1 − MAD) × TAW
pct_at_ad0  = (FC − AD_max / MRZD) × 100
target_in   = target_ad_pct / 100 × AD_max               (nullable)
```

### 5.2 Daily step

```
if moisture observation present:
    ad_raw = MRZD × (obs_pct − pct_at_ad0) / 100
    AD     = clamp(ad_raw, AD_pwp, AD_max)
    DD     = max(0, ad_raw − AD_max)
    adj_et = calculated as normal (reported, not applied)
else:
    adj_et = crop_et(et0_or_gapfill, canopy)
    w      = AD_prev + rain + irrigation − adj_et
    AD     = clamp(w, AD_pwp, AD_max)
    DD     = max(0, w − AD_max)
pct_moisture = pct_at_ad0 + AD / MRZD × 100
```

The initial AD on `season_start` comes from `initial_moisture_pct` via the same observation formula, or AD_max (field capacity) if it is NULL.

**Changes from legacy behavior (deliberate; each needs a golden-test exception, §10):**
- The observation reset is capped at **AD_max** and the excess is recorded as deep drainage. Legacy capped at TAW, which let AD exceed AD_max and never recorded drainage.
- Observation resets are floored at AD_pwp. Legacy had no floor.
- No `< 0.01 → 0` truncation of deep drainage. Rounding happens in the UI only.
- No `0.00001` threshold on drainage: the clamp is exact, and floating-point noise is handled by rounding to 4 decimal places on output.

### 5.3 Canopy

- **Percent cover** (default): 0 before emergence; linear interpolation between observations; **held at the last observed value until `end_date`**; 0 after `end_date`. Legacy only carried the last value forward 6 days, after which cover fell back to 0 or a stale value, which collapsed ET to the bare-soil rate.
- Interpolation from emergence (0%) to the first observation. Readings dated before emergence are ignored (for perennials, enter the green-up date as emergence).
- **LAI** (kept, D8): LAI comes from a crop curve by default, and entered LAI observations override it, interpolated the same way as percent cover. Kc = 1.1 × (1 − e^(−1.5·LAI)), with LAI clamped to ≥ 0.
  - **Field corn curve** (from the WIS v6.3.11 spreadsheet): `LAI = 9e-12 × d^7.95 × e^(−0.1 d)`, d = days since emergence. It peaks at LAI 4.07 on day 80 (Kc 1.10) and falls to 0.86 by day 140.
  - LAI is offered only for crops with an LAI curve, so far field corn (Phase 6.7; it replaced "LAI with entered readings for any crop", Q2 option B).
  - **Legacy problems (C4, C18):** the corn curve was applied to every crop, and sweet corn's placeholder curve produces **negative ET**.
  - The engine takes a `CanopyModel` per plant, so adding validated curves later is a data change.
  - With LAI readings entered, they replace the curve entirely (interpolated like percent cover); with none, the curve is used. Phase 6.7 revisits blending readings with the curve.
- **Phase 6.7 supersedes the interpolation above:** every crop with a curve (`db/reference/canopy_curves.yml`) follows it with no readings, and readings scale it ("ratio between readings"); the linear behavior above remains as a per-planting setting and for crops without a curve (C20).

### 5.4 Crop ET (percent-cover method, from the A3600 Table C regressions)

Port `adj_et_pct_cover` with these fixes:
- Clamp `pct_cover` to [0, 100]. Legacy treated negative values as full cover.
- The bare-soil step lookup uses half-open intervals (`< 0.16`, `< 0.32`). Legacy used `0..0.159` / `0.160..0.319`, so a value such as 0.1595 fell through to the highest bin.
- Fix the coefficient table as a named constant with a unit test per band boundary.
- Never negative: the 10% regression's intercept makes it slightly negative for et0 below about 0.0095 in.

**Gap fill** (observed days where et0 is NULL only): mean of the top 3 adj_ET values over the previous 7 days. This matches legacy; the RingBuffer is ported as a simple array window. Two fixes:
- Gap-filled values are **not** fed back into the window, so a long gap can't keep using the same filled value indefinitely.
- Legacy would raise `NoMethodError` if `ref_et` was NULL (`nil < epsilon`).
- The window is the previous 7 calendar days. If it holds no computed values (a gap longer than a week), the day has no ET and is flagged `missing`, as legacy's empty buffer also gave 0.

Gap fill is **never used for future days**; that's the projection's job (§6).

**C21 (2026-11-17, Q11):** the table's crop ET is scaled by each crop's FAO-56 Kc mid, rising with cover (1 on bare soil, Kc mid at 80% and above) and adjusted for the day's wind and minimum RH (FAO-56 eq. 62); LAI tops out at Kc mid. See §9 C21 and `CropEt`.

**C22 (2026-11-19, D14):** for every planting with a crop, FAO-56's dual crop coefficient replaces the table: (Kcb + Ke) × ET0, Kcb from the canopy (easing to the crop's harvest value over the late season) and Ke the soil surface's evaporation, carried day by day through wetting and drying (`SoilEvaporation`). The table stays for a planting without a crop's coefficients and in `LegacyEngine`. See §9 C22.

### 5.5 Status

| Status | Condition (today's AD) |
|---|---|
| Full | AD ≥ 0.9 × AD_max |
| OK | AD ≥ target_in (or ≥ 0.5 × AD_max if no target) |
| Caution | 0 < AD < target / OK level, or projected to reach 0 within `lead_days` |
| Irrigate | AD ≤ 0 |

Legacy only checked `AD < 0` today or in the next 2 days and ignored `target_ad_pct`.

---

## 6. Forecast projection

Run the **same engine** forward from today's AD:

1. **Deterministic projection** (16 days): forecast et0 and precipitation from the latest `weather_forecasts` row; canopy held or interpolated per §5.3; planned irrigation (below) included.
2. **Ensemble projection**: run the engine once per ensemble member (e.g. GFS ensemble ~31 members, ECMWF IFS ensemble ~51). Outputs per day: the 10th, 50th and 90th percentile of AD and **P(AD ≤ threshold)**, plus the first date where P ≥ `min_probability`.
   - *Spike in Phase 5:* confirm that daily et0 is available per ensemble member. If it isn't, use each member's precipitation with the deterministic et0 (precipitation is the dominant uncertainty), or compute member ET0 from member temperature, radiation and wind using FAO-56.
3. **Planned irrigation ("what-if")**: users can add future irrigation (date, inches) that is stored as `field_entries` on future dates and marked *planned* in the UI. The chart updates immediately. This is computed in the browser from a JSON payload of the resolved daily inputs, or through a small debounced projection endpoint; start with the server endpoint.
4. **Recommended irrigation**: the latest date to irrigate before crossing the target, and the inches needed to refill to field capacity (AD_max − AD). Shown in the field status summary.

Past days use `weather_days` (final or provisional), future days use forecasts, and the switch-over is drawn on the chart.

**As built (Phase 5, 2026-10-04):**
- **Today comes from the forecast.** `weather_days` holds only complete local days (before today), so today's et0 and rain come from the latest deterministic forecast (`WeatherDay.balance_inputs`, source `forecast` in the grid and tooltips). Before this, today's ET was gap-filled and its rain counted as missing. One balance run covers the season through the forecast; `PlantingStatus#forecast_days` are the days after today with forecast weather, up to the season's end.
- **Ensemble spike:** Open-Meteo's ensemble API returns `et0_fao_evapotranspiration` and `precipitation` for every member. GFS (`gfs_seamless`) has 31 members (control + 30) over the full 16 days with no gaps; ECMWF IFS (51 members) stops at 15 days and leaves gaps at the end. GFS is used. Members are fetched with each refresh (`Fetcher#refresh_ensemble`), and Open-Meteo counts each member as a variable, so a cell's ensemble costs about 7 calls per refresh.
- **Ensemble runner** (`EnsembleProjection`): each member runs from today's AD with its own et0 and, where the day's rain is modeled, its own rain; entered values (planned irrigation) are kept. Per day: P10/P50/P90 of AD, and the share of members at or below the threshold by then (cumulative).
- **Threshold:** the field's target if set, else AD = 0. `PlantingStatus#crossing` is the first day (today or ahead) the deterministic projection reaches it, with the refill to field capacity then. A field OK today that crosses within 3 days (`LEAD_DAYS`) is caution (§5.5).
- **Planned irrigation** is an irrigation entry on a future date (no separate table). A future day accepts only irrigation and notes. The field page has a "Next 15 days" table to plan it; a save reloads only the balance props, and the projection updates in about 200 ms (e2e, test server).

---

## 7. Authentication

- **Devise**, as in legacy: confirmable, recoverable, rememberable, trackable, timeoutable. Keep the existing `.ru` block, but enforce it as a proper `validate` method (it was in a `before_validation` callback). Keep the resend-confirmation flow from the last legacy commit.
- **One-time login links and codes**:
  - "Email me a code" on the login page sends a sign-in link and a six-digit code, then shows a "Check your email" page with a code box. The response is always neutral, so it never reveals whether an account exists. The code is for signing in on the device that asked when the email is read on another (as on AgWeather).
  - Token: `User.generates_token_for(:magic_login, expires_in: 15.minutes) { current_sign_in_at }`. Signing in changes `current_sign_in_at` (trackable), so each link works **once**, with no token table.
  - The link opens a confirmation page with a "Sign in" button (POST), so email link scanners that pre-fetch URLs can't use up the token.
  - Code: stored as an HMAC on `users` (`sign_in_code_digest`, `_sent_at`, `_attempts`). It shares the link's 15-minute lifetime, works once, is replaced by a newer request, dies after 5 wrong tries, and stops working after any sign-in. Only the address this browser asked about (kept in the session) can be checked.
  - Using a link or code confirms an unconfirmed email (it proves the user controls the inbox).
  - Rate limiting: 5 emails per address per hour and 20 per IP per hour, a 60-second resend cooldown (shown as a countdown, enforced per browser and per account), and 20 code tries per IP per 15 minutes (`WindowLimit`, fixed windows in `Rails.cache`, plus rack-attack). "Too many" messages say when to try again. Any successful sign-in lifts the per-address limit and the cooldown.
  - Email links carry `ses:no-track`, because the servers relay mail through Amazon SES, whose click tracking rewrites links.
- Devise controllers are subclassed to render Inertia pages (`Auth/SignIn`, `Auth/SignUp`, …). Mail templates are rewritten in plain HTML with a text version.
- **Authorization**: every query goes through `Current.group` (set from the session and checked against `current_user.groups`). Controllers never call `Model.find(params[:id])` unscoped; they use `Current.group.fields.find(...)`. Request specs check that requests for another tenant's records return 404 (§9, item S1).
- Admins: `users.admin` flag kept; admin area for the user list, CSV export, announcements, and impersonation (useful for support).

---

## 8. Weather: Open-Meteo integration

### 8.1 Client and configuration

`Weather::OpenMeteo` (app/services/weather):

- **Key:** `OPEN_METEO_API_KEY` (`.env` in development, loaded by dotenv) or credentials `open_meteo.api_key` on servers. With a key it uses the `customer-*` hosts (`customer-api`, `customer-historical-forecast-api`, `customer-archive-api`) with `&apikey=`; without one, the free hosts. The admin page shows which.
- **Requests:** hourly variables, metric units, `timezone=auto` (pivots can be anywhere in the US and Canada, so each cell's local day is used, not America/Chicago), up to 25 locations per request.
- **Rate limits:** `Weather::RateLimiter` counts calls the way Open-Meteo does (per location, ×variables/10 ×days/14) in `Rails.cache`, and keeps the free tier under 500/min, 4,500/h and 9,000/day (waits out a full minute; raises `RateLimited` for the hour or day and the job retries). With a key there are no client-side limits. 429s, 5xx and network errors are retried twice inline, then by the job.
- A `Weather::Provider` interface was not built: with one provider it would only be indirection. The fetcher is the seam if a second source appears.

### 8.2 Variables and models

Hourly variables (from Ben's R client, including cloud cover): temperature, dew point, relative humidity, ET0 (FAO-56), precipitation, rain, snowfall, snow depth, MSL pressure, VPD, wind speed, gusts and direction, cloud cover (total, low, mid, high); soil temperature and moisture at four depths. `Weather::Daily` aggregates them to local days (sums, means, extremes, a vector mean for wind direction), converts to inches/°F/mph, and leaves a value NULL when more than 2 of its day's hours are missing.

**Models (decided 2026-10-03 from the comparison, §8.4):** values come from a chain, each daily value from the first model that has it: **`ncep_nbm_conus` (NBM), then `best_match`** (`OPEN_METEO_MODELS` to change it). NBM matched AgWeather best for both ET and rain; it covers only the contiguous US and has no cloud cover, so best_match fills in (and covers Canada, Alaska, Hawaii). **Soil variables come from `ecmwf_ifs`**, the only model with them over North America (best_match, GFS and NBM return none).

### 8.3 Ingestion jobs (Solid Queue recurring, `config/recurring.yml`)

| Job | Schedule (CT) | Work |
|---|---|---|
| `WeatherRefreshJob` | 05:00, 11:00, 17:00 | For active cells (a planting this year or still running): the last 7 days (provisional `weather_days`) and a 16-day `weather_forecasts` row from the forecast API; then queues a backfill per cell. The admin page's "Refresh now" covers every cell with a pivot |
| `WeatherUpdateJob` | When a pivot gets a new cell, and when a page showing a cell's pivots is opened (dashboard, field, pivot, daily entry; `WeatherCell.keep_current`, at most every 15 min per cell) | One cell, active or not: a refresh if its latest forecast is over 3 hours old, then a backfill of any gaps |
| `WeatherBackfillJob` | After each refresh | Fills missing days from the cell's season start (or the last 30 days) through yesterday from the **historical-forecast API** (same models as the forecast, so the series is consistent); days older than a week are stored final |
| `WeatherFinalizeJob` | 03:00 | Days more than 7 days old become final; refreshes no longer overwrite them |
| `ForecastPruneJob` | Sundays 04:00 | Keep the latest 14 forecasts per cell |
| Ensemble refresh | — | Moved to Phase 5 with the projection that uses it |

Weather fetching **never** happens inside a web request (legacy fetched synchronously on page view, which is why fields nobody opened never got data); a page view only queues a `WeatherUpdateJob`. `bin/rails weather:refresh` runs a refresh and backfill by hand.

### 8.4 The AgWeather → Open-Meteo shift (validation task in Phase 3)

The reference-ET method differs: legacy used AgWeather's ET product (see `public/diakEtal1998.pdf` in the legacy repo); Open-Meteo uses FAO-56 Penman-Monteith. The A3600 percent-cover regressions were developed against the legacy reference ET. Phase 3 produces a comparison report: for the 2025 and 2026 seasons at real pivot locations, AgWeather ET and precipitation vs Open-Meteo (`best_match`, NBM), with season totals, daily bias and scatter, and the resulting difference in AD and irrigation trigger dates. **Exit criterion:** the shift is understood and documented. If there's a consistent bias, decide whether to apply a correction or document it for users.

The comparison uses AgWeather's public API (`bin/rails weather:compare`, report in `docs/weather-comparison.md`). It is not a runtime dependency, and no legacy data enters WISP 3 (D10).

**Result (2026-10-03; 12 points in Wisconsin's irrigated areas, 2025 and 2026 seasons):**
- **ET:** all models within a few percent of AgWeather: best_match +8%, NBM +2%, ECMWF IFS +3% (r 0.87–0.90).
- **Rain:** best_match is the outlier: 79% of AgWeather's total and 844 rain days against AgWeather's 1,425. NBM 93% (r 0.79), ECMWF 83%.
- **Effect on a standard potato field:** best_match calls for about **6 more irrigations a season** than AgWeather; NBM 1.5 fewer; ECMWF 0.4 fewer. All three Open-Meteo models put the **first irrigation 10–16 days earlier** than AgWeather, which needs a look (early-season ET or rain; TODO.md).
- **Decision:** NBM, with best_match as fallback (§8.2). No correction factor for now.
- **Still to do:** re-run at real pivot locations (`POINTS=file.csv`, TODO.md) before the beta.

### 8.5 Corrections to Open-Meteo (D12; from AgWeather v2, 2026-10-31)

**What AgWeather v2 found** (`../agweather2/docs/validation-openmeteo.md`, `scripts/compare_openmeteo_wisconet.py`; 80 Wisconet stations, 2025-01 to 2026-10, Open-Meteo's historical-forecast API at each station, `ncep_nbm_conus` then `best_match` merged hour by hour as WISP uses them):

| | Against the stations |
|---|---|
| Shortwave (daily totals) | NBM 1.15, best_match 1.20, every month (v2's corrected grid: 1.00) |
| ET0, April–October, against FAO-56 from the stations' own measurements (their pyranometers, temperature, humidity, 3 m wind, pressure; 3.02 mm a day) | **Open-Meteo's `et0_fao_evapotranspiration` (WISP's today) 1.156**; best_match's 1.220; FAO-56 from Open-Meteo's inputs 1.127; **the same with the shortwave corrected 1.032**; the old AgWeather API 1.114 (June–September 1.14–1.26, April–May 0.97, October 0.84) |
| RH, May–September | Open-Meteo counts 5.5 hours a day at RH ≥ 90% (best_match 4.9) against the stations' 7.8 and v2's grid's 7.2; RH bias −0.5 (best_match −2.9), MAE 6% (the grid's 3.8%) |
| Temperature | +0.16 °C (best_match +0.19), as v2's grid |

So WISP's ET runs about 16% above station FAO-56, and about 4% above the old API's, which the A3600 percent-cover regressions were fitted to (§5.4, §8.4). With the shortwave corrected, WISP's ET0 drops about 11% and sits about 7% below the old API's (Q9).

**What to apply, in order, as hours are aggregated to days (`Weather::Daily`):**

1. **Fetch** `shortwave_radiation` (W/m², the preceding hour's mean) and `surface_pressure` with the other hourly variables, from the same chain (NBM has no pressure: take best_match's, or FAO-56 eq. 7 from the cell's elevation).
2. **Shortwave**: `Rs × factor(clearness)`, clearness = the hour's Rs over FAO-56's clear-sky Rso for that hour (eq. 37, from Ra by eq. 28 over the hour ending at the stamp), the factor linear between the table's bins and held at its ends; hours with Rso ≤ 1 W/m² take clearness 0, so the darkest bin's factor (a dark hour's 0 stays 0; v2's code, 8E). Table v1 (`../agweather2/packages/agdata/src/agdata/data/openmeteo_shortwave_correction.json`):

   | Clearness | 0.05 | 0.15 | 0.25 | 0.35 | 0.45 | 0.55 | 0.65 | 0.75 | 0.85 | 0.95 | 1.05 | 1.15 |
   |---|---|---|---|---|---|---|---|---|---|---|---|---|
   | Factor | 0.62 | 1.09 | 0.91 | 0.85 | 0.83 | 0.84 | 0.86 | 0.88 | 0.90 | 0.90 | 0.87 | 0.62 |

   (Use the JSON's four-decimal values.) **The sun's hour angle must wrap to ±12 hours** around solar noon: with UTC hours plus longitude/15, a summer evening's solar time comes out below 0 h west of Greenwich, and v2 had Ra = 0 for the hour ending 01Z (19–20 CDT) until 2026-10-31. Its test: the 24 hourly Ra of a solar day sum to eq. 21's daily Ra at longitudes −122, −89.4, −75, 0 and 100.
3. **ET0**: FAO-56's hourly Penman-Monteith (eq. 53; since 2026-11-19 Rev.1's eq. 2.5a/2.5b, C24) from temperature, dew point, wind (10 m → 2 m by eq. 47), pressure and the corrected Rs, with G = 0.1 Rn by day and 0.5 Rn at night and the cloudiness ratio Rs/Rso carried from the last hour the sun was high enough; summed over the local day. Port `agmodels.weather.et0_hourly_series` (`../agweather2/packages/agmodels/src/agmodels/weather.py`) with its tests (FAO-56 Example 19). Open-Meteo's own `et0_fao_evapotranspiration` stops feeding the water balance and is kept beside it as the raw value.
4. **RH** (shown in the weather panels and charts, the digest and alert emails; not in the water balance): each hour's RH, from Open-Meteo's temperature and dew point, through a quantile map by season and solar hour onto v2's grid's RH; the dew point recomputed from it with the temperature kept (invert eq. 11/14), RH again from both. The map (`openmeteo_rh_map.json`, v1): `map[season][0][solar hour][RH 0…100]` → mapped RH, linear in RH, blended between the two nearest solar-hour bins (centred on h + 0.5) and the two nearest seasons by day of year (centres 15, 105, 196, 288, around the year's end); solar hour = (UTC hour + longitude/15) mod 24 at the hour's end. v2's `agdata.calibration.map_rh` is the reference implementation. WISP shows `relative_humidity_2m` today; take RH from T and Td instead, as the map was fitted on that (they differ by under 0.5% on average).
5. **Times**: WISP asks for `timezone=auto`, so stamps are local; the corrections need each hour's UTC end (from the response's `utc_offset_seconds`) and the cell's longitude.

**Transparency:**
- Keep the raw values: `weather_days` gains `et0_openmeteo_in`, `dew_point_raw_f`, `rh_mean_raw_pct`, `rh_min_raw_pct`, `rh_max_raw_pct` and `shortwave_raw_mj` beside the corrected columns (and `shortwave_mj` itself, which WISP doesn't store yet), and a `corrections` column (jsonb, e.g. `["openmeteo-shortwave v1", "openmeteo-rh v1", "et0-fao56 v1"]`), so a day says what it went through and a table's new version is visible.
- The tables live in `db/reference/weather_corrections/` as copied from AgWeather v2, each with its `version`, `fitted` and `source`, and a README naming the v2 commit they came from. Later, v2's API can serve them (`/api/v2/corrections`), and WISP reads the current ones.
- A corrections table on the About page (and in the admin weather page), generated from the reference files, as v2's `docs/corrections.md` is generated from `agdata.corrections`: source, variable, method, fitted against, version, fitted date, evidence.
- Weather CSV exports list the corrections in their frontmatter, and the chart tooltips say "corrected" with a link to the About page's table.

**Not yet covered:** the ensemble projection's ET0 (`gfs_seamless` members' `et0_fao_evapotranspiration`, Phase 5) wasn't checked; ask the ensemble for `shortwave_radiation`, `surface_pressure` and the rest and compute ET0 the same way, or scale each member's ET0 by the deterministic run's corrected/raw ratio (Q10). The tables were fitted in Wisconsin; pivots elsewhere get them until other mesonets are compared (v2 Phase 9).

---

## 10. Testing strategy

- **Engine unit tests**: every formula in §5, band boundaries in the percent-cover table, clamps, observation resets, gap fill, canopy interpolation edge cases (no observations, a single observation, observation before emergence, after harvest).
- **Golden tests against legacy**: a script in the legacy app exports about 30 representative 2026 fields as anonymized JSON fixtures (FC, PWP, MRZD, MAD, daily ref_et, rain, irrigation, entered moisture, entered cover) along with the legacy AD series. Include percent-cover and LAI fields, observation resets and field groups. The fixtures live in `spec/fixtures/legacy/`; there is no database link to legacy. Run the new engine on the same inputs. Assert AD matches within 0.001 in, **except** on days affected by known fixes C2, C3, C7 and C8, which are listed and explained in the test output. This is how we show the port is faithful.
- **Property tests** (simple randomized loops): AD always within [AD_pwp, AD_max]; water balance holds (Σ inputs − Σ ET − Σ DD = ΔAD, ignoring resets).
- **Weather client**: WebMock fixtures recorded from real Open-Meteo responses (free and customer hosts); unit conversion; timezone; 429 backoff.
- **Request specs**: tenancy isolation for every controller (S1), auth flows including magic links (single use, expiry, scanner-safe POST).
- **Frontend**: Vitest for chart-data transforms and the editable grid; Playwright smoke tests: sign up → confirm → create farm/pivot/field → enter irrigation → see the projection update.
- **CI**: GitHub Actions with Postgres service, RSpec, Vitest, Standard, `svelte-check`, Playwright (headless).

---

## 11. UI / pages

| Page | Contents |
|---|---|
| **Dashboard** (replaces Farm Status) | Card or list per field: status color, AD today, days until the target is crossed (with ensemble probability), last rain and irrigation, sparkline. Filter by farm |
| **Map** (Phase 7) | Its own tab after Dashboard. Pivots drawn to scale as circles or arcs, filled with the most urgent field's status, with each field's badge at the center; click opens a popup with the fields' cards. Fit-all, my location, basemap toggle, optional overlays (radar, observed and forecast rain, drought). Pivot locations are set in setup with the picker |
| **Field status** | Main chart (below), summary box (AD, % moisture, status, recommended irrigation and timing), editable daily grid (date, rain, irrigation, moisture obs, cover obs, notes, with provenance badges), what-if planned irrigation, CSV export |
| **Setup** | Farms → pivots → fields → plantings as nested, inline-editable lists (replaces the jqGrid setup pages). "Copy last season's plantings" action |
| **Field groups** | Create a group, pick fields, enter shared daily values in the same grid component |
| **Daily entry (bulk)** | One date, whole farm: rows are pivots (one irrigation cell per pivot, inches or run hours) that expand to their fields for per-field rain, overrides and observations. Fast entry after a rain or irrigation day |
| **Settings / account** | Profile, password, units (in/mm), alert preferences, group switcher/invites |
| **Admin** | Users, CSV, announcements, weather status (last fetch per cell, API mode, error counts), impersonate |
| **Public** | Landing page, about/methods (from the architecture doc), user guide PDF, announcements |

### Field status chart (ECharts)

- X axis: season dates; default view about 21 days back + 16 days forward, zoomable to the full season.
- Small multiples sharing the date axis (no second y axis): AD on top; water in below it; the running totals of rain and irrigation over the days in view (as the weather precipitation chart); the crop canopy (percent cover or LAI) at the bottom.
- Water in: rain (blue) and irrigation (orange) stacked, planned irrigation hatched, and modeled rain the balance didn't use as a dashed outline beside the rain (replaced by an entry, or left out on a field using only entered rain).
- Canopy (green): the balance's daily value, interpolated between readings, with a dot for each reading.
- Deep drainage: AD never rises above field capacity (the excess drains that day), so each day's drainage is a purple area stacked on the field capacity line, as high as the depth drained.
- Legend: one entry per measure (AD with its forecast and range; deep drainage; rain with modeled rain and totals; irrigation with planned and its total; canopy with its readings). Thresholds, today and forecast shading stay whatever is hidden.
- Line: AD (inches) observed (solid) → deterministic projection (dashed).
- Band: ensemble P10–P90 for future days.
- Horizontal lines: AD_max (field capacity), target, 0 (MAD trigger), AD_pwp (wilting point).
- `markArea` shading for the forecast region; marker on today.
- Optional toggle to show % soil moisture instead of AD inches.
- Tooltip: all resolved inputs for the day with provenance.

---

## 12. Deployment and operations

- **Hosts**: staging (dev.wisp.cals.wisc.edu, existing box; `systemd --user` and linger confirmed) and **production in AWS** (D11), set up by CALS IT in October 2026: an EC2 server (`wisp-prod`, Ubuntu 26.04, t3.medium), and RDS PostgreSQL 18 (db.t4g.small) in us-east-1 (IT also made an ECR repository and SSM Parameter Store, unused since 2026-10-29). Details and steps are in `docs/deployment.md`.
- **Staging**: Capistrano + rbenv, same workflow as legacy. nginx → Puma, with Puma and Solid Queue run as `systemd --user` units owned by `deploy` (`wisp3-web`, `wisp3-jobs`; Puma on 127.0.0.1:3100), restarted by Capistrano hooks without sudo.
- **Production**: Docker Compose (`config/deploy/compose.production.yaml`). `bin/production deploy` checks out the commit on the server from GitHub, builds its image there (`Dockerfile`: Ruby with YJIT, the Vite build, no Node at runtime; tagged with the commit and `wisp3:deployed`), runs `db:prepare db:seed` and replaces the `web` (Thruster on 80/443 with Let's Encrypt, in front of Puma) and `jobs` containers. Rolling back is deploying an earlier commit; the newest 5 images stay on the server.
- **Database**: staging, Postgres on the host. Production, RDS (`wisp3_production`, `_cache`, `_queue`, owned by the `wisp3` role), reachable only from the server, TLS verified against the RDS bundle in the image. RDS keeps 14 days of automated backups with point-in-time restore, which replaces the nightly `pg_dump`; test a restore once before launch.
- **Secrets**: staging, Rails credentials. Production, the server's `/opt/wisp/.env`, edited by hand and backed up in the password manager; its Rails credentials hold only `secret_key_base` (key in `.env` as `RAILS_MASTER_KEY`).
- **Mail**: staging uses the host's sendmail (Postfix relaying through SES). The production container has no sendmail and EC2 blocks port 25, so production sends through Amazon SES's SMTP interface on 587 (`SMTP_ADDRESS` etc. in `.env`; CALS IT asked for SES rather than the CALS relay, 2026-10-30). Before alerts launch, confirm SPF and DKIM for the sender domain with campus IT. Add `List-Unsubscribe` and one-click unsubscribe to alert emails. *Status 2026-11-07: SES is configured, but the test send fails with `554` because the account is still in the SES sandbox; waiting on production access (`docs/deployment.md` step 7).*
- **DNS** (done 2026-11-19): `wisp.cals.wisc.edu` points at the EC2 server, legacy moved to `old.wisp.cals.wisc.edu` (§13), and the temporary `v3.wisp.cals.wisc.edu` was removed.
- **Monitoring**: a `/up` health check; an admin weather-status page; a daily job summary emailed to admins when any job fails or a cell's data is more than 24 h stale. Optional: an error tracker such as Honeybadger or Sentry.
- **Staging**: dev.wisp.cals.wisc.edu runs WISP 3 from Phase 1 onward, so legacy has no staging server. Legacy production stays on its own box, at `old.wisp.cals.wisc.edu`, until it's deleted on December 31, 2027.

---

## 13. Launch without data migration (D10)

Users start fresh in WISP 3. That removes the riskiest part of the project (the legacy data mixes entered and upstream values in the same columns, and half the pivot locations are placeholders), but it moves the effort to onboarding:

- **Fast setup.** Getting from a new account to a working field takes one form per level, with sensible defaults, and the pivot map picker in the setup flow (Phase 4, not Phase 7). Target: a two-field pivot set up in under 5 minutes. Tested in the beta.
- **Announcement email** (at launch, November 2026, with a training session) to confirmed legacy users, sent from the legacy app (it already has the addresses): what's new, the new address, "please create a new account", a link to a short setup video or guide, and a note about sign-in links.
- **Legacy stays readable until December 31, 2027** (Ben, 2026-11-19: through the 2027 season), at `old.wisp.cals.wisc.edu`:
  - Sign-ups go to WISP 3, and a banner on every page says it's deleted at the end of 2027 and links to WISP 3 (`config/initializers/retirement.rb` in legacy).
  - Growers can still look up and export their 2026 data (the CSV export already exists).
  - Delete it on December 31, 2027, keeping an archived `pg_dump`.
- **Legacy data used offline only:**
  - Anonymized golden-test fixtures (§10).
  - The AgWeather comparison export (§8.4).
  - Production usage numbers (§15).
  - There is no deadline pressure: the Feb 15 wipe is disabled, but still take one `pg_dump` after Nov 30 as an archive.

---

## 14. Phased execution

Planned as phases 0–9; the record is now regrouped by theme in the phase files beside this one ([README.md](README.md) maps the old numbers). Calendar assumed one primary developer, Oct 2026 → Mar 2027, each phase ending deployed to staging. Checklists: `[x]` done, `[ ]` open, `[~]` deferred or folded into another item (its note says where).
