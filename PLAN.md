# WISP 3 — Rewrite Plan

A full rewrite of the Wisconsin Irrigation Scheduling Program (WISP), replacing the legacy app at `../wisp`. Target: running in production before **April 1, 2027** (start of the 2027 season), with the October–March off-season used for build, validation, and beta.

---

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

## 2. Recorded decisions

| # | Decision |
|---|----------|
| D1 | **Rails 8 + Inertia.js + Svelte 5 + Tailwind CSS v4**, built with Vite |
| D2 | **Fresh app in this directory (`wisp3`)**; legacy code is ported selectively and every ported method is audited (see §9) |
| D3 | **Keep all seasons**; no yearly wipe. Season setup is copied forward instead |
| D4 | Devise email/password stays; **add one-time login links** |
| D5 | Phased delivery. All phases (including alerts and map) target the 2027 launch, with time left for polish |
| D6 | **Retire AgWeather entirely.** Open-Meteo is the only weather source, behind a provider interface |
| D7 | Open-Meteo **commercial API key is optional config**; without it, the free endpoints are used |
| D8 | **LAI method is kept**, pending the agronomy review in Q2 |
| D9 | **Pivot-level irrigation entry**: irrigation entered once on a pivot applies to every field under it (or a chosen subset), with per-field overrides (§4) |
| D10 | **No data migration.** Users register and set up their farms fresh in WISP 3. Legacy data is used only offline, for engine validation (§10) and the weather comparison (§8.4) |
| D11 | **New production server** for the 2027 season. Provisioned by CALS IT in AWS (EC2, RDS; October 2026) and deployed with Docker, images built on the server (Ben, 2026-10-29: ECR, SSM and SES dropped, as they needed AWS permissions IT was slow to grant); staging stays on Capistrano (§12). The old production box is out of scope |
| D12 | **Open-Meteo's shortwave and humidity are corrected against ground stations, and ET0 is computed here from the corrected shortwave** (Ben, 2026-10-31, from AgWeather v2's comparison with 80 Wisconet stations): its shortwave reads 15–20% high, so its ET0 reads 16% high; its RH runs dry. Each correction is a versioned table copied from AgWeather v2, applied as hours are aggregated, with the raw values kept and the corrections applied recorded on each day (§8.5) |
| D13 | **AGPL-3.0-or-later** (Ben, 2026-10-31), as AgWeather v2 (its D53): anyone who distributes a modified version, or runs one for others over a network, must offer its source. Copyright the Board of Regents of the University of Wisconsin System (`LICENSE`, README, `package.json`). Open-Meteo's data is CC BY 4.0, so the about page credits it | 2026-10-31 |

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
                          │           ├──< PivotIrrigation (date, inches | run hours, fields applied to)
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
- **pivots**: `name, kind, latitude, longitude, radius_ft, arc_start_deg, arc_end_deg (nullable = full circle), length_ft, travel_ft, travel_bearing_deg, equipment, pump_capacity_gpm, notes`.
  - **Kind** (Phase 7 I): `center` (a circle, or an arc for a partial circle, around its location) or `linear` (a linear move: a machine `length_ft` long traveling `travel_ft` along `travel_bearing_deg`, an integer 0–179 from north since it runs both ways; a rectangle centered on its location). Each kind keeps only its own dimensions. Size limits, in the model, the database and the picker: a center pivot's radius at most 3,000 ft (the longest sold are about 2,900 ft); a linear machine at most 3,300 ft long (the longest about 3,200 ft) and its travel at most a mile.
  - **Location is required and has no default.** In legacy production, 215 of 443 pivots (49%) were still at the default 43, −89, so half of all fields got weather for the wrong place.
  - Pivot creation therefore starts with a map picker (click the pivot center, drag the radius) or typed coordinates, validated to fall within a US-and-Canada bounding box (latitude 18–84, longitude −180 to −52). Weather coverage is global, so this can widen later.
- **fields**: `name, area_acres, soil_type_id, field_capacity, perm_wilting_pt` (nullable, so NULL means "use the soil type default"; the legacy code used 0.0 for that), `notes`, optional `boundary` (GeoJSON jsonb) for non-pivot or partial areas, `use_model_precip` (nullable boolean, Phase 6.6: NULL follows the group's setting; true or false overrides it for this field).
- **plantings**: `field_id, plant_id, variety, season_start (default Apr 1), emergence_date, end_date (harvest/kill, default Nov 30), max_root_zone_depth, mad_frac, et_method (pct_cover | lai), target_ad_pct, initial_moisture_pct (nullable, NULL = start at field capacity), notes`. The season year is `season_start.year` (no separate column to disagree with it). Plantings on the same field can't overlap in time (model validation plus a Postgres exclusion constraint). This supports double-cropping properly (replacing the legacy `current_crop` "latest emergence" hack). Emergence may precede `season_start` (perennials).
- **canopy_observations**: `planting_id, date, pct_cover (0–100) | lai (≥0)`. These are anchor points for interpolation (§5.3).
- **field_entries**: `field_id, date, rain_in, irrigation_in, soil_moisture_pct, notes`. All nullable, NULL = not entered, **0.0 = user entered zero** (removes the legacy `CHANGE_EPSILON` workaround). Unique on `(field_id, date)`.
- **field_group_entries**: the same columns, keyed on `(field_group_id, date)`. These apply to member fields **when read**, not copied in on save.
- **pivot_irrigations** (D9): `pivot_id, date, inches, run_hours, field_ids (bigint[], NULL = every field under the pivot), notes`. Unique `(pivot_id, date)`.
  - **Use case:** a pivot is often split into 2 fields (two crops, or two varieties of one crop) that get the same water. The grower enters the irrigation once on the pivot instead of once per field.
  - **Legacy production:** 53 of 443 pivots had 2 or more fields; 34 had 2, and one had 7. The "applies to" picker must handle 7+ fields cleanly (checkbox list, all checked by default).
  - **Applied when read, not copied** into each field. Editing or deleting the pivot entry updates every field at once, and a per-field entry still wins for days when one field got a different amount (end-gun off, a sector skipped).
  - **Run hours instead of inches:** if only `run_hours` is given, inches are calculated as `pump_capacity_gpm × run_hours × 60 / (27,154 × irrigated acres)`, where irrigated acres is the sum of `area_acres` over the fields it applied to. This needs pump capacity and field areas; if they are missing, the form asks for inches. (27,154 gallons = 1 acre-inch.)
  - **UI:** the pivot's daily row shows one irrigation cell; each field's grid shows the value with a "from pivot" badge and an override.
- **weather_cells**: `latitude, longitude` of an ECMWF IFS O1280 grid cell center (~9 km; `Weather::Grid`, ported from Ben's R client), plus `timezone` and `elevation_m` from Open-Meteo and the last fetch/error. Pivots get their cell when created or moved (`pivots.weather_cell_id`), which queues a backfill. Requests go to the cell center, so every pivot in a cell shares one series.
- **weather_days**: `weather_cell_id, date`, daily values built from hourly data in the cell's local day: `et0_in, precip_in, rain_in, snowfall_in, snow_depth_in, tmax_f, tmin_f, tmean_f, dew_point_f, rh_mean/min/max_pct, vpd_max_kpa, pressure_msl_hpa, wind_speed(_max)_mph, wind_gust_max_mph, wind_direction_deg, cloud_cover(_low/_mid/_high)_pct`, soil temperature (°F) and moisture (m³/m³, comparable with field capacity) at 0–7, 7–28, 28–100 and 100–255 cm; `model, soil_model, hours, fetched_at, final`. Unique `(cell, date)`. Missing values are **NULL**, never 0.
- **weather_forecasts**: `weather_cell_id, issued_at, model, kind (deterministic|ensemble), payload jsonb` (deterministic: `{"days": [{date, <weather_days columns>}, …]}`; ensemble: `{"dates": [...], "members": [{"et0_in": [...], "precip_in": [...]}, …]}`, one entry per member). Keep the most recent 14 issues of each kind per cell for later checks of forecast accuracy, and prune older ones.
- **users** (beyond Devise columns): `first_name, last_name, admin, unit_system (imperial|metric, default imperial)`.
- **Daily digest** (Phase 6, replacing event-based alerts; decided 2026-10-04): `users.digest_frequency` (`never | daily | needed`, default never since 2026-10-07; changed from an on/off switch 2026-10-05), `users.digest_sent_on` (so a rerun of the job doesn't send twice) and `users.digest_test_sent_at` (the test email's 5-minute cooldown). **digest_exclusions**: `user_id, subject (Group | Farm | Field)`, unique. Every field in the user's operations is covered unless it, its farm or its operation is excluded; saving the settings leaves out a farm or operation whole when none of its fields are picked, so fields added there later stay out, and otherwise excludes single fields, so new ones join.

### Precedence when resolving a day's inputs for a field

```
rain       = field_entry.rain_in ?? group_entry.rain_in ?? (use_model_precip || date > today ? weather.precip_in : 0.0)
             where use_model_precip = field.use_model_precip ?? group.use_model_precip   (Phase 6.6; Q7)
irrigation = field_entry.irrigation_in ?? pivot_irrigation.inches (if this field is included) ?? group_entry.irrigation_in ?? 0.0
et0        = weather.et0_in            (NULL → gap fill, §5.4)
moisture   = field_entry.soil_moisture_pct ?? group_entry.soil_moisture_pct   (resets balance, §5.2)
canopy     = interpolated from canopy_observations (§5.3); group pct-cover entries become CanopyObservations on each member planting
```

A pivot entry outranks a field-group entry because it describes water that physically reached that field; field groups are a convenience for shared data entry.

Every resolved value carries a **provenance tag** (`entered`, `pivot`, `group`, `model`, `forecast`, `gap_fill`) that the UI shows, replacing the legacy "E" suffix.

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
3. **ET0**: FAO-56's hourly Penman-Monteith (eq. 53) from temperature, dew point, wind (10 m → 2 m by eq. 47), pressure and the corrected Rs, with G = 0.1 Rn by day and 0.5 Rn at night and the cloudiness ratio Rs/Rso carried from the last hour the sun was high enough; summed over the local day. Port `agmodels.weather.et0_hourly_series` (`../agweather2/packages/agmodels/src/agmodels/weather.py`) with its tests (FAO-56 Example 19). Open-Meteo's own `et0_fao_evapotranspiration` stops feeding the water balance and is kept beside it as the raw value.
4. **RH** (shown in the weather panels and charts, the digest and alert emails; not in the water balance): each hour's RH, from Open-Meteo's temperature and dew point, through a quantile map by season and solar hour onto v2's grid's RH; the dew point recomputed from it with the temperature kept (invert eq. 11/14), RH again from both. The map (`openmeteo_rh_map.json`, v1): `map[season][0][solar hour][RH 0…100]` → mapped RH, linear in RH, blended between the two nearest solar-hour bins (centred on h + 0.5) and the two nearest seasons by day of year (centres 15, 105, 196, 288, around the year's end); solar hour = (UTC hour + longitude/15) mod 24 at the hour's end. v2's `agdata.calibration.map_rh` is the reference implementation. WISP shows `relative_humidity_2m` today; take RH from T and Td instead, as the map was fitted on that (they differ by under 0.5% on average).
5. **Times**: WISP asks for `timezone=auto`, so stamps are local; the corrections need each hour's UTC end (from the response's `utc_offset_seconds`) and the cell's longitude.

**Transparency:**
- Keep the raw values: `weather_days` gains `et0_openmeteo_in`, `dew_point_raw_f`, `rh_mean_raw_pct`, `rh_min_raw_pct`, `rh_max_raw_pct` and `shortwave_raw_mj` beside the corrected columns (and `shortwave_mj` itself, which WISP doesn't store yet), and a `corrections` column (jsonb, e.g. `["openmeteo-shortwave v1", "openmeteo-rh v1", "et0-fao56 v1"]`), so a day says what it went through and a table's new version is visible.
- The tables live in `db/reference/weather_corrections/` as copied from AgWeather v2, each with its `version`, `fitted` and `source`, and a README naming the v2 commit they came from. Later, v2's API can serve them (`/api/v2/corrections`), and WISP reads the current ones.
- A corrections table on the About page (and in the admin weather page), generated from the reference files, as v2's `docs/corrections.md` is generated from `agdata.corrections`: source, variable, method, fitted against, version, fitted date, evidence.
- Weather CSV exports list the corrections in their frontmatter, and the chart tooltips say "corrected" with a link to the About page's table.

**Not yet covered:** the ensemble projection's ET0 (`gfs_seamless` members' `et0_fao_evapotranspiration`, Phase 5) wasn't checked; ask the ensemble for `shortwave_radiation`, `surface_pressure` and the rest and compute ET0 the same way, or scale each member's ET0 by the deterministic run's corrected/raw ratio (Q10). The tables were fitted in Wisconsin; pivots elsewhere get them until other mesonets are compared (v2 Phase 9).

---

## 9. Legacy audit: bugs and dispositions

Every ported method is checked against this list. Items marked **Hotfix** should also be patched in the legacy app now (Phase 0), because it is live through Nov 30.

### Security

| ID | Legacy issue | Where | Disposition |
|---|---|---|---|
| S1 | **Unscoped record lookups.** Any signed-in user can read or modify other users' data by ID: `FieldDailyWeather.find(params[:id])` + update, `Field.find`, `Pivot.find`, `Farm.find`, `Crop.find`, `Field.find` in `projection_data` / `set_field`, and the generic `get_and_set` | `field_daily_weather_controller.rb:99`, `fields_controller.rb:41,72`, `pivots_controller.rb:22,26,42,45,64`, `farms_controller.rb:67`, `crops_controller.rb:2,37`, `wisp_controller.rb:15,148,199,214,271-273`, `application_controller.rb:45,65` | **Hotfix** in legacy: scope through `current_group`. WISP 3: `Current.group` scoping + cross-tenant request specs |
| S2 | `before_validation` used to add the `.ru` email error | `user.rb` | Use a real `validate` |

### Correctness

| ID | Legacy issue | Where | Disposition |
|---|---|---|---|
| C18 | **Sweet corn under LAI gets negative ET.** `fake_lai_thermal` is a quadratic in *cumulative* degree-days (positive from 96 to 2,337 GDD), but it is fed *daily* degree-days (5–35), so LAI is −0.4 to −0.6 and adjusted ET is −0.19 to −0.35 in/day: the model adds water every day. If degree-days haven't been fetched, LAI is nil and the field gets no ET at all | `sweet_corn.rb`, `et_calculator.rb#lai_thermal` | Verified numerically. Legacy production has **1** sweet corn + LAI field. The season is over and no data is migrated, so no legacy hotfix; optionally tell that grower their 2026 balance was wrong. WISP 3: Q2 |
| C1 | **Rainfall toggle inverted**: when "Auto" is checked (`precip_use_agwx=true`) the fetch is skipped | `field.rb:301-305` | **Hotfix** (`unless`). WISP 3: `use_model_precip`, default true |
| C2 | Observation reset capped at TAW instead of AD_max; drainage never recorded; no PWP floor | `field_daily_weather.rb` `old_update_balances`, `set_ad_from_calculated_moisture` | Fixed in §5.2 |
| C3 | Percent cover only carried forward 6 days after the last entry; it then falls to 0 or a stale value. Slicing past the end of the season can raise an error | `field.rb` `pct_cover_changed` | Fixed in §5.3 |
| C4 | LAI method uses the corn curve for every crop; sweet corn uses a placeholder quadratic; when emergence moves later, pre-emergence LAI isn't reset | `plant.rb`, `sweet_corn.rb`, `et_calculator.rb`, `field.rb#update_canopy` | LAI limited to field corn (§5.3) |
| C5 | Zero used as "missing" for `ref_et`; a rain value entered as zero is stored as `0.00001` | `field_daily_weather_controller.rb`, `weather_station_data.rb` | NULL = missing everywhere |
| C6 | `ref_et` NULL raises `NoMethodError` in the balance loop | `old_update_balances` | NULL-safe engine |
| C7 | Gap-fill values fed back into the ring buffer; gap fill also used for **all future days** (the straight-line projection) | `field.rb#do_balances` | §5.4 + §6 |
| C8 | Bare-soil ET bins have gaps (`0..0.159`, `0.160..0.319`); negative cover treated as full cover | `et_calculator.rb#adj_et_pct_cover` | §5.4 |
| C9 | Upstream weather is only stored if the current value is 0/nil, so later revisions of provisional data are never picked up | `field.rb#get_et/get_precip` | Re-fetch until `final` (§8.3) |
| C10 | `current_crop` = latest emergence; reloads on every call; single crop per field-year | `field.rb` | `Planting` with date ranges |
| C11 | `field_status` uses min/max dates across **all** fields | `wisp_controller.rb` | Per-planting date ranges |
| C12 | Field-group values copied into fields on save; later edits sometimes not propagated, by design | `weather_station.rb`, `weather_station_data.rb` | Resolved at read time with a clear precedence (§4) |
| C13 | Problem detection ignores `target_ad_pct`; can raise an error when AD is nil | `field.rb#problem` | §5.5 |
| C14 | 0.0 field capacity / PWP treated as "use the soil default" | `field.rb` | NULL = default; validation |
| C15 | `Crop#initial_soil_moisture` shadows the column (always FC) | `crop.rb` | `initial_moisture_pct`, nullable, meaningful |
| C16 | `max_adj_et_in_past_week` calls `size(-1)` (would raise) | `field.rb` | Dead code; not ported |
| C17 | Server-local `Date.today` / `Time.now` | throughout | `config.time_zone = "Central Time (US & Canada)"`, `Date.current` |
| C19 | On a soil moisture reading day, adjusted ET isn't recomputed: the value stored by an earlier run (often from older canopy or weather) is kept and fed into the gap-fill buffer. Found by the golden tests (2 of 12 active fixture fields) | `old_update_balances` | ET computed fresh every day |
| C20 | **No canopy without readings.** A percent cover planting with no readings had 0% cover all season (bare-soil ET only), and between readings cover followed straight lines | `field.rb` canopy interpolation | WISP 3: a default canopy curve per crop, followed with no readings and through readings (Phase 6.7, `CanopyCurve`, `Canopy`); a planting can choose straight lines. A canopy-series change, so `LegacyEngine::CANOPY_FIXES` lists it and `legacy_engine_spec` is unaffected |

### Architecture and performance

| ID | Legacy issue | Disposition |
|---|---|---|
| A1 | `@@do_balances` class variable toggled globally (not thread-safe under Puma) | Gone; no callbacks |
| A2 | GET `field_status` rewrites about 244 rows via `do_balances` | Calculated when read; GETs don't write |
| A3 | Weather HTTP calls inside requests (5 s timeout × 3) | Background jobs only |
| A4 | Feb 15 `yearly:reset` deletes all history | Removed; seasons kept |
| A5 | Pivot default location 43, −89 silently used for weather (215 of 443 production pivots never changed it) | Location required at creation, map picker (§4) |
| A6 | Dead code: `IrrigationEventsController` (no routes), `RingBuffer#mean/max` unused paths, `ApplicationController.jsonify`, `check_pivots_for_cloning` | Not ported. The idea behind the unused `irrigation_events` table comes back as `pivot_irrigations` (D9) |
| A7 | Google `jsapi` legacy loader, jqGrid, jQuery UI, CoffeeScript | Replaced (§3) |
| A8 | `current_group` = `groups.first`; group sharing effectively unsupported | Group switcher + invitations (Phase 8 stretch) |

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

- **Hosts**: staging (dev.wisp.cals.wisc.edu, existing box; `systemd --user` and linger confirmed) and **production in AWS** (D11), set up by CALS IT in October 2026: an EC2 server (`wisp-prod`, Ubuntu 26.04, t3.medium), and RDS PostgreSQL 18 in us-east-1 (IT also made an ECR repository and SSM Parameter Store, unused since 2026-10-29). Details and steps are in `docs/deployment.md`.
- **Staging**: Capistrano + rbenv, same workflow as legacy. nginx → Puma, with Puma and Solid Queue run as `systemd --user` units owned by `deploy` (`wisp3-web`, `wisp3-jobs`; Puma on 127.0.0.1:3100), restarted by Capistrano hooks without sudo.
- **Production**: Docker Compose (`config/deploy/compose.production.yaml`). `bin/production deploy` checks out the commit on the server from GitHub, builds its image there (`Dockerfile`: Ruby with YJIT, the Vite build, no Node at runtime; tagged with the commit and `wisp3:deployed`), runs `db:prepare db:seed` and replaces the `web` (Thruster on 80/443 with Let's Encrypt, in front of Puma) and `jobs` containers. Rolling back is deploying an earlier commit; the newest 5 images stay on the server.
- **Database**: staging, Postgres on the host. Production, RDS (`wisp3_production`, `_cache`, `_queue`, owned by the `wisp3` role), reachable only from the server, TLS verified against the RDS bundle in the image. RDS keeps 14 days of automated backups with point-in-time restore, which replaces the nightly `pg_dump`; test a restore once before launch.
- **Secrets**: staging, Rails credentials. Production, the server's `/opt/wisp/.env`, edited by hand and backed up in the password manager; its Rails credentials hold only `secret_key_base` (key in `.env` as `RAILS_MASTER_KEY`).
- **Mail**: staging uses the host's sendmail (Postfix relaying through SES). The production container has no sendmail and EC2 blocks port 25, so production sends through Amazon SES's SMTP interface on 587 (`SMTP_ADDRESS` etc. in `.env`; CALS IT asked for SES rather than the CALS relay, 2026-10-30). Before alerts launch, confirm SPF and DKIM for the sender domain with campus IT. Add `List-Unsubscribe` and one-click unsubscribe to alert emails. *Status 2026-11-07: SES is configured, but the test send fails with `554` because the account is still in the SES sandbox; waiting on production access (`docs/deployment.md` step 7).*
- **DNS**: decide the hostname switch at launch: `wisp.cals.wisc.edu` moves to the EC2 server; legacy moves to e.g. `legacy.wisp.cals.wisc.edu` (§13). Until then production runs under a temporary hostname.
- **Monitoring**: a `/up` health check; an admin weather-status page; a daily job summary emailed to admins when any job fails or a cell's data is more than 24 h stale. Optional: an error tracker such as Honeybadger or Sentry.
- **Staging**: dev.wisp.cals.wisc.edu runs WISP 3 from Phase 1 onward. The legacy app stays on the old production box until launch.

---

## 13. Launch without data migration (D10)

Users start fresh in WISP 3. That removes the riskiest part of the project (the legacy data mixes entered and upstream values in the same columns, and half the pivot locations are placeholders), but it moves the effort to onboarding:

- **Fast setup.** Getting from a new account to a working field takes one form per level, with sensible defaults, and the pivot map picker in the setup flow (Phase 4, not Phase 7). Target: a two-field pivot set up in under 5 minutes. Tested in the beta.
- **Announcement email** (late March) to confirmed legacy users, sent from the legacy app (it already has the addresses): what's new, the new address, "please create a new account", a link to a short setup video or guide, and a note about sign-in links.
- **Legacy stays readable for one season**, on `legacy.wisp.cals.wisc.edu` (or similar) after the DNS switch:
  - Sign-ups are disabled, and a banner points to WISP 3.
  - Growers can still look up and export their 2026 data (the CSV export already exists).
  - Shut it down after the 2027 season, keeping an archived `pg_dump`.
- **Legacy data used offline only:**
  - Anonymized golden-test fixtures (§10).
  - The AgWeather comparison export (§8.4).
  - Production usage numbers (§15).
  - There is no deadline pressure: the Feb 15 wipe is disabled, but still take one `pg_dump` after Nov 30 as an archive.

---

## 14. Phased execution

Calendar assumes one primary developer, Oct 2026 → Mar 2027. Each phase ends deployed to staging.

### Phase 0: Legacy housekeeping

Code committed on branch `phase0-hotfixes` in `../wisp` (`1abdb8f`, 268 specs passing). Push, deploy and the backfill remain.

- [x] Hotfix S1: every lookup driven by params or session goes through `current_group` (`ApplicationController#group_scope`); `spec/requests/tenant_isolation_spec.rb` (29 cross-tenant cases; 20 failed before the fix).
- [x] Hotfix C1: `Field#get_precip` condition corrected, with model specs.
- [x] `rake precip:backfill` (`DRY_RUN=1` to preview): refills AgWeather rainfall for current-season fields in Auto groups, keeps user entries, and lists Manual groups that received unwanted AgWeather rainfall while the bug was live.
- [x] Feb 15 `yearly:reset` cron disabled in `config/schedule.rb` (the task can still be run by hand).
- [ ] Push, merge to `main`, `cap staging deploy`, smoke test, `cap production deploy`. Whenever's Capistrano hook rewrites the crontab, which removes the reset job.
- [ ] Production: `DRY_RUN=1 bundle exec rake precip:backfill`, review, then run it for real (1 of 183 groups is set to Manual).
- [x] Usage query run on production (results in Q2). Only 1 sweet corn + LAI field and the season is over, so no C18 legacy hotfix.
- [ ] After Nov 30: archive `pg_dump` of legacy production; export golden-test fixtures (§10) and AgWeather ET/precip for 2025–2026 at the ~228 real pivot locations (§8.4).

### Phase 1: Foundation

- [x] `rails new` (Rails 8.1, Postgres, no Hotwire/importmap/asset pipeline) in `wisp3`; git; public GitHub repo `uwent/wisp3`; CI (`bin/ci`, run by GitHub Actions).
- [x] `vite_rails`, `inertia_rails` (Inertia v3), Svelte 5 + TS, Tailwind v4 (`@tailwindcss/vite`), `bits-ui`, Alba + Typelizer (types and route helpers).
- [x] App shell: layout, navigation, user menu, group switcher, status color tokens, light/dark (follows system), responsive at phone widths.
- [x] Devise + Inertia auth pages (sign up, sign in, confirmation, password reset, settings with email/password change and account deletion), **sign-in links and codes**, rate limits (Rails `rate_limit` + Rack::Attack).
- [x] Group / membership / `Current.group` tenancy, with cross-tenant request specs.
- [x] Capistrano config, systemd user units, nginx example, staging credentials; first-time setup steps in `docs/deployment.md`.
- [x] First deploy to staging (2026-10-03): Puma answers on 127.0.0.1:3100 and both services are enabled. nginx serves it at https://dev.wisp.cals.wisc.edu.
- [x] Send the §12 server requirements to the sysadmin so the new production box is ready by February. *(Production went to AWS instead: EC2, RDS, ECR and SSM, ready October 2026; deployed with Docker, `bin/production`.)*
- **Exit:** a user can sign up, confirm, sign in by password or link, and see an empty dashboard on staging. *(Verified locally in a headless browser, desktop and phone/dark; staging live 2026-10-03; sign-up and the confirmation email checked on staging.)*

### Phase 2: Domain and engine

- [x] Migrations and models for §4 (weather tables wait for Phase 3); plants and soil types in `db/reference/*.yml`, loaded by `ReferenceData` on `db:seed` and on every deploy.
- [x] `WaterBalance`, `Canopy`/`CanopyModel`, `CropEt` (`app/services`) with the §5 fixes and unit tests; property tests for AD bounds and water conservation.
- [x] `DailyInputs` resolver (precedence and provenance, including pivot irrigation and run hours); `PlantingBalance` runs a planting's season from the database.
- [x] Golden test harness: `spec/support/legacy_engine.rb` reproduces legacy with each fix switchable (with all fixes it equals `WaterBalance`); `spec/golden` checks each fixture field and attributes every differing day to a fix. Export script `script/legacy/export_golden_fixtures.rb` (checked against the local legacy dev DB, whose 2026 fields have no weather). *(The golden fixtures, `spec/golden` and the export script were retired in `5533ff4` once all 30 fields passed; `legacy_engine_spec` remains.)*
- [x] Golden tests passed on 30 fields exported from legacy production (2026-10-03), then retired along with the legacy data (no legacy data is kept in the repo); `LegacyEngine` and its synthetic spec stay as the record of what each fix changes. 12 have weather; 18 never received reference ET (AD flat all season) and pass trivially. Every differing day traces to C2, C3, C4, C7, C19, or C7+C4 together. Findings:
  - **C19** (new): stale ET on moisture-reading days.
  - **C7 dominates**: active fields are missing reference ET on 80–200 of 243 days, so legacy ran much of the season on self-fed gap fill. Open-Meteo (Phase 3) should make gaps rare; the new engine stops gap-filling after 7 days instead.
- [x] `bin/rails demo:seed`: a demo account with 3 farms, 13 fields (a pivot with 8 fields, a double crop), both ET methods, pivot irrigation in inches, run hours and for a subset, a soil moisture reading and a field group.
- **Exit:** golden tests pass for every fixture field, and each difference traces to a listed fix.

### Phase 3: Weather

- [x] `Weather::OpenMeteo` client (free / customer hosts, key optional), rate limiter, hourly → daily aggregation and unit conversion; WebMock specs from recorded responses.
- [x] Cells on the O1280 grid, `weather_days`, `weather_forecasts`; refresh, finalize, backfill and prune jobs on recurring schedules. `PlantingBalance` reads stored weather.
- [x] Daily and cumulative GDD from tmax/tmin (`Weather::DegreeDays`, base 50 °F / cap 86 °F), groundwork for Q2 option C.
- [x] Admin weather-status page (`/admin/weather`; admins only), with "Refresh now".
- [x] **AgWeather vs Open-Meteo comparison report** (§8.4, `docs/weather-comparison.md`); model chosen: NBM, then best_match.
- [x] Verified locally on the free API: every demo pivot has season-to-date data and a current forecast. Deployed to staging with the commercial key in its credentials (2026-10-03); the local `.env` key check is in TODO.md.
- **Exit:** every pivot in the demo seed data has season-to-date data and a current forecast; comparison report written and decision recorded.

### Phase 4: Core UI

- [x] Setup pages (farms/pivots/fields/plantings), "copy last season", and a guided first-run setup (target: two-field pivot in under 5 minutes, §13). `/setup` (nested list, dialogs for fields and crops, season picker, the group's rainfall setting), `/setup/start` (`QuickSetup`: farm, pivot on the map, fields with crops, all or nothing), `SeasonCopy`.
- [x] Pivot location picker (MapLibre, click center, drag radius) used in pivot creation; location required. `PivotMap`: USGS imagery or OpenFreeMap streets, draggable center and radius handle, arcs, "use my location", the group's other pivots outlined.
- [x] Editable daily grid component; field status page with the summary box. `EditableCell` (click or type to edit, Enter saves and moves down, arrow keys, Escape); `FieldDaysController` saves a day's entry and canopy reading together.
- [x] ECharts chart: observed AD, inputs, thresholds, zoom. AD (or % moisture) above, rain and irrigation below on the same date axis (no dual axis), threshold lines, reading days marked, last 30 days by default.
- [x] Weather panels on the field page from `weather_days` and the forecast (Ben's request): modeled soil moisture by depth (against the field's FC/PWP) and soil temperature, GDD since emergence, temperature, humidity/VPD, wind and cloud cover. `WeatherPanel`; one measure per chart, forecast shaded. Later: precipitation (rain and snow-and-other stacked, with snowfall bars and snow depth in light gray when there's snow) and reference vs crop ET as daily bars, each with running totals over the days in view in a grid below; an (i) on each card explaining its measures, and a reset button once a chart is zoomed or a series toggled (`ChartCard`, `InfoTip`).
- [x] Dashboard by farm → pivot → field ("Farm:", "Pivot:" cards with View/Edit, "Field:" status cards; pivots without fields listed). A pivot's page shows its irrigation and its cell's weather for the season (`WeatherSection`, shared with the field page; reference ET only, GDD from the season start).
- [x] Dashboard (field cards, status), bulk daily entry, field groups. Cards show status, AD, a 21-day sparkline, last rain and irrigation; days-until-crossing waits for the Phase 5 projection.
- [x] Pivot irrigation entry (inches or run hours, which fields it applied to) with "from pivot" badges and per-field overrides in field grids. On the pivot's irrigation page and in daily entry; the grid shows the pivot amount under a field's override.
- [x] CSV export (parity with legacy columns), plus each input's source and the modeled rain. Depths in inches whatever the user's units (`PlantingCsv`).
- [x] Settings menu with the unit toggle (Q3) and the `units.ts` formatters and parsers used by every display and input. `NumberField` shows and parses in the user's units and submits stored units.
- [x] Modeled rain shown next to entered corrections in the grid, chart and season summary (Q7).
- [x] Playwright smoke tests in CI (§10). A local script covered every page this phase (desktop, and phone in dark mode). *(In the repo and CI from Phase 4.5: `bin/e2e`.)*
- **Exit:** the main legacy features are all available; an internal user can manage a season end to end. *(Verified locally in a headless browser on the demo data and a fresh metric-units account, 2026-10-03; not yet deployed to staging.)*

### Phase 4.5: Review fixes and polish

From a review of Phases 1–4 (2026-10-03): bugs, plan items that slipped, and rough edges to finish before the projection work builds on these pages.

Done 2026-10-03, except the staging deploy (Ben pushes and deploys) and the member-roles decision (Q8). Also fixed: GitHub CI failed because `db:prepare` seeds reference data into a freshly created test database; `spec/rails_helper.rb` now clears it before the suite.

Bugs:
- [x] **Escape in a grid cell saves the draft.** Chromium fires `blur` when the focused input is removed, and `EditableCell`'s `onblur` calls `commit()` without checking that editing was cancelled. Reproduced in Playwright on the field grid (typing a note, then Escape, sent the PATCH). The jsdom test passes because jsdom doesn't blur on removal. Guard `commit` (a cancelled flag or `if (!editing) return`) and cover it in the Playwright smoke tests. *(Fixed; a Vitest case simulates the blur, and the e2e test fails without the fix.)*
- [x] Setup: "Delete this crop" closes the dialog even when the confirm is cancelled.

Slipped from the plan:
- [x] **Field-group percent cover** (§4 precedence: "group pct-cover entries become CanopyObservations on each member planting"). The field group grid has rain, irrigation, moisture and notes, but no cover column. *(A Cover column when a member has a percent-cover crop; saving writes `CanopyObservation.record` on each member's percent-cover planting that day; the grid shows their shared reading or "varies".)*
- [x] Playwright smoke tests in CI (carried over from Phase 4): sign in, the demo group, every page, one grid edit, one daily entry save, Escape-cancels. *(`bin/e2e`: own database `wisp3_e2e`, demo account with synthetic weather from `e2e/seed.rb`, desktop and phone/dark; a step in `bin/ci` and GitHub Actions, which uploads the report on failure.)*
- [ ] Deploy Phases 4 and 4.5 to staging and smoke test there (each phase ends deployed to staging). *(Ben: push, then `bundle exec cap staging deploy`; TODO.md.)*
- [x] Give unassigned §11/§12 items a phase, or cut them: admin users list, CSV, announcements and impersonation; the public landing and about pages; the admin email when a job fails or a cell's weather is more than 24 h stale. Suggest Phase 8 for all of them. *(Added to Phase 8.)*
- [x] Plan housekeeping: Phase 7's "moving a pivot triggers a backfill" already shipped in Phase 3 (`Pivot#backfill_weather`; the balance is recalculated on read). The Phase 1 and Phase 3 exit notes still say staging sign-up and email delivery and the commercial key are "still to check", but TODO.md marks them done. Reconcile both. *(Done.)*

Polish:
- [x] **Weather-pending state.** A new pivot shows blank ET and a flat AD line until its backfill lands, with no explanation. Show "Weather for this pivot is on the way" on the field page and dashboard card while the cell has no days. *(`PlantingStatus#weather_pending?`.)*
- [x] Daily entry: changing the date (arrows or picker), or leaving the page, silently drops unsaved values. Use `confirmUnsavedChanges` (the form already tracks `isDirty`).
- [x] Weather panels cover the whole season while the soil-water chart opens on the last 30 days. On a phone that's eight dense season-long charts. Open them on the same window as the main chart (or link their zoom), and consider collapsing them by default on narrow screens. *(Same window, scroll or pinch for more, collapsed on phones.)*
- [x] Phone header: the group switcher and user menu wrap to a second row, so about 140 px of chrome sits above the content. Fold them into one compact menu at phone widths. *(Two rows; the group switch moves into the account menu.)*
- [x] Pivot irrigation page: "Add an irrigation" for a date that already has one silently replaces it. Warn, or switch the form to editing that day. *(Warns, with "Edit that one instead".)*
- [x] Copy last season: plantings that fail validation are skipped silently. Report how many were skipped and why. *(The realistic case is a season running into the next year, whose copy overlaps it.)*
- [x] Farm notes exist in the model but can't be edited (the farm dialog has only the name).
- [x] Charts draw with the body font when they are built. If Red Hat Text hasn't loaded yet, canvas text falls back to the system font, so rebuild once `document.fonts.ready` resolves.
- [x] CSV export: prefix cells starting with `=`, `+`, `-` or `@` with `'` (spreadsheet formula injection from field, farm and note text).
- [x] Dashboard runs the full balance for each field, about 5 queries per field (~50 ms for 2 fields locally). Measure with 50+ fields and batch the loads before Phase 5 adds forecast and ensemble runs to every card. *(60 fields: 368 queries / ~830 ms → 13 queries / ~220 ms in the test environment, via `DailyInputs.preload` and `WeatherDay.balance_inputs_by_cell`. What remains is the balance itself; Phase 5 should run projections from the same preloaded inputs.)*
- [x] Membership roles: any member can rename the group, change its rainfall setting or delete farms. Decide on owner/member roles before group invitations (Phase 8 stretch). *(Q8 decided 2026-10-04: owner and member; shipped with the operation page.)*
- [x] Specs: a `PlantingCsv` unit spec (columns, totals, sources), `SeasonCopy` edge cases (leap day, overlap), and Vitest coverage for `weatherCharts.ts` and `dates.ts`.
- **Exit:** the bugs are fixed with tests, Playwright runs in CI, Phase 4 is live on staging, and every unassigned plan item has a phase.

### Phase 5: Forecast projection

- [x] Deterministic projection through the 16-day forecast. *(Today from the forecast too; §6 "As built".)*
- [x] Ensemble spike (et0 per member?), then the ensemble runner, P10/P50/P90 band, crossing probability. *(Yes for GFS, 31 members; `EnsembleProjection`.)*
- [x] Planned irrigation (what-if) and recommended irrigation amount and timing. *("Irrigate by" with the refill amount and the share of forecast scenarios that agree, on the field page and dashboard cards; the dashboard sparkline continues dashed through the forecast.)*
- **Exit:** the chart shows observed → forecast → band; adding a planned irrigation updates the projection in under 300 ms.

### Phase 6: Alerts

Decided 2026-10-04 (Ben): a **daily digest** instead of event-based alerts. Simpler to build and to understand, and it shows the whole picture every day.

- [x] Digest settings: how often (never, daily during the season, or only when irrigation is needed: a field at Irrigate or Caution, i.e. needing water within 3 days) and which fields it includes (default: every field in the user's operations, picked by operation, farm or field). *(Alerts page, `/alerts`, in the main nav; `digest_exclusions` in §4.)*
- [x] The digest email rehashes each included field's dashboard card: status, AD today, the outlook ("Irrigate by …", refill amount, how many forecast scenarios agree), last rain and irrigation. A short "Needs attention" list (irrigate, or caution; soonest first) leads, then every field by farm and pivot as on the dashboard, each pivot with its weather for the past 7 days and next 7 (rain, ET, range of highs and lows); a field needing attention gets the full outlook, one that's fine a compact line. *(`DailyDigest`, `WeatherSummary`, `DigestMailer`; the outlook's wording is in Ruby too, `Outlook`, matching `lib/outlook.ts`. Links carry `?operation=` so they open in the field's operation.)*
- [x] **Digest by weather zone** (Ben, 2026-10-15): operation › farm › weather zone (the grid cell the farm's pivots share, with that zone's weather and the pivots in it) › pivot › field, with "Operation:", "Farm:", "Pivot:" and "Field:" labels as on the dashboard and each field's due tasks (Phase 6.7). When the included fields are all in one operation (or on one farm), that heading gives way to a line at the top ("Operation: Demo · Farm: Hancock"). *(`DailyDigest#operations`, `#context`.)*
- [x] **What the digest lists** (Ben, 2026-10-15): `users.digest_scope`: all the fields it covers (in season or not, "Off season" with when the season starts or ended), those with a crop in season (the default), those needing irrigation or a reading, or only those needing irrigation. With nothing to list it says "No action needed" and why, with the in-season pivots' weather. A new frequency, `daily_all_year`, sends every morning even with nothing in season (weather for every included pivot). "Fields it covers" gains a pivot level (a pivot with none of its fields picked is left out whole, `DigestExclusion` on a Pivot). The footer counts what's listed of what's covered. `WeatherCell.active` takes in the cells such digests show out of season.
- [x] Preview today's email and send a test from the Alerts page, for every user (a test goes whatever the frequency, at most one per 5 minutes). *(The preview is an optional Inertia prop, built only when asked for.)*
- [x] Sent each morning after the 5 am refresh, to users with the digest on and at least one active field; unsubscribe link and `List-Unsubscribe` header. *(`DailyDigestJob` at 6 am Central; one-click `List-Unsubscribe-Post`; the link's GET only shows a button.)*
- [ ] SPF/DKIM check (Q6): Ben, on staging.
- [x] Admin preview: "what would be sent today" for any user. *(Admin user page → "Preview today's daily email".)*
- **Exit:** staging sends correct digests for test fields across simulated scenarios (rain refill, sudden heat, planned irrigation pushing back "Irrigate by").

### Phase 6.5: Landing page and documentation

Decided 2026-10-05 (Ben): replace the legacy PDF user guide with documentation in the app, and greet signed-out visitors with what WISP is instead of a sign-in form. Brought forward from Phase 8.

- [x] **Landing page** at `/` for signed-out visitors (signed in, `/` stays the dashboard): what WISP is and who it's for, how it works in a few steps (weather → water balance → when and how much to irrigate), what you enter, and sign-up / sign-in buttons. Its text is the introduction of the About page, shared rather than copied. *(`PagesController`, `Pages/Home`; `lib/docs/Introduction.svelte`.)*
- [x] **About page** (`/about`, public, in the nav after Setup; signed out, the nav shows only About with sign-in and sign-up buttons). Sections, each with an anchor:
  - Introduction (shared with the landing page).
  - How WISP works: the water balance (§5) in plain words; weather from Open-Meteo, the forecast and its scenarios; statuses and "Irrigate by".
  - Getting started: account, operations and members, farms → pivots → fields → plantings, quick setup, copying last season.
  - Day to day: dashboard, daily entry, field groups, the field page (grid, planned irrigation, chart, weather), the daily email (Alerts).
  - Ground-truthing: which readings matter and how often (`lib/guidance.ts`): soil moisture weekly, sensor depths, percent cover or LAI, rain gauges.
  - Crops: a table from the `plants` table: default root zone depth, canopy methods (percent cover; LAI with the growth curve or with readings only), suggested sensor depths, with the shared defaults (MAD 50%, season dates) noted.
  - Glossary: every entry in `lib/glossary.ts`, each with an anchor the tooltips can link to.
  - Credits and contact: UW-Madison Vegetable Entomology Lab, agweather@cals.wisc.edu.
  *(`Pages/About`; the crop table from `plants`, reading advice from `lib/guidance.ts`, glossary from `lib/glossary.ts`, so they follow the app.)*
- [ ] Wording reviewed by Ben (agronomy, contact details).
- **Later (Phase 8):** screenshots, a printable version, the methods detail (equations from §5) for agronomists, and a "More in the guide" link from each glossary tooltip.

### Phase 6.6: Field rain setting and season details

Decided 2026-10-07 (Ben): some growers want the balance to use only the rain they enter, field by field. A per-field setting (Q7 addendum, §4 precedence), a "season details" card with gauge-vs-model statistics, entered rain on the precipitation chart, and two chart fixes.

**A. Chart fixes** (independent; can land first)
- [x] Snowfall and snow depth appear in the precipitation legend only when the days *in view* have some (`shownSeries` checked the whole season, so April snow put them in an October legend). *(The series stay on the chart, for scrolling back; `legend.data` names only those with snow in view.)*
- [x] Crop ET on the ET chart continues through the forecast: the projection's `adj_et` (forecast et0 and projected canopy) is what it takes out of the soil. Update the chart's info text.

**B. Per-field rain setting**
- [x] `fields.use_model_precip` (nullable boolean); `Field#effective_use_model_precip` falls back to the group's. `DailyInputs` reads it, and uses modeled rain on days after today whatever the setting (it takes `today:`, passed through `PlantingBalance` from `PlantingStatus`). Check that `FieldStatuses` and `DailyDigest` preload what it reads.
- [x] Any member can change it (like other field settings); the group-level default stays owner-only (Q8).
- [x] `FieldSerializer`: the field's setting (the page takes the group's default from `auth.group`, the effective one from `summary.use_model_precip`); `fields#update` permits it. Specs: override both ways, NULL inherits, forecast rain kept after today, cross-tenant update. `legacy_engine_spec` unchanged (the default doesn't change).
- [x] **"No rain" projection** for entered-only fields: `PlantingStatus` runs the balance over the projection's days with forecast rain set to zero (planned irrigation and entered rain kept), from today's AD with the same ET history as the ensemble. The projection gets a `dry_ad` per day and the summary a `dry_crossing`. On the field page: a dashed "If no rain falls" line on the soil-water chart, a column in the forecast table, and "Irrigate by … (… if no rain falls)". Status, "Irrigate by" and the digest follow the forecast case. *(`PlantingStatus#dry_projection`, `#dry_crossing`; the outlook's `dry` line, in `lib/outlook.ts` and `Outlook`, also goes in the digest.)*
- [x] Wording elsewhere: the operation page says fields can override its setting; daily entry doesn't show the "model" placeholder for entered-only fields; Setup marks entered-only fields; the field page's summary card says "Rain: only your entries · change" (linking to the setting). *(The setting is in a "Field settings" card at the bottom of the field page for now; part D adds the statistics to it.)*

**C. Entered rain on the field page's precipitation chart** (the pivot page's chart is unchanged)
- [x] `weatherPanels(units, { fieldRain })`, from `days` and `forecast_days`: an entered rain bar where there's an entry, with the modeled precipitation as a hollow, dashed bar behind it (the soil-water chart's style); for entered-only fields every modeled bar not used by the balance is hollow. The lower panel gets two running totals: modeled, and used by the balance. The section intro and the chart's info text say so. vitest for overrides, entered-only and no `fieldRain`. *(Entered rain is a bar beside the model's stack, like snowfall, rather than over it; the tooltip marks outlined amounts "not used".)*

**D. Season details and settings card** (at the bottom of the field page, after the weather)
- [x] The rain setting: operation default (named) / modeled, replaced by my entries / only rain I enter. Saving reloads the season.
- [x] Statistics through today, computed in the browser from `days` (`lib/seasonStats.ts`, pure and unit tested):
  - Entered rain: total, readings, days with rain. Modeled rain: total, days with rain (≥ 0.01″, measurable). For entered-only fields, the modeled rain days and total the balance left out.
  - Irrigation: total, days, typical interval (median days between irrigations), typical amount (median).
  - Deep drainage: season total.
  - Gauge vs model, by day: both rained; you entered rain the model didn't have; you entered 0 where the model had rain; model rain with no reading (not counted as a disagreement: no reading may mean no rain or no check). On days both rained: how often they disagree (by more than the larger of 0.1″ and 25%), the typical adjustment (median entered − modeled), and the ratio of the totals.
- [x] The summary card's "your gauge read … the model …" sentence links to the card. A glossary entry for the rain setting; guidance on when to choose entered-only (a gauge read every day it rains). *(Glossary `entered_rain_only`; the About page's Weather section and its rain advice.)*
- [x] Playwright: switch a field to entered-only, see the badge, totals and dry line change, switch back.
- **Exit:** switching a demo field to entered-only and back restores the same balance; its projection shows both cases; the precipitation chart and the details card agree with the daily grid.

### Phase 6.7: Crop canopy curves

Proposed 2026-10-15 (Ben): every crop gets a default canopy curve (percent cover, and LAI where it has one) that runs from emergence through the season. Readings the grower enters scale it or take over from it, and each planting chooses how readings and the curve combine. Brings Q2 option C forward from "After launch". Not a perfect growth model: growers are still asked for readings about weekly. The aim is plausible growth and decline rates between and without readings, and documentation of every curve's source on the About page.

**What happens now (§5.3, `Canopy`, `CanopyModel`):**
- **Percent cover:** 0 at emergence, a straight line to the first reading and between readings, the last reading held to `end_date`, then 0. **With no readings the cover is 0% all season**, so the planting only loses bare-soil evaporation (A3600 Table C at 0%). Percent cover has no curve.
- **LAI:** field corn follows the WIS curve (by days since emergence) until a reading is entered. After that the readings replace the curve for the whole season (straight lines, ramp from 0, held after the last). Every other crop has LAI 0 (no ET) until its first reading.
- ET only responds to cover up to 80% (`CropEt`: ET = et0 from 80% cover), and to LAI up to about 3 (Kc ≈ 1.09). So a curve matters most during canopy development, and in the decline before `end_date` for crops that senesce in the field (potato, field corn, soybean, wheat).

#### A. Research plan

Each step produces a dated note in `docs/canopy/` (sources, data, scripts and results) so the reasoning stays public with the code.

*Progress:* `01-legacy-readings.md` (A.2; first look at A.3: GDD doesn't explain the 2026 spread), `02-published-curves.md` (A.1 for potato, field corn, soybean, snap bean and sweet corn: AquaCrop's calendar-day defaults match Wisconsin 2026 within a few days for potato, corn and snap bean; FAO-56 Table 11 rows for the rest). `03-crop-curves.md` (A.5 draft: a proposed curve and confidence for every crop; onion, alfalfa, mint, asparagus and Other stay readings-only; LAI from cover with k = 1.5 is Kc = 1.1 × cover, 20–40% below percent cover ET during development). `04-backtest.md` (A.4: "ratio between readings" halves the error of the next week's canopy against straight lines and is best between readings; breaking to straight lines never helped, so the recommendation is a warning instead, pending Ben). `05-dssat.md` (LAI curves simulated with DSSAT for field corn, sweet corn and potato: field corn peaks like the WIS curve but develops about 10 days earlier, closer to the 2026 readings, so it's a candidate to replace it once checked against measured LAI (Nocco et al. 2019's readings, requested); sweet corn depends on the hybrid; potato is implausible. No curve changed.) *Waiting on data (2026-10-21):* Nocco's raw LAI readings, to cross-check the field corn curve before changing it; a potato data set has arrived, but it's above-ground biomass by day since emergence from day 56 only, so earlier data and canopy cover readings have been asked for.

1. **Survey the published curve families**, recording for each the equation, driver (calendar days or degree-days, with base and upper temperatures), parameters per crop, how it was calibrated, and its licence or citation.
   - **FAO AquaCrop** canopy cover model (Steduto et al. 2009, Raes et al. 2009, *Agron. J.* 101; reference manual ch. 3): exponential growth from CC0 at rate CGC to a maximum CCx, then decline at rate CDC from the start of senescence. It can run on calendar days or GDD, and its crop files have calibrated parameters for maize, potato, soybean, wheat, barley, tomato, cabbage, onion, sunflower, alfalfa and more. **This is the leading candidate for percent cover:** the curve family is published and peer reviewed, needs only a few parameters per crop, and covers senescence.
   - **FAO-56** (Allen et al. 1998) Table 11 stage lengths and the cover-based Kc (Allen & Pereira 2009, *Irrig. Sci.* 28): use it as the fallback for crops without AquaCrop files (mint, asparagus, celery, beets, cucurbits) and as a check on the others' timing.
   - **Crop-model LAI** for the LAI method: CERES-Maize and Hybrid-Maize (Yang et al. 2004) for corn, SUBSTOR-Potato, and CROPGRO for soybean and snap bean (dry bean). Compare them with the WIS corn curve, whose origin is still to be confirmed (Q2 question 1).
   - **Canopy extinction coefficient k** per crop, to convert between cover and LAI (CC = 1 − e^(−k·LAI)). This lets one curve per crop serve both methods, and it also answers Q2 question 2 about the 1.5 used in `CropEt`.
   - **Upper Midwest and Wisconsin sources** for timing and maximum cover: UW potato canopy and irrigation work in the Central Sands, the processing-vegetable literature (sweet corn, snap bean, peas), Iowa State/Ritchie corn and soybean stage-GDD tables, and A3600 itself. Use them to adjust AquaCrop or FAO timings to Wisconsin cultivars and planting dates.
2. **Mine the legacy readings (the best Wisconsin data we have).** Legacy production holds several seasons of percent cover readings entered by growers, with crop, emergence date and location. Export them read-only and **aggregated, with no user, farm or field identifiers**: crop, year, days after emergence, cover, and the O1280 cell. Attach daily GDD from `weather_days` (or backfill those cells), and screen out implausible values. Also run the LAI-reading query, though few or none are expected. Only the anonymised extract and the fitting scripts are committed. Check with Ben that this use of legacy data is acceptable before exporting.
3. **Choose the driver for each crop from the data.** Fit each candidate family to each crop's legacy readings, by days after emergence and by GDD with the crop's base temperature (for example 50 °F for corn, about 45 °F for potato, 40 °F for peas and cool-season crops). Keep GDD where it explains clearly more of the variation between years and planting dates; otherwise use calendar days, which are simpler to explain. Days ahead of today take GDD from the forecast, and beyond the forecast, a climatological normal.
4. **Choose how readings combine with the curve** by backtesting on the legacy series: hide every other reading, predict the hidden ones with each method, and compare the errors (in cover, and in the season's crop ET through `CropEt`). Candidates:
   - **Linear:** today's behavior, kept as an option.
   - **Scaled curve:** the ratio of each reading to the curve, interpolated between readings and multiplied by the curve, with the curve's shape kept after the last reading. This needs a guard where the curve is near 0 early in the season.
   - **Shifted curve:** each reading maps to the point on the rising curve with the same value (the crop is *n* days or GDD ahead or behind), interpolated between readings. This is stable early but undefined above the curve's maximum and after the peak, so it switches to scaling there.
   - After the last reading the scaled curve is followed (decided below); the backtest measures how well that predicts later readings, and sets how far off the readings can be before WISP warns and falls back to straight lines. Readings at or above 80% cover change nothing in ET, so for percent cover the main question is the early-season ramp.
5. **Write a crop card for every crop in `plants.yml`**: driver and base temperature, parameters, maximum cover/LAI, days or GDD to full cover and to senescence, sources, the fit to legacy data, and a confidence rating (*fitted to Wisconsin data* / *published, unvalidated here* / *borrowed from a similar crop*). Do the crops in order of how much they're grown and how much the curve matters: **potato, field corn, sweet corn, soybean, snap bean**; then peas, onion, carrot, cabbage/broccoli, cucurbits, pepper/tomato, wheat/barley, alfalfa, mint, asparagus; then the rest. Similar crops can share a curve (cucurbits, brassicas, leafy greens), with the sharing noted on their cards. Perennials and cut crops (alfalfa, asparagus, mint) may need curves that restart at green-up or cutting, or no curve. For **Other**, use no curve: linear readings only, as now.
6. **Agronomy review:** send the crop cards and the backtest results to the agronomist contacted for Q2. *(2026-11-10: the researchers contacted about potato canopy and LAI have stopped replying; no review is expected. The curves stand on the literature and our own backtest, labelled with their confidence, and are checked against 2027 readings: After launch.)* Nothing becomes a default without a source; if a crop's card is weak, that crop ships with no curve (today's behavior) rather than a guessed one.

**Research exit:** a crop card for every crop, the backtest choosing a method for combining readings and the curve, and the review's answers recorded in Q2.

#### B. Implementation

- [x] **Curve definitions in one data file**, `db/reference/canopy_curves.yml`, read by `CanopyCurve`: AquaCrop growth (CC₀, CCx, CGC) by days since emergence (calendar days for every crop, A.3), an AquaCrop decline or a calendar rule (potato), basis, sources, confidence and notes. Keyed by plant key; crops not listed have no curve. The engine, the field page and the About page all read it. LAI curves stay in `CanopyModel` (`plants.canopy_model`).
- [x] **Per-planting setting** `plantings.canopy_interpolation` (`linear` | `curve`, NULL = the crop's default: `curve` if it has one). With no readings, a crop with a curve follows it under either setting. The planting form offers "Between canopy readings: follow the curve / straight lines" when the crop has a curve for the chosen method; season copy keeps it.
- [x] **Engine change (C20):** `Canopy` follows the curve with no readings and, under `curve`, the curve times a ratio interpolated between readings (A.4: "ratio between readings"), capped at the larger of the curve's peak and the highest reading; `linear` is the old behavior. The same applies to field corn's LAI curve. `LegacyEngine::CANOPY_FIXES` lists C20; `legacy_engine_spec` is unaffected. Specs: `canopy_spec`, `canopy_curve_spec`.
- [x] **Warning, no automatic switch** (decided below): `Canopy#check` flags percent cover readings (10–80%) more than 7 days ahead of or behind the curve, or a reading that falls more than 5 points while the curve grows or holds. `PlantingSummarySerializer#canopy_check`; the field page shows it above "How … is modeled".
- [x] **Field page:** the canopy panel draws the crop's curve dashed behind the modeled canopy and the readings; the tooltip adds "Crop curve". The guidance describes the curve and how readings combine with it, and the chart and grid notes say how muted values are estimated.
- [x] **About page:** a "Canopy curves" section (how readings combine, the warnings, how the curves were made with the equations, crops without a curve, why LAI is field corn only) and a card per crop from `canopy_curves.yml`: the curve for a May 15 emergence (`CanopyCurvePlot`), days to 50% and 80%, the decline, basis, parameters, notes, confidence and sources (with DOIs), linking to `docs/canopy/`. The crop table says which crops have curves. Glossary: canopy curve.
- [x] Demo seed: the snap beans have no readings, so they follow their curve.
- [x] **Tasks per field** (Ben, 2026-10-15): `PlantingTasks` lists what's due while the season is on: a soil moisture reading about weekly, a percent cover reading about weekly from emergence until about 80% (LAI once the grower has started), and the canopy check. Its wording is server-side, so the field page (readings and warning), the dashboard cards ("To do") and the daily email (a "To do:" line per field) all show the same. `summary.tasks` replaces `canopy_check`; the field page no longer works out due readings in the browser.
- [ ] Wording reviewed by Ben. *(The agronomist review of the curves is dropped for now, 2026-11-10: see A.6. If someone takes it up later, `docs/canopy/03-crop-curves.md`, "For the agronomist", is the starting point.)*
- **Exit:** every crop in `plants.yml` either has a sourced curve or is documented as having none. A demo planting with no readings has a plausible cover and ET season, and adding readings moves it as the chosen method says. The About page's crop cards match `canopy_curves.yml`, and `legacy_engine_spec` passes.

**Decided 2026-10-15 (Ben):**
- **No readings:** a crop with a curve follows it from emergence.
- **Readings and the curve:** the curve is scaled to fit the readings, and after the last reading the canopy **keeps following the scaled curve**, including its decline; it is not held. *Revised after the backtest (A.4):* the scaling is local ("ratio between readings"), and readings far from the curve get a **warning but no automatic switch** to straight lines, which never helped in the backtest: "better to warn and inform than to change behavior". A planting can still choose straight lines.
- **Legacy data:** anonymised readings may be used if they are of good quality. The 30-field golden sample (`tmp/wisp_golden.json`, 2026) shows why filters are needed: 12 of its 23 percent cover fields have no cover readings, the rest have 1–22, and many emergence dates are the May 1 default. Screen out fields with fewer than about 4 readings in the growth period, emergence left at the default, or readings that go down during growth. Only 2026 exists (legacy deleted each season's data on February 15), so the extract checks timing rather than fitting curves (`docs/canopy/01-legacy-readings.md`); the extract itself isn't committed.
- **Potato decline** (until a researcher's potato model arrives): from July 25, an S-curve (smoothstep) down to 50% over 42 days, held until vine kill (below); later if the canopy hasn't reached its maximum by then. It replaced a straight 10 points a week from August 1 (2026-10-22), with nearly the same August values. A labelled Wisconsin management rule (`docs/canopy/02-published-curves.md`), so curve definitions need a calendar-date decline (start date, days, floor) as well as AquaCrop's CDC.
- **LAI only for crops with an LAI curve** (revised 2026-10-15, replacing Q2 option B): deriving LAI from cover (k = 1.5) works out to Kc = 1.1 × cover, 20–40% below percent cover ET during canopy development (`docs/canopy/03-crop-curves.md`), so it isn't offered. A planting can use LAI only if its crop has an LAI curve, so far field corn; other plantings on LAI were switched to percent cover (their readings kept). A researcher may supply LAI curves for more crops; each is added to `CanopyModel` with its source. *(Done: `Planting#lai_needs_curve`, the planting form, guidance, About page, migration.)*
- **Fitting the curve to readings** (Ben, 2026-10-29): readings should be used exactly, a reading or two should barely move the default curve, and more readings should fit it more closely. `CanopyFit` fits a shift, stretch and height to the readings, each held toward the typical curve (penalized least squares: 5 days, 15%, 10%; readings ±10 points of cover, or 0.4 LAI; 80%+ counts as "at least 80"); `Canopy` then passes through each reading by a ratio to the fitted curve, which eases back to 1 over 14 days after the last reading instead of being held all season. That ends the case where one early reading (LAI 0.3 on day 20) took field corn to its peak LAI for weeks. Backtest (`docs/canopy/06-fitting.md`): the error over the rest of the season fell about 40% (0.076 to 0.048 of et0 on the unadjusted curves) and between readings from 0.029 to 0.026; one reading moves the curve 0.6 days on average. The canopy check keeps its own unpenalized shift. Fits are cached by readings and curve. The field page says how the curve was fitted ("runs about 4 days ahead…"). *(Done: `CanopyFit`, `Canopy`, `CanopyCurve`/`CanopyModel` adjustments, guidance, About page, planting form; constants pending Ben's review.)*
- **Vine kill** (Ben, 2026-10-29): potato is vine killed two to three weeks before harvest and irrigated through it for skin set, so ending the season at vine kill stopped the model while growers were still irrigating, and ending it at harvest left dead vines at 50% cover. A potato planting takes an optional `vine_kill_date`; from it the canopy ramps linearly to 0% over 14 days (`Canopy::VINE_KILL_DAYS`; desiccants vary a little by cultivar), and the balance runs on to the end date, now labelled Harvest, on bare-soil evaporation. A reading on or after vine kill is used as entered, and the ramp continues from it; those readings stay out of the curve and the canopy check. Percent cover isn't asked for after vine kill; soil moisture is, to harvest. Which crops take it is `vine_kill: true` in `canopy_curves.yml`: only potato, as no other WISP crop is irrigated after its vines are killed (sweet potato vines are cut days before digging, after irrigation stops; onion tops fall on their own). *(Done: migration with a check constraint, `Canopy`, `PlantingTasks`, the planting form, the field page's chart and guidance, season copy, both CSVs.)*

### Phase 7: Map

Proposed 2026-10-17 (Ben): a **Map** tab next to Dashboard showing the operation's current state at a glance: every pivot where it is, its fields' status badges, a popup per pivot with its fields' cards, the usual map controls, and a few optional public layers (radar, observed and forecast rain, drought). It reads the same data as the dashboard, with nothing new stored.

**Decided 2026-10-17 (Ben):** the map is its own tab, and the dashboard keeps its layout. Fields are badges on the pivot, not pie wedges (wedges would suggest where each field is). A collapsible side list of field cards. The public layers may be flaky as long as a failure is caught and reported gently. The soil survey comes into Phase 7 (G); weather zones and a map in the email go to later.

- [x] Moving a pivot (or changing its cell) triggers a backfill and recalculation. *(Shipped in Phase 3: `Pivot#backfill_weather` on a cell change; the balance is recalculated on read.)*

**Fields on the map.** We know where pivots are but not where their fields are (`fields.boundary` exists in §4 but nothing sets it). So the map stays honest: the pivot is drawn to scale, and its fields are shown as badges *on* it rather than as made-up areas.
- The pivot's circle or arc, to scale, outlined and lightly filled with its **most urgent** field's status color (irrigate > caution > ok > full; grey when no field is in season or the pivot has no fields).
- At the center, a screen-sized marker (HTML, not to scale) holding one `StatusBadge` per field in season, in name order, with a "Season ended" or "No crop" chip otherwise. Below a zoom threshold (pivots a few pixels across) it collapses to a single dot in the most urgent color with the field count.
- Pivot names label the outline at closer zooms, as in the picker. *(As built: the marker shows the name from zoom 13, badges from 11.5, a dot below; fields not in season are gray dots.)*
- *Later, not Phase 7:* drawing fields as sectors of their pivot (a start and end bearing per field, set in the picker; most split pivots are halves or quarters). Then each sector takes its own color. Only once growers ask for it.

#### A. Shared map pieces (refactor first)
- [x] `lib/map/`: the MapLibre loader (worker URL, dynamic import), the basemap styles (USGS imagery, OpenFreeMap streets), `switchBase` keeping our own sources and layers, and a `BasemapToggle` component. `PivotMap` (the picker) moves onto them with no change in behavior. *(`lib/map/maplibre.ts`, `basemaps.ts` with `setBasemap`, `BasemapToggle`, `PlaceSearch`.)*
- [x] `FieldCard.svelte` from the dashboard's card, with a `compact` variant for the popup. The dashboard uses it unchanged. *(`lib/components/FieldCard.svelte`, with `onselect` for the side list; `StatusCounts` too.)*
- [x] `FieldStatuses` loading moves out of `DashboardController` into a small query object (`OperationOverview`?) used by both pages, so the map and the dashboard can't drift. *(`OperationOverview`.)*

#### B. Map page (`/map`, `MapController#show`, `Map/Show`)
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

#### C. Pivot popup
- [x] Opens on a click on the pivot or its marker; on phones it's a bottom sheet instead of a floating popup.
- [x] Header: pivot name and farm, links to View, Edit and to daily entry for this pivot. *(View and Edit only: daily entry has no per-pivot view to link to.)*
- [x] Each field's compact card: status, AD today with the sparkline, the outlook headline ("Irrigate by …"), last rain and irrigation, due tasks; it links to the field page. *(The compact card leaves out last rain and irrigation.)*
- [x] The pivot's weather in one line: rain over the last 7 days and forecast for the next 7, ET over the last 7 (from `weather_days` and the latest forecast for its cell, already preloaded).
- [x] With the drought layer loaded: the pivot's Drought Monitor category (point in polygon in the browser).

#### D. Controls
- [x] Zoom in and out (`NavigationControl`), **fit all pivots**, **my location** (`GeolocateControl`; useful in the truck), fullscreen, scale bar.
- [x] Basemap: Satellite / Map, the picker's toggle (A).
- [x] Layers button: a panel with the overlays (E), each with on/off, opacity, its legend and valid time, and a link to the source.
- [x] Find a place (the picker's geocoder); pivots and fields are found with the side list's filter. *(Hidden on phones, where the map has no room for it.)*

#### E. Optional overlays (all off by default, loaded by the browser, never by our server)
Each overlay lives in a registry (`lib/map/overlays.ts`: id, name, tile URL builder, attribution, legend stops, refresh interval, description), unit tested for its URLs. All of these were checked on 2026-10-17: they answer with CORS headers and serve Web Mercator.

**When a source fails** (decided: depend on them, but fail gently): MapLibre's `error` events are caught per source. The layer stays switched on but is marked "unavailable" in the panel, a small notice shows on the map for a few seconds ("Radar isn't loading right now; try again later"), and the map, pivots and other layers carry on. One notice per layer per page visit, not one per tile. The layer retries at its next refresh, or when it's switched off and on.

| Overlay | Source | Notes |
|---|---|---|
| **Radar now** | Iowa Environmental Mesonet NEXRAD composite tiles (`mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/{z}/{x}/{y}.png`) | Every 5 minutes; the panel shows the time. A loop over the last hour (IEM's `-m05m`…`-m55m` layers) is a stretch goal |
| **Rain, last 24 h / 72 h** (radar estimate) | IEM MRMS accumulation tiles (`q2-p24h`, `q2-p72h`); *as built (H): NOAA's MRMS image service (`obs/mrms_qpe`)* | Good next to WISP's own numbers: did the gauge, the model and the radar agree? |
| **Forecast rain**, day 1 / days 1–3 / days 1–7 | NOAA WPC QPF (`mapservices.weather.noaa.gov/vector/rest/services/precip/wpc_qpf/MapServer`, `export` with `{bbox-epsg-3857}`) | A human forecaster's product; it can differ from the Open-Meteo forecast WISP uses, and the legend says so |
| **Drought Monitor** | USDM current polygons (`services5.arcgis.com/0OTVzJS4K09zlixn/.../USDM_current/FeatureServer/0/query`, GeoJSON; as built, loaded once for the area 3° around the operation's pivots) | Weekly (Thursday); the panel shows the map date. USDM's standard D0–D4 colors |

Not proposed: RainViewer (its free tier is limited) and NWS warnings (useful, but a crowded layer; maybe later for frost and freeze).

#### F. Soil survey in setup
USDA NRCS Soil Data Access (SSURGO) has both a map layer and a query API, free and CORS enabled (checked 2026-10-17: a point in the Central Sands returns "Plainfield sand, 0 to 2 percent slopes", Plainfield 90%, surface texture Sand, AWC 0.08).
- [x] **Soil layer** on the pivot picker (and as an overlay on the Map tab): map-unit outlines from the WMS (`SDMDataAccess.sc.egov.usda.gov/Spatial/SDM.wms`, layer `mapunitpoly`), visible from about zoom 13, with each unit's name on click. *(A "Soils" toggle on the picker and a layer on the Map tab. No click-to-identify, as clicks place or select pivots; the survey box lists the map units under the pivot instead.)*
- [x] **Suggest the soil type** for a pivot's fields: query the map units under the pivot's circle or arc (`Tabular/post.rest`, `SDA_Get_Mukey_from_intersection_with_WktWgs84` with the polygon from `pivotRing`). Take each unit's area share and its dominant component's surface texture, and show "Soil survey: mostly Plainfield sand (82%), some Richford loamy sand (18%) → Sand". The field form and quick setup preselect that soil type when the user hasn't chosen one, and never overwrite a choice. The user can always change it. *(`lib/soils.ts`, `SoilSurvey.svelte`: area shares from `mupolygon` intersected with the pivot's polygon in one query, about 5 s. Quick setup's fields and a new field in Setup take the suggestion until the user picks a soil; the pivot form shows it for information.)*
- [x] **Soil types reviewed** (Ben, 2026-10-17): Loamy Sand, Sandy Clay Loam, Silty Clay Loam and Muck added, and sandy loam, loam, silt loam and clay loam updated, from Wisconsin SSURGO medians and Saxton & Rawls (2006). The legacy values had no known source. Each entry in `soil_types.yml` gives both sources' values and the legacy one.
- [x] **Texture mapping** to our eleven soil types, as a table in `lib/soils.ts`, unit tested: each USDA texture to its class, with modifiers dropped (fine sand and coarse sand → Sand, loamy fine sand → Loamy Sand, fine sandy loam → Sandy Loam), muck and mucky peat → Muck, and no suggestion for peat or textures we don't have (silty clay, sandy clay).
- [x] Failure is quiet: no suggestion and a short "Soil survey unavailable" note; setup never waits on it. Outside the survey's coverage (Canada) there's no suggestion.
- [x] **About page:** a Soils section: what the soil type sets, the setup suggestion, and a table of every type's field capacity, wilting point, available water and where its values come from (`basis` in `soil_types.yml`). The Day to day section describes the Map tab.
- [x] **Thin organic surface layers skipped** (Ben, 2026-10-19): Friendship loamy sand was suggested as Muck, because its top horizon in the survey is 2 cm of leaf litter ("moderately decomposed plant material"). The surface texture is now the top horizon only for organic soils (Histosols: Markey, Seelyeville), and otherwise the first mineral horizon (`SURFACE_TEXTURE` in `lib/soils.ts`). Checked against Soil Data Access in Portage and Waushara counties: Friendship, Plainfield, Roscommon and Newson come out as their mineral textures, and the Histosols stay Muck. Minocqua muck (3 cm of muck over silt loam) now suggests Silt Loam.
- [ ] *Maybe:* show the survey's available water capacity next to the soil type's default field capacity and wilting point, as a check. Not used in the balance.

#### H. Revisions after trying it (Ben, 2026-10-17)
- [x] **No soil layer on the Map tab.** The survey's map unit codes meant little and loaded slowly. The pivot picker's layer shows **WISP's soil types** instead: the survey's polygons around the pivot (or the view, zoomed in), colored coarse to fine and labeled by the type each unit's surface texture suggests, with the unit's name on hover and a legend of the types present (`lib/soils.ts` `fetchSoilAreas`, about 5–7 s for the area around a pivot).
- [x] **Values under the pointer:** resting the mouse on the map (or tapping it, off the pivots) shows each shown layer's value there (`MapOverlays.probe`, `OverlayTooltip`). Radar: read from the same Iowa Environmental Mesonet tile the map draws, whose colors are IEM's N0Q palette (index 1 is −32 dBZ, 0.5 dBZ an index; `lib/map/radar.ts`), described as light to very heavy rain. NOAA's radar image service was tried first, but it stores rendered colors with no table back to dBZ, and its default raster is the oldest. Recent rain: NOAA's MRMS image service (`obs/mrms_qpe`), which the 24- and 72-hour layers now come from too, drawn with NOAA's own classes so the picture and the value agree (its pixel values are millimeters, checked against WISP's weather at North 160). Forecast rain: a point query on WPC's layer, giving its class (0.25–0.50 in). Drought: the loaded polygons. Where a layer has nothing, the tooltip says so ("No rain", "No drought"); outside the US, "No data outside the US" (a simplified outline, us-atlas 3.0.1 from Census Bureau boundaries, `lib/map/us-outline.json`, loaded on first use).
- [x] ~~"None" shown as light gray over the US~~: tried and removed (Ben): with values under the pointer, the gray only dimmed the map.

#### I. Pivot shapes (Ben, 2026-10-19)
- [x] **Partial circles on the map:** a partial circle has a handle at each end of its arc in the picker, dragged to set its start and end (whole degrees, at least 5° swept); the typed angles still work.
- [x] **Linear moves:** `pivots.kind` (`center` or `linear`) with `length_ft`, `travel_ft` and `travel_bearing_deg`. The picker draws a linear as a rectangle with handles on its front left and back right corners (northwest and southeast for one traveling north); dragging one keeps the opposite corner and the direction fixed, and a corner can't cross the opposite one. A round handle past its front end turns it, in whole degrees, snapping to north–south or east–west within 2° (`resizeLinear`, `snapBearing`). The pivot form and quick setup share `PivotShapeFields` (kind, map, soil survey, coordinates, sizes, arc). The Map tab, the soil survey and the other-pivot outlines draw either kind (`pivotOutline` in `lib/geo.ts`).
- [x] **Maximum sizes** (§4, pivots), enforced by `Pivot` validations, check constraints and the picker's handles.
- [x] Placing a pivot with a click zooms the picker to fit it and its handles.
- [x] **Rotated linears** (Ben, 2026-10-19): plenty of linears don't run north–south or east–west, so a linear has a direction of travel.
- [x] **Handle polish:** handles move only where the shape puts them (no flicker between the pointer and the shape); a double-ended arrow along a linear's travel, 80% of its length (`travelArrow`); cursors drawn for each handle, circling arrows for those that turn about the center and a double arrow along the drag for those that resize (`lib/map/cursors.ts`).

#### G. Ideas for later (Phase 8 polish or after launch)
- Field sectors (above).
- A **WISP weather zones** layer: the O1280 cells with the operation's pivots, colored by WISP's own 7-day rain or ET, which shows which pivots share weather and matches what the balance uses. The cell edges come from `Weather::Grid.cell_for` (ported from Ben's R code; cell width depends on the latitude ring), so they are served with the pivots and not recomputed in the browser.
- The map in the daily email (a static image per farm).
- A radar loop over the last hour.

- **Exit** *(met 2026-10-17; `bin/ci` passes, with the map, failing-layer, drought and soil suggestion tests in `e2e/smoke.spec.ts`)*: every pivot in the demo seed is drawn where it is, with its fields' badges and a popup matching their dashboard cards. The side list sorts both ways and selects with the map. The map fits the farm filter. Each overlay loads with its legend and time, and a blocked source shows its notice without breaking the map (Playwright, with the route aborted). Playwright opens the map, picks a field in the list, sees its pivot selected and follows the field link. The pivot picker suggests Sand for a Central Sands pivot (a vitest with a recorded Soil Data Access response). Editing a location updates its weather within one job cycle.

### Phase 8: Polish, beta, launch

**Order (Ben, 2026-10-22):** accessibility first (A), then the admin additions (B), then a performance check and code audit (C), before the beta. Long-lead items run alongside from now: the server request to the sysadmin ([Phase 1](#phase-1-foundation)) and recruiting beta testers.

**Next (2026-11-10; production is live at `v3.wisp.cals.wisc.edu` with SES out of the sandbox):**
1. **Weather corrections (E)**, before any beta tester sees a number: it moves every field's ET by about 11%, and the backfill keeps one method per season.
2. **Weather update polling (C, follow-up)**: small, and it shows on every dashboard visit.
3. **RDS restore test (D)**: once, before real growers' data is on the server.
4. ~~**Time travel (F)**~~ (built 2026-11-10): the beta runs over the winter, when every season has ended, so testers and demos can only see an in-season page this way.
5. **Beta readiness (G)** (added 2026-11-11, from a UX review; all before launch): seasons that keep their history, fields with several plantings, field boundaries and import, season end dates, crops without a curve, daily entry, irrigation systems other than pivots, wording, new crops, all operations at once and a public example farm. On the `beta-readiness` branch; G.1–G.4 and G.9 before any tester sets up a field.
6. **Closed beta (D)**, then launch by ~Mar 20, 2027. The screen reader walkthrough (A) and wording reviews happen alongside.

Canopy and LAI research continues without outside reviewers (Phase 6.7, Q2): our own analysis, published literature, and readings collected in the 2027 season (After launch).

Done so far:
- [x] Admin users list (`/admin/users`): a searchable, sortable table (`DataTable`) of every account with its farm, pivot and field counts; delete unconfirmed accounts from the list. Each account's page shows its attributes (not its secrets), its groups and members, and its farms, pivots and fields, with a delete button (with confirmation) except for your own or another admin's account.
- [x] Group members (A8, Q8): an operation page (`/operation`) for the current group, with its name and rainfall setting (moved from Setup), its members, your other operations, creating one, and deleting it. Owners add people by the email they sign in with (an existing, confirmed account; no invitation tokens) and they get an email; owners change roles and remove members; anyone can leave. A group always keeps an owner, and someone left with no group gets a new one of their own.

#### A. Accessibility (WCAG 2.1 AA)

UW–Madison is a public entity, so the DOJ's ADA Title II rule (2024) applies: WCAG 2.1 AA for web content, due April 2026 for large public entities. WISP 3 launches conforming. Done before the beta so testers see the final interface. Audit first, writing the findings to `docs/accessibility.md` (page, issue, WCAG criterion, fix), then fix them.

- [x] **Automated checks in CI:** `@axe-core/playwright` in the e2e suite, scanning every page (public, auth, dashboard, map, field, daily entry, setup, field groups, alerts, operation, settings, admin) in light and dark, with the WCAG 2.1 A/AA rules. No violations, or each exception listed with its reason. *(`e2e/accessibility.spec.ts`; the first run's findings, all fixed, are in `docs/accessibility.md`.)*
- [x] **Keyboard:** every action reachable and visible focus everywhere. In particular the `EditableCell` grids (move between cells, edit, Escape, save), `DataTable` sort headers, the map's popups and phone sheets (focus moves in, Escape closes, focus returns), the side list and the overlay panel, menus and the operation switcher. A skip link to the main content. *(Done 2026-10-22: skip link, grids as one tab stop, the map panel and layers, the account menu, names in Setup and daily entry; `e2e/keyboard.spec.ts`, findings in `docs/accessibility.md`.)*
- [x] **The pivot picker:** typed coordinates, sizes and angles (`PivotShapeFields`) are the keyboard alternative to the handles; check they cover everything the handles do and say so in the picker. *(Done: they do; the picker now says so.)*
- [x] **Charts:** a table alternative for each chart (the field chart, weather panels, canopy plots), as a "Show as table" toggle or a visually hidden table, plus a text summary (`aria-label`) on each chart. *(Done: weather panels get a "Summary and data" disclosure generated from their definitions; the field chart's are the daily and forecast tables and the summary card; `docs/accessibility.md`.)*
- [x] **Not by color alone:** status badges, pivot fills and the "Needs water within" dimming, provenance (entered vs modeled), forecast shading, soil-type colors. Each also has a label, a pattern or text. *(Done: the map's zoomed-out dots now carry the status icon; the rest already had words, icons, weight or outlines; chart series are also in the "Summary and data" tables.)*
- [x] **Contrast:** text, including muted text ("model 0.35"), placeholders and disabled controls, at 4.5:1; controls, focus rings and chart lines at 3:1, in light and dark. *(Text checked by axe on every page in light and dark; status text and fills fixed in the first pass, the email's green too. Focus rings and chart colors were checked by hand: brand-500 rings are above 3:1 on both surfaces, and the chart palette was validated in Phase 4.)*
- [ ] **Screen readers** (NVDA or Orca, and VoiceOver on a phone): page titles, heading order, landmarks, form labels and errors tied to their inputs (`NumberField`'s unit), flash messages and grid saves announced (live region), the glossary `Term` tooltips reachable, and icons labeled. *(By hand, Ben or a tester: the checklist in `docs/accessibility.md`, about an hour. The glossary popups' known gap is fixed.)*
- [x] **Reflow and zoom:** 320 px wide and 200% text with no lost content or sideways page scroll; the grids may scroll inside themselves. *(Done: the dashboard's card grid overflowed at 320 px; `e2e/accessibility.spec.ts` now checks every page at 320 px and with 200% text.)*
- [x] **Motion:** map fly-tos and transitions respect `prefers-reduced-motion`. *(Done: CSS transitions and animations cut short, Svelte's slides through `lib/motion.ts`, the map list's smooth scroll; MapLibre already jumps instead of flying.)*
- [x] Emails: the digest and account emails readable without images, with real headings and link text. *(Done: `lang`, a viewport and the subject as title in the layout; the digest's heading levels follow the sections shown; its OK green darkened. No images; plain-text parts exist.)*
- [x] An accessibility statement on the About page with a contact for problems. *(Done: About › Accessibility. Wording to review; add a link to UW–Madison's digital accessibility policy if wanted.)*
- **Exit:** axe passes in CI on every page, the keyboard and screen reader walkthroughs in `docs/accessibility.md` find nothing open, and every chart has its table.

#### B. Admin: monitoring and impersonation

**Design (2026-10-22).** No new tables: the health check reads what's already stored, and impersonation lives in the session.

- [x] **1. Health check** *(Built 2026-10-22, then revised the same day after Ben's review, below.)*
- **Revised (Ben, 2026-10-22):** report the state of the data, which clears itself, rather than every failure along the way (as agweather's missing-data email does).
  - **`HealthCheck`** (`app/services/health_check.rb`): **failed jobs since the previous check** (Solid Queue's failed executions, by class, with the latest error from its JSON `error` column; only under the `:solid_queue` adapter), and **missing weather**: active cells with days missing, or without ET or precipitation, in the last 7, or a forecast over a day old, and any cell whose fetch failed in the last day. The "digests due but unsent" check is dropped.
  - **`DailyDigestJob`** carries on past a user whose digest fails, then fails itself at the end (`DailyDigestJob::Incomplete`, "3 of 120 daily emails failed …"), so the failure is a failed job; retrying it sends only to those who missed out. Before, per-user errors went to `Rails.error.report`, which nothing listens to.
  - **Failed executions are discarded after 7 days** (`config/recurring.yml`), so nothing piles up and no retry/discard screen is needed.
  - **`HealthCheckJob`** (7 am) runs the check, **stores the result** (`HealthCheck.run` → `Rails.cache`, Solid Cache on the servers) and emails the admins when there are problems. The admin weather page shows the stored result ("Last checked … · Re-run health check", which re-runs it without the email, `Admin::HealthChecksController`) instead of checking on each visit. Past 26 h without a run (where jobs run), the page says the job runner may be stopped.
  - **`/up`** (`HealthController`) returns JSON safe to show publicly: `status` (`ok`, `degraded` when the last check found problems or is overdue, `down`), the time, the deployed commit, the database, and the last check's time, whether it's overdue and a count per problem kind (no cells, errors or users). 200 unless the database is down (503), so an uptime monitor can alert on `"status":"degraded"`.
  - Found in review: the first version read `exception_class` and `message` methods that Solid Queue's failed executions don't have (the details are in `error`), which would have raised on the servers; specs stubbed the method, so a spec now runs the mapping on stand-in rows.

- [x] **2. Impersonation** *(Done 2026-10-22: `Admin::ImpersonationsController`, `ImpersonationsController`, `impersonator` in `ApplicationController`, the bar and tab-title prefix in `AppLayout`; the Settings page hides deleting the account too. `e2e/impersonation.spec.ts` signs in as the seeded grower jane@example.com, and the axe scan covers the bar.)*
- **Start:** `POST /admin/users/:id/impersonation` (`Admin::ImpersonationsController#create`, admins only, so a 404 for anyone else). Refused, with a flash, for yourself and for another admin. It stores `session[:impersonator_id]` (the admin) and `session[:impersonated_id]` (the user) and the admin's `session[:group_id]` to restore later, clears `session[:group_id]` so the user's own operation is chosen, sets `request.env["devise.skip_trackable"] = true` so the user's sign-in count and times don't change, `sign_in(:user, user)`, and redirects to the dashboard. Logged: `Rails.logger.info("Impersonation started: admin #{admin.id} as user #{user.id}")`.
- **Stop:** `DELETE /impersonation` (`ImpersonationsController#destroy` under `AuthenticatedController`, as the signed-in user is no longer an admin). It checks the stored admin still exists and is an admin, signs them back in (again without trackable), restores their group, clears the keys, logs the end and redirects to that user's admin page. If the admin is gone, it signs out.
- **Signing out** while impersonating ends both (Devise's sign-out clears the session).
- **Current state:** a helper `impersonator` (in `ApplicationController`, also a `helper_method`) returns the admin `User` only when `session[:impersonated_id] == current_user&.id` and `session[:impersonator_id]` is an admin, so a stale key (after a timeout and a remember-me sign-in) never shows the bar; stale keys are cleared.
- **Shared prop:** `auth.impersonator` in `InertiaController` (`{name, email}` of the admin, or null), typed for the frontend (Typelizer, or the shared props type wherever `auth` is typed).
- **The header:** in `AppLayout`, above the branding bar, a full-width bar that stays at the top as the page scrolls (`sticky top-0 z-50`), in a color no status uses (a violet: new tokens `--color-impersonation` / `--color-on-impersonation` with a dark-mode value, contrast at least 4.5:1, in `application.css`), with `role="status"`: "Signed in as **Jane Grower** (jane@example.com) for support" and a "Return to admin" button (an Inertia `<Form>` or `router.delete` to the stop route). On the Map tab's full-height layout it takes its height from the page rather than covering the map. The skip link stays the first stop. The tab title gets a prefix ("As jane@example.com · ") while impersonating, so another tab shows it too, set from the layout on each page change.
- **Blocked while impersonating** (a `before_action :forbid_while_impersonating` with a flash: "That's turned off while you're signed in as someone else"): changing the email or password or deleting the account (`Users::RegistrationsController#update`, `#destroy`), sending the test digest (`AlertsController#test_email`), and starting another impersonation. The Settings page hides the email and password forms while impersonating, with a note why. Data entry, setup, profile settings and alert settings stay allowed (the support case).
- **On the admin user page:** a "Sign in as this user" button (with a confirm: "You'll see WISP as Jane until you return to admin"), absent for yourself and other admins.
- **Specs:** request specs for start (admin only; 404 otherwise; refused for self and admins; trackable untouched), the shared prop on a later page, each blocked action refused, stop restoring the admin and their operation, sign-out ending both, a stale key not showing the bar. Playwright: an admin signs in as the demo grower, sees the bar on the dashboard, a field page and the map, and returns to the admin page. Add the impersonation bar to the axe scan (one page while impersonating).

- [ ] CSV export of users, and announcements (shown in the app, replacing the legacy blog): after the beta, if still wanted.
- **Exit:** a failed job or a stale cell on staging sends the email the next morning; an admin can sign in as a beta tester, sees the header on every page, and returns to the admin pages.

#### C. Performance check and code audit

Measure first; fix what the numbers show. The app already feels fast enough (Ben, 2026-10-22), so the targets below are nice to have, not launch requirements: a miss gets a note here, and a fix only if it's cheap or users notice.
- [x] **A large operation:** a seed (`demo:seed`-style) with 100 fields on 60 pivots across 4 farms, with a season of entries. Time the dashboard, map, field page, daily entry and digest build, and count queries (none per field: `FieldStatuses.for` preloads). Targets: dashboard and map server time under 500 ms, a field page under 300 ms. (Checked 2026-10-22, on the e2e database with a scratch seed: 100 fields on 60 pivots in 30 weather cells, every planting in season, Apr 1 to today, entries every 4 days, canopy readings; test environment on a laptop, Ruby without YJIT. Query counts don't grow with fields: dashboard 1,070 ms and 19 queries, map 1,250–1,360 ms and 20, field page 74 ms and 24, daily entry 44 ms, setup 63 ms, pivot page 47 ms, one user's digest built in 1.0 s with 18 queries. **Dashboard and map miss the 500 ms target**: it's Ruby arithmetic, not the database: of the dashboard's time, the 100 balances (~225 days each) take ~470 ms and the 31-member ensembles ~350 ms; loading takes ~160 ms and serializing ~50 ms. Props: dashboard 336 kB (37 kB gzipped; mostly each card's 16-day projection), map 354 kB (39 kB), field page 221 kB (12 kB). Left as is for now; if growers with many fields notice, first make sure the servers' Ruby is built with YJIT (needs rustc when ruby-build runs; Rails turns it on in production), then trim allocations in `WaterBalance.run`/`EnsembleProjection` or cache statuses per group and day.)
- [x] **The browser:** Lighthouse with mobile throttling (rural connections) on the landing page, dashboard, field page and map. Bundle sizes from `vite build` (ECharts imports only what's used, MapLibre stays on demand, the `routes` chunk size), and fonts and images. Targets: LCP under 2.5 s on throttled 4G, no main bundle over about 300 kB gzipped. (Checked 2026-10-22, with Playwright's Chromium and CDP throttling as Lighthouse's mobile setting: 562 ms RTT, 1.47 Mbps, 4x CPU, phone viewport, first visit, against the large operation above. Landing page FCP/LCP 2.5 s, 181 kB transferred; dashboard LCP 3.6 s (1.1 s of it the server); map 4.2 s; the field page's heading 5.3 s, now 3.7 s since Chart loads ECharts on mount instead of the page waiting for it. Repeat visits 0.7–2 s. **LCP misses 2.5 s on the signed-in pages**, mostly server time and the chunk waterfall (entry, then page chunk, then its imports). Bundles (gzipped): the entry 26.5 kB plus shared chunks 70 kB and CSS 12 kB, so about 110 kB before a page; the largest page chunk is 18 kB; `routes` 1.6 kB. ECharts is tree-shaken (line, bar and seven components) and 204 kB, loaded only when a chart mounts; MapLibre 288 kB (and its worker) only on the map, pivot form and quick setup, with its CSS; the US outline (41 kB) only on the map. Fonts: two latin woff2 files of 30 kB (latin-ext only when needed); no raster images.)
- [x] **Database:** indexes for the lookups the pages use (EXPLAIN on the slowest queries), and `weather_forecasts` pruning working. (Checked 2026-10-22: the slowest queries on these pages are the preloads (field entries and weather days for the season, the latest forecast per cell), each under 7 ms and under 2 ms in EXPLAIN ANALYZE; each has an index leading with its key (`field_id, date`, `weather_cell_id, date`, `weather_cell_id, issued_at`), though at this size Postgres scans the small tables instead. `ForecastPruneJob` runs weekly from `config/recurring.yml` and has a spec; with 63 forecasts of each kind per cell the latest-forecast query still takes 1.5 ms. No index added.)
- [x] **Code audit:**
  - Tenancy: every controller loads group records through `Current.group` and has its cross-tenant spec; owner-only actions have `require_owner`.
  - Brakeman and `bundle audit`, `pnpm audit`; Rack::Attack limits on sign-in, codes and magic links.
  - Dead code and unused components, and TODOs.
  - Duplicated logic between Ruby and TypeScript (`Outlook`/`lib/outlook.ts`, pivot size limits) still matching, ideally with a shared spec fixture.
  - CLAUDE.md and the docs matching the code.
  - (Done 2026-10-22. Tenancy held: no unscoped lookup outside `Admin::`, Q8's owner-only actions all have `require_owner`, and `FieldGroupMember` and `PivotIrrigation` also refuse another group's or pivot's fields; added cross-tenant specs for season copy, the pivot form's `farm_id`, the field page's `planting_id`, pivot irrigation `field_ids` and field group updates. Brakeman's two warnings (`permit!` in bulk daily entry, which also raised a 500 on a malformed value) fixed; `bundle audit` clean; `pnpm audit` one moderate, `postcss-selector-parser` under `@tailwindcss/typography` (build time only). Fixed: the sign-in link's token and code were in the log, as Active Job logs job arguments (`SecretMailDeliveryJob`). Dead code removed (`overlayById`, `WeatherDay#degree_days`, `DegreeDays.cumulative`). Mirrored constants (pivot limits, `LEAD_DAYS`, `READING_EVERY`, `FULL_COVER_PCT`) are now checked by `spec/models/frontend_constants_spec.rb`; `Outlook` and `lib/outlook.ts` still agree, without a shared fixture. **Resolved after review (Ben, 2026-10-22, recommended resolutions):** a sign-in link that confirms a never-confirmed account now clears its password, so someone who signed up with another person's email can't keep a way in (`User#confirm_by_magic_link!`); password sign-in is limited to 10 tries per account per 15 minutes from any address, a limit rather than a lockout (Rack::Attack `sign_in/email`, reading Inertia's JSON); the sign-in link's and unsubscribe link's tokens are query parameters, which the request log filters; a Content Security Policy allows scripts only from WISP (the theme script has a nonce; images and connections allow https for the map's services); `postcss-selector-parser` is overridden to 7.1.6 (`pnpm-workspace.yaml`, identical CSS); missing GDD before emergence, season weather totals without weather and MRMS NoData are shown as missing, not zero; soil depth labels and available water go through `units.ts`. **Accepted as is:** sign-up and adding a member say whether an email has an account. Sign-up has to (the address is taken), adding a member is for owners only and needs the address, and sign-in, password reset and links don't reveal it (`config.paranoid`). The water balance treating missing rain and irrigation as none is legacy behavior and stays.)
- [x] **Weather update polling** (Ben, 2026-11-10: on signing in as the demo user, both cards said "Updating weather…", then the page seemed to refresh as a whole). What happens now:
  - **Most visits show the spinner.** `WeatherCell.keep_current` queues a `WeatherUpdateJob` for every cell on the page once per `UPDATE_THROTTLE` (15 min), whether or not anything is missing, and the job marks the cell as updating. The forecast is refreshed at 5, 11 and 17 h and is stale after 3 h (`STALE_AFTER`), so most visits do fetch a new forecast, but the page already has a usable one and the new one changes little. "Updating weather…" should mean that what's on the page is incomplete.
  - **It isn't a page reload.** The dashboard and map reload only the `farms` prop (`router.reload({ only: ['farms'] })`), and the cards are keyed, so they update where they are. When one pivot's weather lands first, its cards change and the others keep their spinners. But it's one prop for the whole operation, so every 5 s poll reruns `OperationOverview` (every field's balance and ensemble: about 1 s for the 100-field test operation) for up to 3 minutes. The field page reloads all its props the same way.
  - **Proposed:** (1) Split "missing" from "refreshing": mark a cell as updating, and show the spinner, only when it has no weather, has gaps in the season, or its forecast is past a day old; a stale but recent forecast is refreshed quietly and the next visit gets it. (2) Poll a cheap endpoint for the updating cells (`GET /weather_updates?cells=…`, reading only the cache) and reload `farms` once each time a cell clears, instead of rebuilding the overview every 5 s. Reloading one pivot's cards alone isn't worth a per-pivot prop.
  - *Done 2026-11-10, as proposed:* `WeatherCell#incomplete?` (no deterministic forecast within `INCOMPLETE_AFTER`, a day, or a day missing since `backfill_start`); `keep_current` queues a complete cell's update with `quiet: true`, which doesn't mark the cell. `GET /weather_updates` (`WeatherUpdatesController`, the group's pivots only) lists the updating pivot ids from the cache; `poll` checks it every 5 s and reloads once one of the page's pivots has landed, not checking again until that reload finishes.
- [x] **The blank field chart in development** (Ben, 2026-11-10): the chart's box was empty, then the whole page reloaded and the chart appeared. Most likely Vite's dependency optimizer: `Chart` imports ECharts on mount, Vite meets it for the first time, prebundles it and reloads the page (its terminal says "new dependencies optimized … reloading"). Check for that message; if so, add the ECharts modules and `maplibre-gl` to `optimizeDeps.include` in `vite.config.ts` *(done 2026-11-10, on that diagnosis; Ben to confirm the reload is gone)*. Production loads the prebuilt chunk and doesn't reload; there the box is empty only while the ECharts chunk loads, as designed above.
- **Exit:** the large operation is measured against the targets (misses noted), Lighthouse findings are fixed or listed, and the audit's findings are fixed or have an entry here.

#### D. Beta and launch

- [ ] Empty states and an onboarding tour (once the beta shows where people get stuck).
- [x] **Data downloads where they fit** (Ben, 2026-10-22): a CSV link in each weather chart's "Summary and data" (that panel's table), and one for all weather variables for the pivot's cell in a single CSV; look for other tables that would benefit (the field page already has Export CSV). In inches and °F as stored, like the field export. (Done 2026-10-26. Every export opens with PRISM-style frontmatter (Ben): the title, what it covers, units, who exported it and when, the source and the About link, then the data. **Season report** on Setup (legacy's end-of-season report, for the whole operation, one CSV, depths in inches only (Ben)): a summary in the frontmatter, then Fields (each planting's crop, dates and season totals, days irrigated, days at or below AD 0, AD and moisture at the end, notes), Irrigation by pivot (its fields' irrigation averaged by area) and Weather by zone (precipitation, reference ET, GDD and temperatures over its crops' seasons). **Weather:** each chart's data from its "Summary and data" (built in the browser, as stored), and all of a pivot's weather variables for the season from the weather section on the pivot and field pages (`/pivots/:id/weather?year=`). **Pivot irrigation** list as CSV on the pivot page. The field export gained the frontmatter. Left out: the daily entry and field group grids (entry tools; the field export has their values).)
- [ ] Methods detail for the About page (Phase 6.5 "Later").
- [ ] Closed beta with a handful of growers or extension agents on staging, each setting up their own operation from scratch (this validates onboarding as well as the app).
- [ ] New production server provisioned (§12), deploy rehearsed, backups and restore tested.
  - [x] AWS resources ready (CALS IT, 2026-10-27): EC2, RDS, ECR, SSM. The `wisp3` role and databases created.
  - [x] The Docker deploy (2026-10-28): `Dockerfile`, `config/deploy/compose.production.yaml`, `bin/production` (push, deploy, status, logs, console), production credentials (`secret_key_base` only), RDS TLS in `database.yml`, SMTP from the environment; the image checked against a local Postgres 18 (migrations, reference data, `/up`, assets, the jobs scheduler, YJIT). The Capistrano production stage removed.
  - [x] The deploy simplified (2026-10-29): images built on the server from a git checkout, settings in a hand-kept `.env`; no ECR, SSM or SES, so nothing needs AWS permissions beyond SSH.
  - [x] `.env` on the server and the first `bin/production deploy` (2026-10-29), at `54-159-70-187.sslip.io` until campus DNS (ports 80/443 were already open).
  - [x] A temporary campus hostname: `v3.wisp.cals.wisc.edu` (2026-10-30).
  - [x] The first admin account (docs/deployment.md, step 6).
  - [x] Production mail through SES (docs/deployment.md, step 7): SMTP credentials, the sender identity verified with DKIM, production access out of the sandbox; `SMTP_*` in `.env`, a test checked for `dkim=pass`.
  - [ ] Restore an RDS snapshot to a scratch instance once, and check the app against it.
- [ ] Legacy goes read-only (sign-ups disabled, banner) and moves to its legacy hostname; DNS switch; **launch by ~Mar 20, 2027** (§13).
- **Exit:** WISP 3 live on the new server before April 1; announcement emailed to legacy users from the legacy app (new address, create a new account, sign-in links, setup guide).

#### E. Weather corrections (D12, §8.5; before the beta)

**Build plan (2026-11-10, for a new session).** On a feature branch (`weather-corrections`): it's wide (the fetch, aggregation, schema, About page), likely more than one session, and ends with a backfill that changes every field's ET in production, so it's checked on staging before it merges. §8.5 has the method; this is the order and the details found reading v2 (`../agweather2` at `bbb0a6d`).

**What v2 does that WISP doesn't yet** (`agdata.sources.openmeteo.fetch` and `correct`, `agdata.shortwave.correct_w_m2`, `agmodels.weather.et0_hourly_series`):
- It **merges the models hour by hour, per variable** (NBM's hour if present, else best_match's), then corrects and computes ET0 from the merged hours. WISP's `Weather::Daily.from_hourly` merges *days*: each daily column comes from the first model with enough hours that day. ET0 from hourly inputs needs the hourly merge, so it comes first.
- It asks in **UTC** (`timezone=GMT`, `timeformat=unixtime`, `wind_speed_unit=ms`). The corrections need each hour's UTC end (solar time, the clear-sky radiation). WISP asks with `timezone=auto` for local days and keeps no offset (`Hourly` drops `utc_offset_seconds`), and one offset per response is wrong across a DST change anyway. Ask with `timeformat=unixtime` (keep `timezone=auto` so the date range stays local) and group hours into local days with the cell's zone (`WeatherCell#time_zone`), which handles DST.
- **Dark hours:** §8.5 says hours with Rso ≤ 1 W/m² stay as they are, but v2's code gives them clearness 0 and so the darkest bin's factor (0.6171): a dark hour's 0 stays 0, a twilight hour's few W/m² are scaled. Follow the code. Where pressure is missing, Rso uses 97 kPa.
- Rso uses the elevation from the hour's pressure (FAO-56 eq. 7 inverted, `elevation_from_pressure_m`), not the cell's elevation; NBM has no pressure, so best_match's fills it in the hourly merge.
- RH is derived from temperature and the corrected dew point (Tetens, `relative_humidity_percent`), replacing Open-Meteo's `relative_humidity_2m`; v2's map is applied to the *dew point* (`calibration.map_humidity`: RH from T and Td, mapped, Td recomputed with T kept).

**Steps:**
1. **Reference tables.** Copy `openmeteo_shortwave_correction.json` and `openmeteo_rh_map.json` from `packages/agdata/src/agdata/data/` to `db/reference/weather_corrections/`, with a README naming the v2 commit, each table's `version`, `fitted` and `source`, and the labels v2 uses (`openmeteo-shortwave v1`, `openmeteo-rh v1`; ET0 `et0-fao56 v1`). A small `Weather::Corrections` reads them once. The RH map's array is `map[season][lead group][solar hour][RH grid]` with one lead group; check its `season_day_of_year`, `rh_grid` and solar-hour bins against `map_rh` before porting.
2. **FAO-56 in Ruby** (`Weather::Fao56`, plain functions on arrays of hours): saturation and actual vapor pressure, RH ↔ dew point, Δ, γ, wind 10 m → 2 m, extraterrestrial radiation per hour (eq. 28, **the hour angle wrapped to ±12 h**), solar elevation at mid-hour, Rso (eq. 37), the cloudiness ratio carried from the last hour with the sun high enough, net radiation (eq. 38–40, hourly σ), G = 0.1 Rn by day and 0.5 Rn by night, and eq. 53 with negatives clamped to 0. Port `packages/agmodels/tests/test_weather.py` as `spec/services/weather/fao56_spec.rb`: FAO-56 Examples 2–5, 8, 9, 14 and 19 (day and night hours), the Ra wrap test (24 hourly Ra of a solar day sum to eq. 21's daily Ra at longitudes −122, −89.4, −75, 0 and 100), missing inputs giving nil, heavy cloud not turning net longwave into a gain, day length at the equinox and the poles.
3. **Fetch the inputs.** Add `shortwave_radiation` and `surface_pressure` to `OpenMeteo::VARIABLES`, `timeformat=unixtime` (and `utc_offset_seconds` kept on `Hourly`, for checks), and update the recorded responses in `spec/fixtures/files/open_meteo` (re-record, or add the two variables to them) and `spec/support/fake_open_meteo.rb`. Check the rate limiter's weight still matches (two more variables).
4. **Hourly pipeline** (a new step between the client and `Weather::Daily`): merge the models' hours per variable; keep the raw shortwave, dew point and RH; correct shortwave (step 1's table, by clearness), then dew point (the RH map, by season and solar hour); derive RH and FAO-56 ET0 from the merged, corrected hours. Then `Daily` aggregates these hours by local day as now, plus the new columns. The archive endpoint (ERA5) isn't corrected (v2 didn't fit it); WISP doesn't use it for the water balance today.
5. **Schema** (one migration): `weather_days` gains `shortwave_mj` (daily total, MJ/m²), `shortwave_raw_mj`, `et0_openmeteo_in`, `dew_point_raw_f`, `rh_mean_raw_pct`, `rh_min_raw_pct`, `rh_max_raw_pct` and `corrections` (jsonb array of labels, default `[]`). `et0_in` becomes the FAO-56 value; `dew_point_f` and `rh_*_pct` the corrected ones. `WeatherDay::VALUE_COLUMNS`, the forecast payload's day keys (deterministic forecasts go through the same `Daily`, so they're corrected too) and serializers follow; Typelizer regenerated.
6. **Check against v2.** A script in v2 (`uv run python`, kept in `docs/weather-corrections/` with its output) runs `openmeteo.correct` and `_derive` on v2's recorded responses (`packages/agdata/tests/fixtures/openmeteo_historical_{ncep_nbm_conus,best_match}.json`: three June 2025 days at Stillwater, OK, already UTC, unixtime, m/s) and writes each hour's corrected shortwave, dew point, RH and ET0 to `spec/fixtures/files/weather_corrections/v2_expected.json`, with the inputs. A spec feeds the same responses through WISP's pipeline and matches every hour (shortwave and ET0 within 0.1%, RH within 0.1 point). This is the test that the port is right; the Example 19 tests check the formulas.
7. **The ensemble (Q10).** First check the ensemble API returns `shortwave_radiation`, `surface_pressure`, `temperature_2m`, `dew_point_2m` and `wind_speed_10m` per member for `gfs_seamless`, and what it costs: each member counts as a variable, so five more variables take a cell's ensemble from about 7 calls a refresh to about 24 (`RateLimiter.weight`). If both are fine, compute each member's ET0 with the pipeline above (shortwave and RH corrections included); otherwise scale each member's Open-Meteo ET0 by the deterministic forecast's corrected/raw ratio for that day. Record the choice in Q10.
8. **Comparison.** Re-run `bin/rails weather:compare` (`docs/weather-comparison.md`) and the irrigation-count comparison of §8.4 with the corrected ET0, and write the shift up for users (ET about 11% lower than WISP's 2026 numbers, about 7% below the old API's; Q9: used as is).
9. **Transparency.** An About page section, "Weather corrections", built from the reference files (source, variable, method, fitted against, version, fitted date, evidence, linking v2's `docs/validation-openmeteo.md`), the same table on the admin weather page, the corrections in the weather CSV frontmatter (`WeatherCsv`, `PlantingCsv`, `SeasonReportCsv`, and the browser's `panelCsvRows`), "corrected" in the ET, shortwave and humidity chart tooltips with a link to the section, and a changelog line. Glossary: reference ET (if not there), shortwave radiation.
10. **Backfill** (`bin/rails weather:recorrect`): WISP keeps no hourly data, so refetch every stored day of every cell with a pivot from the historical-forecast API in `BACKFILL_CHUNK_DAYS` runs, overwriting final days too, through a job per cell so the rate limiter paces it. Count the calls first (cells × days × variables; about 200 days × a few dozen cells in production) and run it at night. Forecasts refresh themselves within hours. Run on staging first, compare a few fields' season ET before and after, then production after the deploy.
11. **Start the forecast archive** (below), once corrected forecasts are being stored.

Checklist:
- [x] Reference tables and their README (1). *(`db/reference/weather_corrections/`, with `corrections.yml` describing each for the About page; `Weather::Corrections` applies them and matches v2's `correct_w_m2` and `map_humidity` on 300 random hours.)*
- [x] `Weather::Fao56` with v2's tests (2).
- [x] The two new variables and UTC hours from the API; recorded responses updated (3). *(`relative_humidity_2m` and `vapour_pressure_deficit` are no longer asked for: RH and VPD are derived from temperature and the corrected dew point, so the request stays at 17 variables and the rate-limit weight is unchanged.)*
- [x] The hourly merge, corrections and ET0 before `Daily`; the new columns (4, 5). *(`Weather::Hours`; each day's `corrections` lists a label only where its column has a value.)*
- [x] The spec against v2's computed values (6). *(`spec/services/weather/v2_match_spec.rb`: every hour matches to floating point.)*
- [x] The ensemble's ET0 (7, Q10): scaled by the deterministic forecast's ratio.
- [x] `weather:compare` and the irrigation-count comparison re-run; the shift documented (8). *(2026-11-10, `docs/weather-comparison.md`, 12 Wisconsin points, April–September 2025 and 2026; the report now has WISP 2026 (NBM then best_match, Open-Meteo's ET0) and WISP corrected as sources, and ET by month.)* Results:
  - **ET0:** corrected is 0.89 × WISP 2026's (11% lower, as v2 predicted) and 0.91 × AgWeather's (v2 predicted about 0.93). By month against AgWeather: April–May 1.04 (WISP 2026: 1.15–1.17), June 0.92, July–September 0.82–0.87 (WISP 2026: 0.93–0.99). The old API ran high against the stations in midsummer and low in spring (§8.5), and the corrected ET0 follows the stations, so the gap to AgWeather is largest at full cover.
  - **The standard potato field:** 3.3 fewer irrigations a season than WISP 2026 (range 2 to 5) and 4.5 fewer than AgWeather (range 2 to 10), about 2.5–3.4 in less water. The first irrigation moves from 10 days before AgWeather's to 4 days before, so most of the early-irrigation puzzle (§8.4, TODO.md) was the spring shortwave bias.
  - **What it means:** the percent-cover table (§5.4) at full cover was fitted to the old API's midsummer ET, about 1.2 × station ET0; with corrected ET0 it gives a full-cover Kc near 1.0 against FAO-56's 1.15–1.20 for these crops, so WISP 3 likely under-counts midsummer crop water use by 10–20% until the table is refit (After launch). Q9 chose corrected ET0 as is; this measures its cost. **Needs Ben's decision before the beta (Q11).**
- [x] The corrections table on the About page and the admin weather page; CSV frontmatter and chart tooltips name them (9). *(About › Weather, with a "What's changed" section for the changelog; `WeatherCorrectionsTable` from `corrections.yml`; the weather panels gain a solar radiation chart; a corrected panel's tooltip says "Corrected" only on days whose `corrections` list it, as stored days before the backfill aren't; the weather CSV adds the uncorrected values and each day's corrections; glossary: solar radiation.)*
- [ ] Backfill: every stored day refetched and corrected, so every season uses one method; staging, then production (10). *(Built: `bin/rails weather:recorrect` counts the cells, days and calls, and with `CONFIRM=yes` queues a `WeatherRecorrectJob` per cell with a pivot; `Fetcher#recorrect` refetches days before the refresh window whose corrections aren't current, final ones too, so a rerun resumes. Rehearsed on the dev database 2026-11-10: 3 cells, 610 days, about 184 calls; April–September 2026 ET0 went to 0.89 of before at each cell, Open-Meteo's own ET0 unchanged by the hourly merge, no day left uncorrected. Staging and production remain, after the merge and deploy.)*
- [x] **Keep a daily forecast archive** (Ben, 2026-11-10; built: `ForecastPruneJob` keeps each cell's first *corrected* issue of each kind per local day, so the archive starts by itself once corrected forecasts are stored), for forecast accuracy tracking (After launch) and time travel's replay (F): `ForecastPruneJob` keeps, besides the latest 14, each cell's first deterministic and ensemble issue of each day (from the 5 am refresh) for good. A few kB to tens of kB a cell a day; at 100 active cells, well under 1 GB a year. Start before the 2027 season, after the corrections, so the archive is all on one method (members scaled by the deterministic ratio, Q10, each issue recording its corrections).
- **Exit:** WISP's ET0 matches v2's for the same hours; every stored day says which corrections it went through; the About page lists them; the shift is documented; staging and production are backfilled.

#### F. Time travel on the field page (built 2026-11-10, except the archive replay)

**Why:** to show what WISP says mid-season. Demos, the About page's examples and a beta that runs over the winter (when every season has ended) can only show an ended season today.

**Idea:** a rewind-clock button on the field page picks a date in the planting's season; the page then shows what it would on that day, under a persistent banner ("Viewing this field as of July 15, 2026 · Return to today"). Only the field page; the dashboard, map and digest are unaffected.

**Why it's feasible:** the engine already takes `today:` everywhere (`PlantingStatus`, `PlantingBalance`, `DailyInputs`, `OperationOverview`), and the field page gets its "today" from the server rather than the browser's clock. So most of it is passing a different date.

**Proposed shape (to keep the complexity down):**
- **A URL parameter**, `/fields/:id?as_of=2026-07-15`, not a session setting: it can't leak into other pages or tabs, reloading keeps it, a demo link can be shared, and "Return to today" is a link without it. The controller validates it (a date in the planting's season, before today) and passes it as `today:`.
- **Read-only:** no editing in the grids, no forms or setup links, no weather update polling. One `readonly` flag on the page, passed to `EditableCell` and the forms. Nothing that writes needs to know about time travel.
- **The data as it is now, cut at that date:** entries, irrigation and canopy readings after the date are left out; those on or before it are shown as they are now. WISP keeps no history of edits, so this isn't exactly what the page showed then (a week of rain entered late shows anyway), and the banner says so.
- **Tasks and the canopy check** as of that date (they already take `today`).
- **Weather panels** end at the date.

**Decided (Ben, 2026-11-10):**
1. **The projection:** where the forecast issued on that day was archived (Phase 8 E, from 2027), the page replays it, ensemble included; otherwise (2026 seasons) it uses **the weather that actually followed**, labelled "what happened next" rather than a forecast, with no ensemble band. Open-Meteo can't fill the gap: its historical-forecast API is stitched from each run's first hours (close to observed weather, not a 16-day forecast), and its Previous Runs API reaches only 7 days ahead and has no ensemble.
2. **The projection shows what happened** (Ben, 2026-11-10, reversing the first build, which left out entries after the date): the days that followed take the rain, irrigation and soil moisture entered for them, so irrigation applied then shows. Canopy readings after the date stay out (they'd refit the curve before it). The outlook looks back ("Reached its target Tue, Aug 4", "Stayed above … through …").
3. **Everyone can use it** (read-only, their own fields).
4. **The button** goes beside the page's date heading: a rewind-clock icon button (`aria-label="View this field on an earlier date"`) opening a date input limited to the season's days before today.

**Built (2026-11-10)**, as below except where noted:
- [x] Controller: `?as_of=` honored for a day of the chosen planting's season before today, else ignored; `travel_dates` gives the picker its limits. `PlantingStatus.new(planting, as_of:)` does it (records via `DailyInputs.preload` through the days that followed, `Canopy.for(planting, through:)`, no ensemble, `projection_source: observed`).
- [x] Projection: the existing `HORIZON` cap already ends it at as_of + 15, on stored weather (a date within 15 days of today runs into the forecast for the rest). The weather panels end at the date.
- [x] Page: the rewind-clock button is the last of the header's actions, right-aligned so it never moves; its date input, View and (time travelling) a Today button fly out to its left, open from the start on a time-travelled page; the banner (a card that scrolls away, then a slim full-width bar pinned to the top; pinned bars publish their heights, `lib/stickyBars.ts`, and the weather range bar sticks below them with `top-sticky`, under the impersonation bar too), "Return to today" (keeps the season), read-only `EditableCell` (`readOnly`), no Export CSV, setup link or rainfall preferences; the title starts "As of Jul 15 · ". While read-only, the grid's scroll boxes take focus (axe).
- [x] Words: the outlook (`lib/outlook.ts` only; the digest never time travels), the chart's "What happened next" and the date in place of "Today", the section "The N days that followed", About (Day to day and What's changed).
- [x] Tests: request specs, outlook and `EditableCell` vitests, the page in `e2e/accessibility.spec.ts`, a smoke test.
- [ ] The archive replay (step 3's later part), once the archive has a season.

**Build plan** (as written before building):
1. **Controller** (`FieldsController#show`): read `params[:as_of]`, parse it as a date, and use it only if it's within the chosen planting's season and before `Date.current` (otherwise ignore it and show today; no error). Pass `today: as_of` to `PlantingStatus`, the season's records and the weather range. Skip `keep_current` and give `weather_updating: false` while time travelling. Add `as_of` (the date or null) to the props. The planting choice (`default_planting`) uses the as_of date when given, and `?planting_id=` still wins.
2. **Records cut at the date:** `DailyInputs::Records` built with entries, group entries and pivot irrigations dated on or before as_of (a `through:` on `DailyInputs.preload`, or filter the field's own). Canopy readings: `Canopy.for(planting, through: as_of)` leaves out readings after it; `CanopyFit`'s cache key follows the readings, so it needs nothing else.
3. **The projection:** `PlantingBalance` already uses stored weather where it exists and the forecast only for days without it, so days after as_of take the observed weather. Cap the projection at as_of + `FORECAST_DAYS` − 1 (today it runs while days have weather, which would be the rest of the season), pass `ensemble: nil` so there's no band, and mark the summary (`projection_source: "observed"`) so the page labels it "What happened next" instead of the forecast. Replaying an archived forecast is a later step, once the archive has data: `weather:` from that day's archived issue.
4. **The page** (`Fields/Show.svelte`): with `as_of`, a banner under the header, sticky like the impersonation bar but in the info style (`role="status"`: "Viewing {field} as of July 15, 2026, with what's entered for days up to then. Return to today"), "Return to today" a `<Link>` to the field without `as_of`. A `readonly` flag hides or disables every editing path: `EditableCell` (a `readonly` prop that renders the plain value), the planting and rain setting forms, setup links, Export CSV (or exports the cut season; simplest to hide), and the weather update spinner. The page title gets "as of Jul 15 · ". Links to other seasons drop `as_of`.
5. **Words:** the projection's legend and the outlook say "what happened next" for observed weather; guidance and tasks already follow `today`. A short paragraph on the About page (how to use it for training and demos), and a glossary entry only if the label needs one.
6. **Tests:** request specs (as_of honored inside the season; ignored outside it, in the future and when malformed; entries, irrigation and readings after it left out; no weather update queued; another group's field still 404); a component test of the read-only page (no editable cells, banner, Return link); the time-travel page in `e2e/accessibility.spec.ts` (banner contrast, light and dark) and a smoke test (pick a date, see the banner, return).
7. **Not in scope:** the dashboard, map and digest; writing while time travelling; the archive replay (step 3) until the archive has a season.

#### G. Beta readiness (UX review, 2026-11-11)

A review before the beta: the app driven in a browser as the demo grower (desktop and phone widths), a new account taken through sign-up and quick setup, and the code read behind anything that looked off. Nothing was broken; these are the pain points, gaps and confusions a new grower would meet, and the crops worth adding. Ben agreed to all of it (2026-11-11) and asked for irrigation systems beyond pivots and linears (G.5) and a link from the dashboard's pivot names (G.1).

**Principle (Ben, 2026-11-11): simple by default, more for those who want it.** A one-pivot, one-crop grower should set up and use WISP in as few steps as today; the extras (boundaries, several plantings in a field, planting-level irrigation, other irrigation systems) appear when asked for ("Add another planting to this field", "Draw or import the field's outline"), never as required fields or extra screens on the simple path. Each step below is checked against that: the quick setup for a single pivot with one crop must not gain a required input, and pages for a field with one planting look as they do now.

**All of G is before launch** (Ben, 2026-11-11), and its beta covers growers of every scale, large pivot operations to small diversified farms and research stations (Ben is reaching out to both). Larger growers often run their pivots from the manufacturers' software (Lindsay FieldNET, Valley 365); ask them in the beta whether importing irrigation from those exports would decide whether they use WISP (After launch otherwise).

**Order** (on the `beta-readiness` branch, merged to `main` in pieces as each step passes CI): G.1 quick fixes; G.9 seasons and history (it moves soil and weather onto the planting, which G.11 builds on, and G.5's pivot moves rely on it); G.11 fields with several plantings (it changes what the balance reads and every page that shows status, so before G.2–G.4 build on those pages); G.12 the weather page; G.2 and G.3 (what a grower meets in the first week); G.4 daily entry (with G.11's planting rows); G.5 irrigation systems; G.10 field boundaries and import; G.6 wording; G.13 forms; G.7 crops; G.8 operations, next season and the example farm (which shows all of the above). Decisions: Ben, 2026-11-11, recorded in each step.

##### G.1 Quick fixes

- [x] **Dashboard: the pivot's name links to its page** (`Dashboard/Show.svelte`, the `Pivot:` heading), and the same on the map's field list (`FieldCard`'s `Pivot:` line) and the pivot popup. Rename the pivot's "View" link to "Irrigation", the name Setup gives the same page.
- [x] **Readings due stay visible:** the "Soil moisture … due" and "Percent cover … due" chips sit inside the "How … is modeled" `<details>` (`Fields/Show.svelte`), so collapsing the text hides them. Move them out, beside the canopy warning.
- [x] "On the 1 days you entered rain" (`Fields/Show.svelte`, season totals): pluralize.
- [x] **Phone nav:** at 390 px the tab row scrolls sideways and "Setup" is cut off with no sign of more. Add an edge fade or scroll hint (or a "More" menu for About and the admin items); keep the bits-ui rule in CLAUDE.md (items left out, not hidden). *(Done 2026-11-11: a fade on whichever edge has more tabs past it, and the current tab scrolled to the middle after each visit.)*
- [x] **The page jumps when a dialog or menu opens** (Ben, 2026-11-11: the operation switcher, every form dialog). bits-ui's scroll lock hides the page's scrollbar and pads `body` by its width, one a frame after the other, so the page shifts and shakes. Decided (Ben, 2026-11-11): no scroll lock rather than a permanent scrollbar gutter. `preventScroll={false}` on `Dialog.Content` (`lib/components/Dialog.svelte`) and on the menus' content (the operation and account menus in `AppLayout`, `Term`'s popover if it locks), so the scrollbar stays and the wheel scrolls the page behind; the dialog itself still scrolls inside (`max-h-[90dvh] overflow-y-auto`). Check that focus stays trapped in the dialog, and on a phone that scrolling inside a dialog doesn't drag the page. *(Done 2026-11-11: both, the dialog with `overscroll-contain`; a smoke test checks the page keeps its scrollbar with a dialog open. Focus and phone scrolling to check by hand.)*
- [x] **Setup names each level** (Ben, 2026-11-11): "Farm: Coloma Vegetables", "Irrigation system: Home pivot", "Field: Home North", the label inline in muted text and outside the link, as the dashboard does. The pivot's name links to its page (what "Irrigation" opens); the field's already links to the Field page. Fits G.5's wording ("Irrigation system", then the kind's name once G.5 lands) and G.6's moving Delete into each item's form.

##### G.2 Season end dates

Every planting defaults to an end date of Nov 30 (`Planting.defaults_for`, as in legacy), and quick setup doesn't ask for one. A potato harvested in September stays in season for two more months: the dashboard shows it, the daily email lists it, and its tasks keep asking for readings (the demo's R1 potato on Nov 11: "Percent cover: Oct 2 (40 days ago) · due").

**Built (2026-11-11):**
- [x] **A typical season length per crop:** `season: {days, basis}` on each crop in `db/reference/canopy_curves.yml` (`CanopyCurve#season_days`). AquaCrop's maturity for potato (105), field corn (126) and soybean (121); FAO-56 Table 11's total less about 10 days to emergence for the rest; crops harvested green (snap bean 70, sweet corn 80, shell peas 65) stop before FAO-56's late stage. The crops without a curve (onion, alfalfa, mint, asparagus, other) end Nov 30. No season ends after Nov 30.
- [x] `Planting.typical_end(plant, emergence)` (mirrored by `typicalEnd` in `lib/plantings.ts`): `defaults_for`, a planting created with an emergence and no harvest, and quick setup use it. The planting form's harvest follows the crop and emergence until a date is typed (an existing planting keeps its own), with "A soybean season typically runs about 121 days from emergence to harvest" under the dates.
- [x] **Quick setup asks for the harvest date** ("Harvest (expected)", following crop and emergence until typed; `end_date` in its rows).
- [x] **"End the season today"** on the planting page, once a planting in season is past its crop's typical length ("Past a typical potato season (105 days from emergence). Harvested?"), after a confirm; anyone in the operation (an ordinary planting update).
- [x] Existing plantings keep their dates. The About page's planting entry says how the harvest date is set, and each crop card gives its typical season with its basis.
- [x] Tests: request specs (defaults, the emergence given, quick setup's harvest given or suggested), `typicalEnd` vitest, a smoke test of the form's suggestion.
- [ ] **Wisconsin timings for the warm-climate rows** (cabbage 155, broccoli 125, tomato 145, carrot 140, celery 115, sweet potato 140 days come from California and Mediterranean rows and likely run long here): replace them with Upper Midwest extension timings, with sources, alongside the canopy curves' own follow-up in `docs/canopy/02-published-curves.md`.
- Winter crops (Ben, 2026-11-11): a planting may cross the new year, but WISP models the irrigated season; winter wheat or rye is entered from spring green-up (emergence on that date). Say so with G.7's crops.

##### G.3 Crops without a canopy curve

Onion, alfalfa, mint, asparagus and Other have no curve (`canopy_curves.yml`), so until the first cover reading their canopy is 0 and crop ET is bare-soil evaporation (at most 0.02 in a day, `CropEt.bare_soil`). The field page says so in "How … is modeled", but the dashboard card, map badge and email show the field as OK and never needing water: a silent, confident wrong answer.

**Decided (Ben, 2026-11-11): generic curves, a "readings only" opt-out, and cuttings.** A crop without its own curve borrows a generic one, which readings correct as they do any curve (`CanopyFit`); "No curve: readings only" is a choice with a warning, and only that gets the status of its own. Perennials that are cut restart their canopy at each cutting.

- [x] **Generic curves** in `canopy_curves.yml` (`generic:`, percent cover only, confidence `generic`, each with its derivation), and each curveless crop's default:

  | Curve | Shape (AquaCrop growth) | Typical season | Default for |
  |---|---|---|---|
  | Fast, leafy | CC₀ 2%, CCx 90%, 80% by day 35 | 60 days | — |
  | Vegetable, medium | CC₀ 1.5%, CCx 90%, 80% by day 52 | 110 days | Other, garden vegetables |
  | Slow, partial cover | CC₀ 1%, CCx 65%, 55% by day 70 | 120 days | onion |
  | Perennial, regrowth | CC₀ 5%, CCx 95%, 80% by day 25 from green-up or a cutting | (Nov 30) | alfalfa, mint, asparagus |

- [x] **`plantings.canopy_curve_key`** (string, NULL; the serializer's `canopy_curve` was already the boolean "has a curve"): NULL is the crop's own curve, or its generic default; a generic key picks another; `none` is readings only. Only crops without their own curve take one (validation). `Planting#cover_curve` gives the `CanopyCurve` in effect (or nil), and everything that asked `CanopyCurve.for(plant.key)` for a planting asks it instead (Canopy, `canopy_curve?`, season days, guidance). LAI is unchanged (field corn only).
- [x] **The planting form** (and quick setup's crop choice), for a crop without its own curve: "Canopy: [generic curves] | No curve: readings only", preset to its default, with "An approximation for {crop}: your percent cover readings correct it" or, for none, "Irrigation scheduling works only if you enter percent cover regularly, about weekly until the canopy closes."
- [x] **A status of its own** for `none` only: a planting in season, past emergence, with no curve and no reading gets `needs_canopy` in place of OK/Full (`PlantingStatus`): a caution-style badge "No canopy data", the outlook "WISP can't estimate {crop} water use until you enter a percent cover reading", and a task that is always due. The dashboard counts, map filter, and digest (its own line, not "no irrigation needed") follow. `Outlook` and `lib/outlook.ts` change together, with cases in `outlook_cases.json`.
- [x] **Garden vegetables (mixed)**: a crop in `plants.yml` (root zone 18 in) on the medium vegetable curve, for a home garden or a market garden bed: one planting on part of a field (G.11), at a location without a pivot once G.5 has "Location only"; hose or drip water is its own irrigation.
- [x] **Cuttings** (alfalfa, mint; any planting on the perennial curve): a `canopy_cuttings` table (planting, date), entered on the planting page ("Cut on [date]", listed with delete) and drawn on the chart. Each cutting restarts the canopy: the season splits at the cuttings into pieces, each following the perennial regrowth curve from its start (the first from emergence, i.e. green-up) and fitted to the readings within it only, so the canopy drops at a cutting and regrows (a sawtooth) rather than smoothing across it. Readings after a cutting belong to the regrowth. `Canopy` composes the pieces; the check runs on the current piece. Tests: the drop and regrowth, a reading fitting only its piece, cross-tenant for the cuttings controller.
- Built (2026-11-11), as above, with: the key validated only when it changes (a crop that later gets its own curve keeps its plantings editable; its own curve wins), the default left blank (so a crop follows a changed default); quick setup only says a crop is on a generic curve (no choice there); `needs_canopy` ranks after caution, an outlined "? No canopy data" badge, the map in the caution color; the About page's crop table, a list of the generic curves and the crops on each, and the status; "How … is modeled" names the generic curve. Tests: `spec/services/generic_curves_spec.rb`, request and model specs for the choice, an outlook case, vitests, a smoke test of the form.
- [ ] Onion gets its own curve in G.7 if one can be justified; the generic stays its default until then.
- [x] About: the generic curves (a list, with the crops on each, and in the crop table), and readings-only with its status. *Cuttings built 2026-11-11: `CutCanopy` (pieces from emergence and each cutting, each on the regrowth curve from 5% stubble and fitted to its own readings; no canopy check across cuttings), `CanopyCuttingsController` (create and destroy, through `Current.group.plantings`), a Cuttings panel on the planting page (read-only while time travelling), "Cut" lines on the chart's canopy panel, and the demo's "Hay north" alfalfa with three cuttings. Tests: `cut_canopy_spec.rb`, `canopy_cuttings_spec.rb`, cross-tenant, a chart vitest, a smoke test, the page in axe.*
- [ ] The About page's own words on cuttings, and the glossary's canopy curve entry (with G.6's wording pass).

##### G.4 Daily entry as the morning page

Daily entry has rain, irrigation and soil moisture per field, but nothing for a shared rain gauge and no canopy readings. On River pivot (8 fields) one gauge reading is typed 8 times, or entered on the field group's page; weekly cover readings for 10 fields mean opening 10 field pages.

- [ ] **Rain gauge groups on daily entry** (field groups, `FieldGroupEntry.record`): a "Rain gauges" section at the top, one rain input per group, each listing its fields. A field in a group shows the group's value in its rain cell, muted (a field's own entry still wins, as now).
- [ ] **"Same rain for all fields"** on each pivot: fills its fields' empty rain inputs in the browser (stored per field as now; no new data). Simpler than a pivot-level rain entry, and nothing in the balance changes.
- [ ] **An optional percent cover column** (LAI for LAI plantings), shown for fields in season after emergence whose canopy reading is due or that have no curve; written with `CanopyObservation.record`. Hidden once the canopy is closed or vines are killed (`PlantingTasks`).
- [ ] Fields with no crop in season are listed below the rest, collapsed ("3 fields with no crop this season").

##### G.5 Irrigation systems other than pivots

WISP assumes every field sits under a center pivot or linear move, and says "pivot" everywhere. Research farms use travelers (hard hose reels with a big gun), specialty crop growers drip, and some fields solid set; some growers just want a location.

**What the "pivot" does in the model:** only two things depend on it. Its **location** picks the weather cell (and the soil suggestion), and it holds **irrigation applied to several fields at once** (`pivot_irrigations`, inches or run hours: pump gpm × hours ÷ the fields' acres). The shape is drawn and measured, never used by the balance. So other systems need new shapes and words, not a new engine. Run hours already work for any system with a flow rate and known acres.

**Kinds** (`pivots.kind`, a check constraint, `Pivot::KINDS`, mirrored in `lib/geo.ts`):

| Kind | Called (one) | Shape on the map | Dimensions |
|---|---|---|---|
| `center` | Pivot | Circle or arc (as now) | Radius, arc |
| `linear` | Linear | Rectangle (as now) | Machine length, travel, bearing |
| `traveler` | Traveler | A point | None; area from its fields (see below) |
| `solid_set` | Solid set | A point (a marker) | None; area from its fields |
| `drip` | Drip | A point | None; area from its fields |
| `point` | Location | A point | None. For anything else, or growers who don't want to draw a shape |

Point kinds keep the pump capacity (labelled **Flow**), so run hours work for a drip zone or solid set block as for a pivot. Drawing a block's outline (a polygon) for solid set and drip is a later step; the point is enough for weather and soil.

**What an irrigation system is in WISP** (2026-11-11): a place that is watered one way, not a machine. A pivot is both, which hid the difference. A **traveler** is one machine pulled by a tractor from field to field, so in WISP each field (or set of fields) it waters is its own Traveler system at that field's location, and the machine's name goes in Equipment ("Hard hose reel #2"). Irrigation is entered on that system or field for the day it ran there. One record for the machine with no location wouldn't work: weather comes from the location, and the fields it moves between can be in different weather cells (about 9 km across, so usually not). The same applies to a drip block or solid set block. That's also why the traveler is a point and not a lane: a field is covered by many pulls in different places. A shared Equipment name lets a later step list a machine's runs across fields if growers want that.

**Words:**
- [ ] **One item names its kind**: "Pivot: North 160", "Traveler: Lane 3", "Drip: Tomato block". The noun comes from one place: `Pivot::KIND_NAMES` serialized as `kind_name` on the pivot serializers, so Svelte pages, the digest, CSVs and admin pages can't disagree.
- [ ] **Collective words use "irrigation system"**: "Set up an irrigation system", Setup's "Add irrigation system", the map's list, the digest's grouping ("by weather zone, irrigation system and field"), the About page, the glossary. A pivot's irrigation page becomes "{kind name}: {name}" with "Irrigation applied by this {kind name lower}".
- [ ] Sentences that only make sense for pivots ("place the pivot where it really is", "Click the map at the center of the pivot") get per-kind versions in the shape editor.
- [ ] Legacy users keep seeing "Pivot" for their pivots; nothing they know changes name.

**Decided (Ben, 2026-11-11):** keep `Pivot`, `pivots`, `pivot_irrigations` and the `/pivots` URLs in code, with a line in CLAUDE.md ("a pivot in code is any irrigation system; growers see its kind's name"). The collective word is **"irrigation system"** ("system" where space is short).

**Build:**
- [ ] Migration: widen the kind check constraint; point kinds (`traveler`, `solid_set`, `drip`, `point`) hold no dimensions (check constraint).
- [ ] `Pivot` validations and limits per kind, mirrored in `lib/geo.ts` (`pivotOutline` gives a point kind no outline; `shapeAcres` nil).
- [ ] `PivotShapeFields`: the kind as a set of choices with a one-line description each ("Center pivot: a circle or part of one", "Traveler: a hard hose reel or gun moved between fields; set one up for each field it waters, at the field", "Drip: drip tape or emitters; place it at the block", "Location only: just where the field is"). Point kinds show only the location (map click, place search, coordinates) and Flow.
- [ ] Map: point kinds drawn as markers with the same badges and selection (`lib/map/pivots.ts`, `OverviewMap`); the pivot picker (`PivotMap`) places a marker with no handles.
- [ ] Words, as above, across pages, emails (`DailyDigest`, mailer views), CSV headers and frontmatter (`PivotIrrigationCsv`, `SeasonReportCsv`), About and glossary; `e2e` and spec text updated.
- [ ] Demo seed: a traveler serving two fields on a research farm (two Traveler systems, one Equipment name) and a drip block at Coloma Vegetables, so the beta, the example farm (G.8) and the screenshots show them.
- [ ] Tests: model and request specs per kind (validations, constraint, cross-tenant as now), `geo.ts` vitests, the setup form's kinds in a smoke test, axe on the form with a point kind.

**Not in this step (After launch, if the beta asks):**
- **Drip's wetted fraction and plastic mulch.** WISP spreads every irrigation over the whole field and counts bare-soil evaporation from all of it. FAO-56 adjusts both for drip (the fraction of soil wetted, `few`, and mulch cutting soil evaporation). Until then, the About page says to enter drip irrigation as the depth over the field's whole area (what run hours already compute).
- **Application losses.** Travelers and guns lose more to wind drift than pivots or drip. WISP takes the irrigation entered as what reached the crop; the About page and the irrigation form's hint say so, and a per-system efficiency (to enter gross amounts) waits for demand.
- Polygons for blocks; several drip zones on one block with their own run times.

##### G.6 Fewer things to decode

- [ ] **Lead with the outlook, not AD.** The dashboard card and the field summary lead with "AD today 0.31 in of 0.48 in"; field capacity, target and the irrigation point are all given in AD ("Irrigate at 0 AD"), which goes negative. Make the outlook sentence ("Irrigate by Thu, Jul 23 · about 0.6 in refills it", "No irrigation needed through …") the headline, with AD and moisture beneath it, and word the reference points by moisture first: "Irrigation point: 7.0% moisture (AD 0)". `Outlook` and `lib/outlook.ts` together. A wording review with the beta growers.
- [ ] **A shorter field page for a first visit:** the weather section starts collapsed (its remembered open state then wins), and "How … is modeled" opens as two sentences with "More about how {crop} is modeled" for the rest.
- [ ] **Setup's Delete links** (one per farm, pivot, field and crop, red, on every row) move into each item's edit page, behind its confirmation as now. Setup keeps Edit, Add and Irrigation.

##### G.13 Forms that explain themselves and don't lose edits

Ben, 2026-11-11, from clicking through Setup.

- [ ] **Every form asks before dropping changes**, dialogs included. Pages already ask through `lib/unsaved.svelte.ts` (Pivots/Form, Setup/Start, Daily entry); a dialog closed by Escape, a click outside or ✕ just closes. `Dialog` takes the form's changes and, with any, shows its own prompt inside the dialog in place of closing (not `window.confirm`): **"Save changes" / "Discard" / "Keep editing"**, listing what changed in the user's units: "Area: 40 ac → 30 ac", "Crop: Potato → Soybean", "Harvest or kill: Sep 15 → Sep 30". The list comes from comparing the form's labelled controls (what the user sees, not the hidden stored values) with a snapshot taken when it opened, so each form needs no list of its own; a shared helper (`lib/formChanges.ts`, vitest) for dialogs and the pages that ask today, so they word changes the same way. Leaving a page with a changed form keeps the browser's prompt (its wording can't be changed). Smoke test: edit a field's area, press Escape, see the change listed, Discard; Keep editing keeps the value.
- [ ] **An info tip on form labels:** a small ⓘ at the far end of a label's line, opening a short explanation on hover, focus or tap, like `Term` (its popover and keyboard handling): what the setting does and when to change it ("Root zone depth: how deep the roots draw water; the crop's typical depth unless you know better"). `TextField`, `NumberField`, `SelectField` and the date and radio groups take `info`; the wording lives in one module (`lib/fieldInfo.ts`), from the About page and the legacy user guide, next to `lib/guidance.ts`. Start with Setup's forms (farm, pivot, field, planting), then quick setup, settings and alerts. Keep the hints that are there (under the box) for what must be read before typing; tips for the rest. In axe and the keyboard tests.

##### G.7 Crops to add

From the canopy research already done (`docs/canopy/02-published-curves.md`, `03-crop-curves.md`). Each new crop gets its row in `plants.yml` (root zone), a curve in `canopy_curves.yml` with sources, confidence and notes (the About page's crop cards follow), a `season_days` (G.2), and a backtest line where readings exist.

- [ ] **Dry bean** (kidney, black, navy; grown in the Central Sands): AquaCrop's DryBean curve, already behind snap bean (which stops it at harvest), run to maturity with its decline. Confidence `published`.
- [ ] **Oats** (and spring rye or triticale if growers ask): FAO-56 Table 11's "Barley/Oats/Wheat" row is already the source of the barley and wheat curves.
- [ ] **Corn silage:** the field corn curve and LAI model with an earlier harvest (`season_days`). Its own crop name rather than a variety, so it gets its own default end date and shows in the crop list.
- [ ] **Onion, a stopgap:** note 03 found no published Upper Midwest curve and rejected FAO-56's temperate row (80% cover by day 26). Try FAO-56 Table 11's stage lengths with Wisconsin planting and maturity dates and a realistic maximum cover from extension photos; confidence `fao56`, flagged on its crop card. If it can't be justified, it stays readings-only with G.3's status.
- [x] **Alfalfa and mint** cuttings: moved to G.3 (Ben, 2026-11-11).
- [ ] **About page: crops WISP doesn't model** and why: cranberry (managed by flooding, frost protection and the water table) and ginseng (under shade). Sugar beet and sorghum are left out until someone asks (little irrigated acreage in Wisconsin).

##### G.8 Operations, next season and an example farm

Decided (Ben, 2026-11-11): all three.

- [ ] **All operations at once** (crop consultants and anyone in several operations): an "All operations" choice at the top of the operation switcher, shown to users in more than one. The dashboard and map then list every operation's fields, grouped by operation first (`OperationOverview` over several groups, `FieldStatuses.for` already takes any fields). Daily entry, Setup and the operation page stay one operation at a time, and say so with a link to pick one. Tenancy: the set is exactly `current_user.groups`, never a parameter; a cross-tenant spec for it.
- [ ] **Next season from October:** quick setup asks which season when run between October and December, defaulting to next year. (Setup's season menu already offers next year all year round: `Setup/Show.svelte` adds `year + 1`; corrected 2026-11-11.)
- [ ] **Rebuild the demo with realistic names** (Ben, 2026-11-11): fields are named for the land, not the crop ("Home North", not "Cabbage"; "River H peas then soybeans" becomes a field with two plantings), now that a field can hold several plantings; a few fields with two plantings in the season. The example farm below is built from it. The e2e seed and tests that find fields by crop names change with it (`firstPlantingPath` looks for "Field: Cabbage"). Existing demo accounts are rebuilt by rerunning `bin/rails demo:seed` (it keeps the password).
- [ ] **A public example farm** (Ben, 2026-11-11: one example anyone can view without an account, the same for everyone, rather than a copy per account; once signed up, growers set up their own). One example operation (`groups.example`, at most one, seeded by `DemoSeed`, owned by an admin account), shown read-only at `/example` (its dashboard, map, fields and irrigation systems), linked from the landing page and the signed-out nav ("Example farm") and from the empty dashboard. It shows the common configurations: a center pivot split between two crops, a linear, a traveler serving two fields, a drip block, a location-only field, a research field with several plantings side by side (G.11), field boundaries (G.10), irrigation by run hours and a shared rain gauge.
  - **Always mid-season:** shown as of a fixed day (July 20 of its seeded year), so it has fields needing water even in winter and needs no reseeding each spring. Time travel (F) covers only the field page, so the dashboard and map get `as_of` too, read-only (`readOnly` as on the field page; no weather polling, no forms).
  - **Tenancy:** the first signed-out pages to read a group's data. The controllers load only `Group.example` (never an id from the request), through a base controller of their own, not `AuthenticatedController`; specs that no route under `/example` reaches another group's records, and that nothing there writes. Rate limited (Rack::Attack) and cached.
  - A banner on each page ("This is an example farm. Create an account to set up yours") and the pages in `e2e/accessibility.spec.ts`. Optional: a preview of the example's morning email.

##### G.9 Seasons and history

Farms, pivots and fields aren't tied to a season; only plantings (a field's crop in a season), entries, irrigation and readings are dated. Every balance is recalculated when it's shown, from the field's and pivot's **current** values. So editing setup for 2027 changes 2026 as well:

| Change made in 2027 | Effect on the 2026 season |
|---|---|
| Rename a pivot, farm or field | Shows the new name. Harmless |
| Move a pivot within its weather cell | None |
| Move a pivot to another weather cell | 2026 reads the new cell's weather, which usually has no 2026 days (backfills cover only the current year, `WeatherCell#backfill_start`): its days lose their weather |
| Change a field's soil, field capacity or wilting point | 2026's balance is recomputed on the new soil |
| Change a field's area | Run-hours irrigation in 2026 converts to different inches |
| Move a field to another pivot | Its 2026 pivot irrigation no longer applies (`PivotIrrigation#applies_to?` checks the field's current pivot), and its weather follows the new pivot |
| Add a field to a pivot | Run-hours irrigation for "all fields" in 2026 is spread over the new field's acres too (a bug now: `irrigated_fields` counts every current field, even one with no crop that day) |

Growers rotate crops and often farm different acreage from year to year, so this will happen. **Recommended:** past seasons keep the values they ran with, and edits apply from the season being edited on:
- [x] **The balance's field values on the planting.** A planting copies the field's soil type, field capacity and wilting point when it's created (as it already holds root zone and MAD), and the balance reads the planting's. Editing a field updates it and its plantings that haven't ended; ended plantings keep theirs, and the planting form can change them for a past season. A migration fills existing plantings from their fields. `legacy_engine_spec` is unaffected (inputs only). *(Built 2026-11-11: `plantings.soil_type_id`, `field_capacity`, `perm_wilting_pt` (the overrides, NULL following the soil type, so a corrected soil type still moves plantings that don't set their own), `area_acres` and `weather_cell_id`, copied on create (`Planting#copy_from_field`); `Field` and `Pivot` update `Planting.open` (end date today or later) after an edit. The planting form's "Soil and area this season" appears only for an ended season.)*
- [x] **The weather cell on the planting.** `plantings.weather_cell_id`, set from the pivot when the planting is created; when a pivot moves, its plantings that haven't ended follow it, and ended ones keep their cell (whose weather is already stored). `DailyInputs` and the preloads read the planting's cell.
- [x] **Run hours over the fields irrigated that day:** only fields with a planting in season on the irrigation's date count (fixes the bug above), and the inches are stored when the irrigation is saved (`converted_inches`, recomputed when it's edited, or when the pump capacity or a field's area changes for an irrigation in a season that hasn't ended). Run hours stay what's shown. *(Built differently, 2026-11-11: nothing stored. `PivotIrrigation#irrigated_acres` adds the area each planting in season that day kept, so a later season's area change can't reach it, and a pump capacity fix still applies everywhere; a day with no planting counts the fields' areas.)*
- [x] **Moving a field to another pivot** is allowed only for a field with no ended plantings; otherwise the form offers "Set up this field under {other} from {year}", which makes a new field there (same name, soil and area) and leaves the old one with its history. *(Built 2026-11-11 without the one-click copy: `Field#pivot_kept_with_history`, and the form locks the pivot with "The 2026 season stays with North 160. To grow on another pivot, add a new field there." Add the copy button if the beta asks.)*
- [x] **Setup by season:** fields and pivots with plantings in other seasons but none in the one shown are collapsed under "N fields not used in 2027", so last year's layout doesn't clutter this year's; a field with no plantings at all always shows. *(Built 2026-11-11: a field is listed when it has a crop in the season shown or the one before (so next season can be planned from this one), or none at all; the rest are under "N fields not used in 2026 or 2027".)*
- [x] Setup forms say when an edit leaves earlier seasons alone ("Changes apply to 2027 and later; 2026 keeps its soil").

##### G.10 Field boundaries (optional)

A field can have an outline: drawn on the map, imported from a file, or none (as now). It is for the map and the suggested acreage only; the balance and weather don't use it.

- [ ] **Storage:** `fields.boundary` (GeoJSON Polygon or MultiPolygon, WGS84, jsonb). Validated on the server: closed rings, at most a few thousand vertices (simplified on import), inside `Pivot::LATITUDES`/`LONGITUDES`, and no larger than a plausible field. Changing it never changes a past season (G.9: acreage for the balance lives on the planting).
- [ ] **Import first, drawing second:** most growers already have boundaries (FSA Common Land Unit shapefiles, John Deere Operations Center or Climate FieldView exports, Google Earth). "Import field outlines" in Setup takes a zipped shapefile (`.shp`, `.dbf`, `.prj`; read in the browser with shpjs, which reprojects with the `.prj`), GeoJSON or KML, all parsed in the browser (nothing uploaded but the result). It shows the shapes on the map with their attribute names, lets the grower match each to an existing field or create a field under a chosen irrigation system, previews acres, then saves.
- [ ] **Drawing:** terra-draw (MIT, works with MapLibre) for a free-form polygon (click vertices, drag, delete a vertex), loaded on demand like MapLibre. Shortcuts: "Same as the irrigation system" (a field filling its pivot or a linear's rectangle, one click); splitting a pivot's circle along a line for a two-crop pivot can follow.
- [ ] **Suggested area and soil:** the outline's acres (`shapeAcres`) are offered for the field's area; the soil suggestion takes the dominant soil in the outline (area-weighted from the soil survey) rather than the soil at a point.
- [ ] **Map:** fields with an outline are filled by status (the status colors, validated for color blindness, light and dark); fields without one keep the pivot badges. Irrigation systems are drawn as outlines on top, with a toggle in the layer menu ("Irrigation systems"); a click inside a field selects the field, a click on a system's outline (a wider invisible hit line) selects the system. G.11's partial plantings show as pins in their field.
- [ ] Tests: GeoJSON validation specs, the import parser on fixture files (a shapefile zip, GeoJSON, KML), `geo.ts` area vitests, the import and draw flows in a smoke test, axe on both.

##### G.11 Fields with several plantings

**A field is a piece of land; a planting is what grows on it** (Ben, 2026-11-11). Today a field has one planting at a time (`Planting#no_overlap`), so a diversified farm or a research station has to make a field per crop and redraw them as crops rotate. Ben's research fields ("Arlington 525") grow several crops at once, each on a plot of known length and width. The balance already runs per planting (`PlantingBalance`), and a field can already hold plantings one after another (peas then soybeans, `?planting_id=` on the field page), so this extends the model rather than replacing it: every existing field is the case "one planting, the whole field".

**Model** (built 2026-11-11, commit "Part-field plantings: data model (8G.11)"):
- [x] **Whole field or part of it.** `plantings.partial` (false by default). A part-field planting's `area_acres` is its own: from `plot_length_ft` × `plot_width_ft` (ft, both or neither, `SQUARE_FEET_PER_ACRE`) when given, else entered acres (required). A whole-field planting has no plot or pin and follows the field's area while it hasn't ended (G.9); a field's area edit no longer touches part-field plantings. Overlaps: `Planting#no_overlap` ("overlaps a planting covering the whole field" for a plot) and the database's `plantings_no_overlap`, which now adds `CASE WHEN partial THEN int8range(id, id + 1) ELSE int8range(NULL, NULL) END WITH &&` (a whole-field planting's unbounded range overlaps everything; a plot's own-id range overlaps only that). `Planting#exceeds_field_area?` (plots in season together on some day add up to more than the field; a warning, serialized as `exceeds_field_area`). Switching back to the whole field is refused while the planting has its own entries.
- [x] **Where it is (optional):** `plantings.latitude`/`longitude` (both or neither, within `Pivot::LATITUDES`/`LONGITUDES`); cleared on a whole-field planting. No interface yet.
- [x] **Entries per planting** in their own table, **`planting_entries`** (irrigation, soil moisture, notes; no rain), not `field_entries.planting_id` as first planned: every existing query, form and CSV on field entries keeps its meaning, rain can't be entered per planting by construction, and tenancy goes through the planting. Only part-field plantings have them (`PlantingEntry#part_field_planting`); a whole-field planting *is* the field. `DailyEntry` takes `entry_values` per model. Precedence (`DailyInputs`, `planting:`), for a part-field planting only: irrigation = its entry (`:entered`) ?? the field's (**`:field`**, labelled "from field" in `lib/provenance.ts`) ?? pivot ?? field group ?? 0; soil moisture = its own readings only (a reading elsewhere on the field, or the field group's, isn't this crop's); rain as the field's. Whole-field plantings resolve exactly as before. `DailyInputs.preload` loads the plantings' entries with the field's (`Records#planting_entries`). The grid's save (`FieldDaysController`, with `planting_id`) sends a plot's irrigation, soil moisture and notes to its entry and rain to the field's; the field page's notes column reads the plot's entries.
- [x] **Run hours** (`PivotIrrigation#irrigated_acres`): a field growing only plots that day counts at its whole (current) area, since the pivot waters the field, not just its plots; a whole-field planting counts at the area it kept.
- [x] G.9's per-planting soil and weather cell apply as they are. `Field#planting_on(date)` now prefers the whole-field planting, else the earliest plot; `Field#plantings_on(date)` gives every one. Copy last season copies plots with their size and pin.
- [x] Tests: `spec/models/part_field_plantings_spec.rb` (areas, overlaps in the model and database, the warning, switching back, area edits, season copy, precedence with and without preload, entries only on plots, no rain, run hours), request specs for the grid's save and a cross-tenant one.

**Handoff for the frontend session** (2026-11-11). The data model above is done and tested; nothing in the interface knows about part-field plantings yet, so today they can be made only from the console or a crafted request. Start from the checklist below; these notes say where each piece plugs in and what's already decided.

1. **Status per planting (backend first).** `FieldStatuses.for(fields)` returns one `PlantingStatus` per field (`Field#planting_on`: the whole-field planting, else the earliest plot), so a field's other plots have no card, task or email line. Give it a per-planting form: `{field_id => [PlantingStatus, …]}` for every planting in season today (or the nearest this year when none), sharing the field's preloaded records (`DailyInputs.preload` already carries the plots' entries) and weather by `planting.weather_cell_id`. Callers: `OperationOverview#card` (dashboard and map: e.g. `fields: [{id, name, plantings: [summary, …]}]`, one summary for a field with one planting, so its card is unchanged), `DailyDigest` (a line per planting under its field; `Outlook` and `lib/outlook.ts` change together with `outlook_cases.json` only if the wording does), `SeasonReportCsv` (already per planting). Keep the dashboard compact for a field with many plots (a list layout once a field has, say, more than three).
2. **Field page** (`Fields/Show.svelte`, `FieldsController#show`): the planting `<select>` (`field.plantings`, by year) becomes tabs for the plantings in season on the day shown, with earlier seasons still in the select; `default_planting` uses `planting_on`. For a plot: the header says "Part of the field: 100 × 20 ft (0.05 ac)" (`plot_length_ft`, `plot_width_ft`, `area_acres`) and shows `exceeds_field_area` as a caution; the grid hint says rain is the field's and irrigation, soil moisture and notes are this planting's; irrigation from the field shows as "from field" (muted, as pivot irrigation is). `day_params[:pivot_inches]` shows the pivot's value under an override; add the field's irrigation the same way (`field_inches`) for plots. The field's own entries (rain, overhead irrigation) for a field of plots are entered on a field-wide view: either a "Whole field" tab with the field's rain and irrigation grid and no balance, or daily entry (item 5); decide while building.
3. **Planting form** (`lib/setup/PlantingForm.svelte`, `PlantingsController` already permits `partial`, `plot_length_ft`, `plot_width_ft`, `area_acres`, `latitude`, `longitude`): "Part of the field" appears only when the new planting's dates overlap another on the field (the field's plantings are in the Setup props), or on an existing plot. Its inputs: length × width (`NumberField` with a distance quantity; check `lib/units.ts` has ft ↔ m) or acres, and the computed acres beside them. The whole-field alternative there is "Replace": end the other planting the day before this one starts. "Add the next planting" pre-fills a season starting the day after the latest one ends. The pin waits for G.10's map.
4. **Setup** (`pages/Setup/Show.svelte`): a field's crop chips become a season timeline when it has more than one planting in the season (bars from season start to end across April to November, stacked rows for plots side by side, each opening its form; a pure layout function in `lib/` with a vitest); one planting keeps its chip. A plot's chip shows its size.
5. **Daily entry** (with G.4): plots in season are sub-rows of their field (irrigation, soil moisture, cover), collapsed when empty. The bulk save (`DailyEntriesController#update`) takes `plantings: {id => values}`, loads them through `Current.group.plantings`, and writes `PlantingEntry.record`; add a cross-tenant spec.
6. **Map** (G.10): plots with a pin as markers inside their field; cards per planting from item 1.
7. **Words:** "Add a planting" for "+ Crop", "planting" for a crop on a field in a season, "crop" for its kind; a glossary entry; About: fields and plantings, plots, and what's entered where.
8. **CSV:** `PlantingCsv` header gains "Part of the field" (plot or acres) and the `field` irrigation source; `SeasonReportCsv`'s Fields section a "Part of the field" column.
9. **Demo and example (G.8):** a research field ("Arlington 525"-style) with four plots side by side (one with its own drip irrigation and readings) and a market garden field with successions, in `DemoSeed`.
10. **A plot's own soil** (Ben, 2026-11-11: yes; model built, `plantings.own_soil`, plots only, check constraint `plantings_own_soil_partial`). A plot follows its field's soil (and its field capacity and wilting point overrides) unless it has its own: field soil edits skip plots with `own_soil` (`Field#update_open_plantings`), setting `own_soil` back to false takes the field's soil again, a plot created with a soil different from the field's gets `own_soil` true, and Copy last season keeps a plot's own soil. **Interface** (planting form, plots only): a checkbox **"Use the field's soil (Sand)"**, checked by default, with the field's current soil named in the label (it follows the field); unchecked, it shows the soil menu and the plot's own field capacity and wilting point, and sends `own_soil=true` with them. Once the field has an outline (G.10), the menu's options say each soil's share of the field from the soil survey ("Silt loam, 5% of the field"; the same area-weighted query as G.10's dominant soil), ordered by share, so growers are steered to the soils actually there. The ended-season correction (G.9's "Soil and area this season") stays as it is for whole-field plantings.

**Pages (Ben, 2026-11-11; replaces the handoff's items 2–4 where they differ).** The pages follow weather zone → irrigation system → field → planting, each linking up to its parent and to its weather (G.12):
- **Field** (`/fields/:id`, `Fields/Show`): the land. Its area and soil, the season's **timeline** of plantings, a status card per planting in season, the field's own rain and irrigation grid (field entries, no balance; where a field growing only plots gets its rain and overhead irrigation until G.4), "Add a planting", and the rainfall preference. `?planting_id=` (old links) redirects to the planting.
- **Planting** (`/plantings/:id`, `Plantings/Show`): what `/fields/:id` showed before, one planting's balance, chart, grid and time travel (`?as_of=`). Cards, the digest and CSVs link here.
- Both share a header (`FieldHeader`): breadcrumbs (farm › system › field), and tabs **Field · each planting of the year**, with other years in a select.
- **Planting form:** "Planting size: Whole field | Part of the field", always shown (not only on overlap). Part of the field asks length × width or acres (not more than the field; a validation), with the acres computed beside them; plots together over the field's area is a warning. A whole-field planting overlapping another on the field says which and offers to end that one the day before (`replace`). "Use the field's soil (Sand)" for plots. "Add the next planting" from a planting's form.
- **Season timeline** (a Gantt, `lib/timeline.ts`): on every field in Setup, even with one planting, and on the Field page; bars across April to November (wider if a planting runs outside), plots in season together in rows, each bar opening its planting.
- Words: "Part of the field".

**Interface (simple stays simple):**
**Built (2026-11-11)**, as above, with these details:
- [x] A field with one planting at a time looks as it did: the same card (linking to the planting), the planting page as the field page was, daily entry rows.
- [x] **Adding a planting:** "Add a planting" on Setup's field rows and the Field page (`PlantingDialog`); "Planting size: Whole field | Part of the field" (length × width or area, acres computed, the field's size the limit: `Planting#within_field_area`, and Save disabled past it); an overlap is named in the form, and for a new whole-field planting starting after the other's emergence, "Replace: end Corn on Jun 30" (`replace`, in the create's transaction; plots never end other plots); "Use the field's soil (Silt loam)"; "Add the next planting" in an existing planting's dialog (the day after it ends, a week to emergence, to Nov 30, the same size).
- [x] **A season timeline per field** (`SeasonTimeline`, `lib/timeline.ts` with vitests): every field row in Setup, even with one planting (bars open the form), and the Field page (bars link to the plantings, a status dot each, today's line). Plots dashed; ended plantings muted.
- [x] **Status per planting:** `FieldStatuses.for` gives each field a list: every planting in season, or the one this year nearest today with those overlapping it (a field of plots shows all its plots in November, a succession just the nearest). Cards are `{id, name, plantings}`; `primary` (the most urgent, matching `FieldStatuses.urgency`) places the field, its pivot's status and the map badge; status counts count fields. A card lists each planting in brief for two or three, one line each beyond three. The digest has a line per planting ("Soybean, 100 × 20 ft (0.05 ac)", linking to the planting), counting fields once in its subject and counts.
- [x] **Field and Planting pages** as above (`FieldHeader` tabs: Field, then the year's plantings, whole-field first, a plot's tab with its acres; other years in a select). A plot's page: "Part of the field: 300 × 60 ft (0.41 ac)", its own soil when it has one, the area warning, the grid hint on what's whose, irrigation "from field" and the field's amount under the plot's own (`field_inches`). The rainfall preference moved to the Field page ("Change this" links there).
- [ ] **Daily entry** (G.4): a field's row has the field-wide rain and irrigation; its partial plantings in season are sub-rows for their own irrigation, soil moisture and cover, collapsed when there's nothing to enter.
- [x] Digest (a line per planting), tasks (per planting already), CSVs (`PlantingCsv`'s header and `SeasonReportCsv`'s Fields gain "Part of the field": "Whole field", "100 × 20 ft (0.046 acres)" or "0.25 acres", `Planting#size_label`; the `field` irrigation source comes through as it is).
- [ ] The map's pins (G.10).
- [x] **Words:** "Add a planting", "Copy last season's plantings", "Save planting"; glossary entry (`planting`); About: fields and plantings, plots, what's entered where, both pages, What's changed.
- [x] Demo: "Arlington 525" (2 ac, silt loam, Arlington Research) with four 300 × 60 ft plots, the snap beans on drip with their own irrigation and readings, and a "Market garden" field with three successions. The example farm (G.8) reuses them.
- [x] Tests: `spec/requests/field_plantings_spec.rb` (the field page, a plot's page, cards, the out-of-season list, the digest, the form's limit and Replace), the planting page's specs moved to `/plantings/:id`, cross-tenant (planting page, Replace), `plantings.test.ts`, `timeline.test.ts`; smoke tests for a field of plots (dashboard, field page, tabs, Setup's timeline and form, the size limit, next planting) and Replace; the field, research field and a plot's page in axe and the reflow check. `legacy_engine_spec` unaffected.

##### G.12 A weather page

**Weather is a place, not part of a field** (Ben, 2026-11-11). The weather panels now sit on the pivot and field pages, repeated for every pivot in the same grid cell. Instead:
- [ ] `/weather` lists the operation's weather zones (grid cells), each with the irrigation systems in it; `/weather/:cell_id` has the panels (season slider, summaries, CSV) for the zone, with a year select.
- [ ] A zone is named from its systems ("North 160 and River") with its coordinates, as the digest's zones are.
- [ ] The pivot and planting pages drop their panels for a "Weather: …" link to their zone (a planting's own `weather_cell`, G.9, so an ended season links where it ran). The planting page keeps what's the planting's own: crop ET and entered rain in the chart.
- [ ] The nav gets Weather; the weather CSVs move with the panels; tests and axe for the new pages, a cross-tenant spec (cells reached only through the group's pivots and plantings).

**Exit:** editing setup for a new season leaves earlier seasons' balances as they were; a new account set up in November or May gets the right season and sensible harvest dates; no field shows OK on a model that can't estimate its water use; a grower can do the morning routine (rain gauge, irrigation, soil moisture, cover) on one page; a traveler, a drip block and a location-only field can be set up, mapped, entered and emailed in their own words; anyone can look around the example farm without an account; a research field holds several plantings side by side, each with its own balance; fields can be imported from a shapefile and shaded by water need on the map; someone in several operations sees them all on one dashboard; the new crops are on the About page with their sources.

### After launch

- Forecast accuracy tracking (stored forecasts vs finalized weather), from the daily archive started in Phase 8 E: by lead time, for ET0 and rain, and whether the ensemble's spread covers what happened. Part of the evaluation pages below.
- **Model evaluation and usage insights (admin pages; Ben, 2026-11-10; ideas, not designed).** After a season of data, an admin section that shows how WISP's models compare with what happened and with what growers entered, as anonymised statistics and charts, and how WISP is used:
  - **Forecasts:** the archived forecasts (Phase 8 E) against the finalized weather, by lead time, for ET0 and rain; the ensemble band's coverage (how often the outcome fell inside P10–P90), which decides Q10's revisit (ratio scaling vs per member).
  - **Canopy:** each crop's default curve and fitted curves (`CanopyCurve`, `CanopyFit`) against the percent cover and LAI readings growers entered, by crop and days since emergence; what `Canopy#check` flagged; feeds the curve refits under "Canopy and LAI readings in the 2027 season".
  - **Water balance:** modeled AD against entered soil moisture readings where fields have them (the drawdown check of the percent-cover refit below).
  - **Corrections from the evidence:** tools to apply what the comparisons show, either one-time (a refit, recorded as a new table version with its evidence, like the weather corrections) or ongoing (a correction recomputed as data accumulates), each versioned and listed on the About page.
  - **Usage metrics, collected natively** (no third-party analytics): page views and active users by day, which pages and features are used (entries, setup, map layers, exports, time travel), sign-in methods, digest opens or clicks if measurable without tracking pixels, devices by screen size; stored in our database, aggregated, with no personal data beyond what the account already holds, and a retention limit. Decide what to count and the privacy wording (About page) before building.
  - Anonymised: no grower, farm or field names; groups below a minimum count left out; growers' consent as in Phase 6.7 A.2 where readings leave the account.
- PWA / offline-friendly daily entry.
- Validated LAI or canopy curves for more crops; sensor integrations; a future AgWeather 2 provider.
- **Canopy and LAI readings in the 2027 season** (2026-11-10: the researchers contacted haven't replied, so the curves get checked against our own data). Before the season, pick a few cooperating fields (potato first, then field corn, sweet corn, soybean, snap bean) and a protocol: percent cover about weekly from emergence to vine kill or harvest, by photo (the Canopeo app, which measures green cover from a phone picture), and LAI where a ceptometer can be borrowed, with emergence and vine kill dates recorded. Growers' own WISP 3 readings add to it, with their consent and anonymised as in Phase 6.7 A.2. After the season, rerun the backtest (`docs/canopy/scripts/backtest.py`) and refit the curves, with a note in `docs/canopy/` and a changelog line on the About page. A potato LAI curve, if the data supports one, is the most valuable result (Q2).
- **Refit the percent-cover table (§5.4) against today's ET0** (Q9; Ben, 2026-10-31: no academic is available to refit it, so it has to be done computationally). Its slopes are crop ET over the old API's ET by cover (1.0 at 80% and above), and the old API's ET runs about 1.11 × station FAO-56 grass ET0 (April–October), so at full cover the table meant a Kc of about 1.1, near FAO-56's mid-season values (Table 12: potato 1.15, field corn 1.20, soybean 1.15). With corrected ET0 (1.03 × the stations') it gives about 1.03, 10–14% below those values (it was 3–8% below), so WISP may now under-count full-cover water use. Steps:
  1. Re-express the table against FAO-56 grass ET0 and compare it, band by band, with Allen and Pereira (2009)'s crop coefficient from fraction of ground cover and height (*Irrigation Science* 28: 17–34, doi:10.1007/s00271-009-0182-z: a density coefficient on FAO-56's basal Kcb per crop, plus FAO-56's dual-coefficient soil evaporation in place of the bare-soil steps). Published, per crop, and needs only cover (which WISP has) and crop height (a default per crop).
  2. Check both against measured ET: Wisconsin eddy-covariance records over irrigated crops (Central Sands potato and corn; ask the Kucharik lab and AmeriFlux), and WISP 3's own soil moisture readings once seasons accumulate (the drawdown between two readings with no rain or irrigation between them is crop ET; needs growers' consent and the anonymised extract of Phase 6.7).
  3. Pick a method per crop, with its error against the measurements, and replace `CropEt::PCT_COVER_COEFFICIENTS` or keep it with a scale, recorded as a D# with the evidence; a changelog line on the About page.

---

## 15. Open questions

| # | Question | Status | Needed by |
|---|---|---|---|
| Q1 | Alert threshold and lead-time defaults | **Resolved**: recommendation adopted | – |
| Q2 | How LAI should work, and for which crops | **A adopted for 2027** (B dropped in Phase 6.7); curves per crop (option C) built in Phase 6.7. No outside review coming (2026-11-10): literature, our own work and 2027 readings instead | After launch |
| Q3 | Display units | **Resolved**: inches by default, per-user inch/mm toggle in Settings | – |
| Q4 | Pivot-level irrigation | **Resolved** → D9, §4 `pivot_irrigations` | – |
| Q5 | Can the deploy user run `systemd --user` services? | **Resolved**: yes on staging; new production server provisioned with it (D11, §12) | – |
| Q6 | Alert email sender and DKIM | **Resolved**: Amazon SES over SMTP with DKIM, out of the sandbox (2026-11) | – |
| Q7 | Per-field rainfall correction | **Resolved**: per-day overrides shown next to modeled values; no multiplier; per-field entered-only setting (2026-10-07) | – |
| Q9 | The percent-cover regressions (§5.4) were fitted to the old API's ET; with Open-Meteo's shortwave corrected (D12), ET0 is about 7% below it (1.032 vs 1.114 against station FAO-56, April–October, Wisconsin). Use corrected ET0 as is, or scale crop ET to the old API's level? | **Resolved** (Ben, 2026-10-31): corrected ET0 as is. The regressions' provenance is unknown and likely over a decade old, so the best available is the most accurate weather; a computational refit is under After launch | – |
| Q10 | The ensemble projection's ET0 (§8.5): compute it per member from corrected shortwave, or scale the members by the deterministic run's correction? | **Resolved** (Ben, 2026-11-10): **scale by ratio**, evaluated after a season. The ensemble API has every input for all 31 members, but each member counts as a variable, so per member takes a cell's ensemble from about 7 calls a refresh to about 21 (each refresh from about 14 to 28). The members are one model's perturbed runs, interchangeable by design, so storing more per member wouldn't show which forecasts are better; the archive's daily ET0 and rain per member serve accuracy tracking either way. `Weather::Ensemble.corrected` scales each member by the deterministic forecast's corrected/raw ratio for the day (the mean ratio where that day's raw ET0 is under 0.01 in), keeps the ratios (`et0_ratio`) and records `et0-ensemble-ratio v1`. Revisit with the evaluation page (After launch): if the band's coverage is poor, compute per member with the ensemble refreshed once a day, which costs about what three ratio refreshes do | – |
| Q11 | With corrected ET0 the standard potato field gets 3.3 fewer irrigations a season than WISP 2026 and 4.5 fewer than AgWeather, mostly at full cover in midsummer, where the percent-cover table's Kc (about 1.0 on corrected ET0) is below FAO-56's 1.15–1.20 (Phase 8 E step 8). Ship as is (Q9) and refit after launch, scale full-cover crop ET up for 2027 as a stopgap, or bring the refit (After launch, Allen and Pereira 2009) forward before the beta? | – | Phase 8 E |

### Q1. Alert defaults: resolved (recommendation adopted)

*Update 2026-10-04:* Phase 6 is now a daily digest of every included field rather than alerts for crossings, so the probability and dedupe settings below don't apply. The threshold (target, else AD = 0) and the 3-day lead time live on as the projection's "Irrigate by" and caution status (§6 "As built").

**What it decides:** when a user gets an email saying a field is heading for irrigation.

**Recommendation:**
- **Threshold:** the field's target (`target_ad_pct`) if set; otherwise AD = 0, the MAD trigger point, which matches legacy "AD < 0" problem reporting.
- **Lead time:** 3 days.
- **Ensemble probability:** alert when ≥ 50% of members cross the threshold within the lead time.
- **Delivery:** one digest per user per day at 6 am CT, listing every flagged field; nothing is sent if nothing is flagged.
- All of these can be changed per user, and the beta (Phase 8) is the time to tune them.

### Q2. LAI (leaf area index) method: A + B adopted, review in progress

**Background.** WISP estimates crop water use as reference ET × a crop coefficient (Kc), and Kc grows with the canopy. There are two ways to describe the canopy:
- **Percent cover** (used by almost everyone): the grower enters canopy cover on a few dates, and Kc comes from the A3600 Table C regressions.
- **LAI**: leaf area per unit of ground, turned into Kc with a Beer's-law curve: Kc = 1.1 × (1 − e^(−1.5·LAI)). LAI normally comes from a growth curve, so the grower doesn't have to enter canopy data.

**How much it's used (legacy production, 2025–2026 fields):** 29 of 525 fields (5.5%) use LAI, by crop:

| Crop | LAI fields | What legacy actually computed |
|---|---|---|
| Potato | 14 | Field corn canopy curve |
| Soybean | 8 | Field corn canopy curve |
| Field corn | 6 | Field corn canopy curve (the only correct case) |
| Sweet corn | 1 | Negative ET (C18) |

So 23 of the 29 LAI fields were modeled with a *corn* canopy. Potato is the main case to get right: it is the largest LAI group and a major irrigated crop in the Central Sands.

**What the legacy app actually does:**
- **Field corn and every other crop except sweet corn:** the corn curve from the WIS v6.3.11 spreadsheet, based on calendar days since emergence. It gives LAI ≈ 0.25 at day 30, 1.95 at day 50, 4.07 at day 80 (peak), 3.25 at day 100 and 0.86 at day 140. Kc reaches about 1.0 by day 50. So soybeans, potatoes, onions and the rest under LAI all use a *corn* canopy.
- **Sweet corn:** the placeholder curve, which is broken (C18): negative ET, or none.
- **No way to enter LAI.** There is a column for it, but no screen writes observations to it.

**Questions for an agronomist** (for example the A3600 authors or UW BSE / Soil Science extension):
1. Is the WIS corn curve still a reasonable default for Wisconsin field corn? Should it be driven by **growing degree-days** instead of calendar days, so planting date and a cool or warm year shift the canopy? (WISP 3 can compute GDD from Open-Meteo temperatures; AgWeather isn't needed.)
2. The extinction coefficient of 1.5 and maximum Kc of 1.1: what is their source, and do they suit crops other than corn? Published canopy extinction coefficients are usually lower (about 0.4–0.8), so confirm which formulation the spreadsheet intended.
3. For sweet corn: use the field corn curve shortened to the earlier harvest, a GDD-based curve, or percent cover only?
4. Are there trustworthy curves for potato, snap bean or soybean, the other big Wisconsin irrigated crops? If not, those crops should only be offered percent cover, or LAI with entered observations.
5. Is it useful to let growers **enter LAI readings** (from a ceptometer or app) that override the curve, as they can with percent cover?

**Options:**

| Option | What growers get | Risk |
|---|---|---|
| A. Corn curve for field corn only; everything else uses percent cover | Simple and honest | Loses LAI for other crops; little value lost if nobody uses it |
| B. A + entered LAI observations allowed for any crop | Flexible for advanced users | Needs a good help page on how to measure LAI |
| C. GDD-based curves per crop | Most realistic | Needs validated curves, which we don't have yet |

**Decision:** ship **A + B** for 2027 (already reflected in §5.3). *Revised 2026-10-15 (Phase 6.7): B is dropped; LAI only for crops with an LAI curve.* An agronomist has been contacted with the questions above. **C (curves per crop, by GDD or calendar days) is brought forward to Phase 6.7 (2026-10-15).**

Groundwork in the meantime: Phase 3 stores daily tmax/tmin and calculates daily and cumulative GDD (base 50 °F, 86 °F cap, the standard corn method). GDD-based curves then need no new data plumbing, and GDD can be shown in the UI.

**Production usage query** (run on the legacy production server; it only reads):
```bash
cd ~/wisp/current && RAILS_ENV=production bundle exec rails runner '
  recent = Field.joins(:pivot).where(pivots: {cropping_year: 2025..})
  puts "Fields by ET method: #{recent.group(:et_method).count.inspect}  (1 = pct cover, 2 = LAI)"
  lai = recent.where(et_method: 2).includes(crops: :plant).map { |f| f.crops.max_by(&:emergence_date)&.plant&.name }.tally
  puts "LAI fields by crop: #{lai.inspect}"
  puts "Groups set to Manual rainfall: #{Group.where(precip_use_agwx: false).count} of #{Group.count}"
  puts "irrigation_events rows: #{IrrigationEvent.count}"
  puts "Fields per pivot (fields => pivots): #{Pivot.joins(:fields).where(cropping_year: 2025..).group(:id).count.values.tally.sort.inspect}"
  puts "Pivots still at default 43,-89: #{Pivot.where(latitude: 43, longitude: -89).count} of #{Pivot.count}"
'
```
**Given the numbers:**
- Option A alone would move 23 fields (mostly potato) to percent cover, which is arguably *more* correct than the corn curve they had.
- A + B lets those growers keep LAI if they enter readings.
- A potato canopy curve would be the single most valuable result of the agronomy review (question 4).

Ask for the review in Phase 2 so its answer can land in the engine before the Phase 4 UI.

### Q3. Display units: resolved

- **Storage stays in inches** everywhere. Units are a display and input concern only.
- **Per-user setting** `users.unit_system` (`imperial` default | `metric`) in a Settings menu, applying to:
  - water depths (in ↔ mm)
  - temperatures (°F ↔ °C)
  - area (ac ↔ ha)
  - pump capacity (gpm ↔ L/s)
- Percent values (soil moisture, cover, MAD) don't change.
- **Implementation:**
  - A small `units.ts` module of formatters and parsers, used by every display and input.
  - Conversion happens only at that edge.
  - Serializers always send inches.
  - The editable grid parses user input in the chosen unit and converts back to inches before submitting.
  - Phase 4.

### Q4. Pivot-level irrigation: resolved

Use case (from you): a pivot covers 1–2 fields (a split for two crops or two varieties), and usually all of them get the same water. The design is in §4 (`pivot_irrigations`) and D9:
- Entered once on the pivot, as inches or run hours.
- Applies to every field under the pivot, or a chosen subset.
- Applied when read, so editing the pivot entry updates every field.
- A per-field value overrides it.

The legacy `irrigation_events` table had no routes, so nothing should be in it; the usage query above confirms.

### Q5. `systemd --user` on the servers: resolved

- **Staging:** `Linger=yes`, and user services work. WISP 3 staging runs `wisp-jobs.service` (and optionally `wisp-web.service`) as `deploy`.
- **Old production:** both checks failed; out of scope, since WISP 3 production goes on a new server (D11). Its requirements in §12 include `loginctl enable-linger deploy`.
- **Before handing the new server over,** re-run the check from the staging test (start a throwaway user service, log out, log back in, confirm it's still active).

### Q6. Alert email sender and DKIM

*Resolved (2026-11):* production sends through Amazon SES's SMTP interface with the sender verified and DKIM passing, out of the sandbox (Phase 8 D, `docs/deployment.md` step 7). Staging still uses the host's sendmail. The questions below were for the old campus setup.

The app currently sends as `agweather@cals.wisc.edu` through local `sendmail`. Ask campus IT:
1. Is mail from these hosts relayed through a campus server that signs DKIM for `cals.wisc.edu`?
2. Does the SPF record cover these hosts?
3. Is a daily digest to a few hundred recipients acceptable volume?

If any answer is no, use an authenticated SMTP relay (campus relay or a transactional email provider) in the production Action Mailer config. Sending a test to a Gmail address and reading "Show original" will show SPF/DKIM pass or fail.

### Q7. Rainfall corrections: resolved

- **Per-day overrides only**, plus the group-level modeled/manual switch. No multiplier: rainfall is highly localized, so a fixed ratio wouldn't hold from storm to storm.
- **Modeled values always stay visible next to entered corrections**:
  - **Daily grid:** an overridden rain cell shows the entered value with the modeled value beside it in muted text (e.g. `0.80  (model 0.35)`); hovering or tapping shows both and their difference.
  - **Chart:** an entered rain bar is drawn solid, with the modeled amount as an outlined "ghost" bar behind it.
  - **Field summary:** season totals of entered vs modeled rain over the days with entries, so growers can see how their gauge compares with the model.
- The resolver (§4) already keeps both values; it returns `rain_model_in` alongside the resolved `rain_in` and its provenance.
- Revisit a correction factor after a season of gauge-vs-model data.

**Added (2026-10-07, Ben):** the modeled/manual switch can also be **set per field** (Phase 6.6). It is a setting read when the balance runs; it never copies or deletes entries, so switching back restores the modeled rain exactly.
- **Entered-only applies through today; the projection still uses forecast rain.** Nobody can enter future rain, and the forecast is expected to be roughly right; growers choosing entered-only mostly want exact amounts, or know storms often miss their field. This changes the existing group-level switch too (it zeroed forecast rain).
- **Entered-only fields also show a "no rain" projection**: the same balance with no forecast rain (planned irrigation kept), so the grower sees both the forecast case and the dry case. Status, "Irrigate by" and the digest follow the forecast case.
- Field rain entries and field-group rain entries both count as entered.

### Q8. Group member roles

Today every member of a group can do everything: rename it, switch its rainfall setting, and delete farms, pivots and fields. That's fine while each group has one person, but invitations (Phase 8 stretch) need a decision. Suggestion: **owner** (everything, including managing members and deleting) and **member** (data entry and setup, but not deleting farms or the group, or managing members). `memberships.admin` already exists and could become the owner flag.

**Decided (2026-10-04):** owner and member as suggested. `memberships.admin` is renamed `owner`. Owners only: the group's name and rainfall setting, adding and removing members and changing roles, and deleting farms, pivots, fields or the group (`AuthenticatedController#require_owner`). Members can do everything else, including deleting plantings, irrigation and field groups. Members are added by the email of an existing, confirmed account; there are no invitations for people without one. A group always has an owner: the last owner can't step down or leave, and deleting the account of a group's only owner hands it to its longest-standing member.

