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
| D11 | **New production server** for the 2027 season, provisioned to the spec in §12. Staging already supports `systemd --user` with linger; the old production box is out of scope |

---

## 3. Architecture and stack

```
Browser (Svelte 5 pages, Tailwind v4, ECharts, MapLibre)
   │  Inertia protocol (JSON page props over normal Rails requests; session cookie + CSRF)
Rails 8.1 (Ruby 4.0)
   ├── Controllers → Inertia responses (render inertia: "Fields/Show", props: …)
   ├── Devise (+ magic-link strategy)
   ├── Domain services: WaterBalance, Projection, Canopy, WeatherIngest, AlertEvaluator
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
| Styling | **Tailwind CSS v4** via `@tailwindcss/vite`, CSS-first config (`@theme` in `app.css`) | Design tokens for status colors (full/ok/caution/irrigate) defined once |
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
- **pivots**: `name, latitude, longitude, radius_ft, arc_start_deg, arc_end_deg (nullable = full circle), equipment, pump_capacity_gpm, notes`.
  - **Location is required and has no default.** In legacy production, 215 of 443 pivots (49%) were still at the default 43, −89, so half of all fields got weather for the wrong place.
  - Pivot creation therefore starts with a map picker (click the pivot center, drag the radius) or typed coordinates, validated to fall within a US-and-Canada bounding box (latitude 18–84, longitude −180 to −52). Weather coverage is global, so this can widen later.
- **fields**: `name, area_acres, soil_type_id, field_capacity, perm_wilting_pt` (nullable, so NULL means "use the soil type default"; the legacy code used 0.0 for that), `notes`, optional `boundary` (GeoJSON jsonb) for non-pivot or partial areas.
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
- **weather_forecasts**: `weather_cell_id, issued_at, model, kind (deterministic|ensemble), payload jsonb` (`{"days": [{date, <weather_days columns>}, …]}`; the ensemble payload is defined in Phase 5). Keep the most recent 14 issues per cell for later checks of forecast accuracy, and prune older ones.
- **users** (beyond Devise columns): `first_name, last_name, admin, unit_system (imperial|metric, default imperial)`.
- **alert_preferences**: `user_id, enabled, lead_days (default 3), threshold (enum: target | mad_zero), min_probability (for ensemble, default 0.5), send_hour_local (default 6), digest (bool)`.
- **alert_deliveries**: `user_id, planting_id, projected_cross_date, sent_at`. Dedupe key `(planting_id, projected_cross_date ± 1 day)`. The same projected crossing is not re-sent unless it moves earlier by ≥2 days or the field was refilled in between.

### Precedence when resolving a day's inputs for a field

```
rain       = field_entry.rain_in ?? group_entry.rain_in ?? (group.use_model_precip ? weather.precip_in : 0.0)
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
  - **Which crops get which curve, and whether to switch to degree-day curves, depends on Q2.** Until then, the corn curve is offered only for field corn, and other crops can use LAI only with entered observations.
  - **Legacy problems (C4, C18):** the corn curve was applied to every crop, and sweet corn's placeholder curve produces **negative ET**.
  - The engine takes a `CanopyModel` per plant, so adding validated curves later is a data change.
  - With LAI readings entered, they replace the curve entirely (interpolated like percent cover); with none, the curve is used, or LAI 0 (no ET) for plants without one. Revisit blending readings with the curve after Q2.

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
| `WeatherRefreshJob` | 05:00, 11:00, 17:00 | For active cells (a planting this year or still running): the last 7 days (provisional `weather_days`) and a 16-day `weather_forecasts` row from the forecast API; then queues a backfill per cell |
| `WeatherBackfillJob` | When a pivot gets a new cell, and after each refresh | Fills missing days from the cell's season start (or the last 30 days) through yesterday from the **historical-forecast API** (same models as the forecast, so the series is consistent); days older than a week are stored final |
| `WeatherFinalizeJob` | 03:00 | Days more than 7 days old become final; refreshes no longer overwrite them |
| `ForecastPruneJob` | Sundays 04:00 | Keep the latest 14 forecasts per cell |
| Ensemble refresh | — | Moved to Phase 5 with the projection that uses it |

Weather fetching **never** happens inside a web request (legacy fetched synchronously on page view, which is why fields nobody opened never got data). `bin/rails weather:refresh` runs a refresh and backfill by hand.

### 8.4 The AgWeather → Open-Meteo shift (validation task in Phase 3)

The reference-ET method differs: legacy used AgWeather's ET product (see `public/diakEtal1998.pdf` in the legacy repo); Open-Meteo uses FAO-56 Penman-Monteith. The A3600 percent-cover regressions were developed against the legacy reference ET. Phase 3 produces a comparison report: for the 2025 and 2026 seasons at real pivot locations, AgWeather ET and precipitation vs Open-Meteo (`best_match`, NBM), with season totals, daily bias and scatter, and the resulting difference in AD and irrigation trigger dates. **Exit criterion:** the shift is understood and documented. If there's a consistent bias, decide whether to apply a correction or document it for users.

The comparison uses AgWeather's public API (`bin/rails weather:compare`, report in `docs/weather-comparison.md`). It is not a runtime dependency, and no legacy data enters WISP 3 (D10).

**Result (2026-10-03; 12 points in Wisconsin's irrigated areas, 2025 and 2026 seasons):**
- **ET:** all models within a few percent of AgWeather: best_match +8%, NBM +2%, ECMWF IFS +3% (r 0.87–0.90).
- **Rain:** best_match is the outlier: 79% of AgWeather's total and 844 rain days against AgWeather's 1,425. NBM 93% (r 0.79), ECMWF 83%.
- **Effect on a standard potato field:** best_match calls for about **6 more irrigations a season** than AgWeather; NBM 1.5 fewer; ECMWF 0.4 fewer. All three Open-Meteo models put the **first irrigation 10–16 days earlier** than AgWeather, which needs a look (early-season ET or rain; TODO.md).
- **Decision:** NBM, with best_match as fallback (§8.2). No correction factor for now.
- **Still to do:** re-run at real pivot locations (`POINTS=file.csv`, TODO.md) before the beta.

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
| **Dashboard** (replaces Farm Status) | Card or list per field: status color, AD today, days until the target is crossed (with ensemble probability), last rain and irrigation, sparkline. Filter by farm. Toggle to the map view |
| **Map** | Pivots drawn as circles or arcs from center + radius, colored by status; click opens a popover with summary and link. Setup mode: drag the pivot center, set the radius (the same picker component is used when creating a pivot) |
| **Field status** | Main chart (below), summary box (AD, % moisture, status, recommended irrigation and timing), editable daily grid (date, rain, irrigation, moisture obs, cover obs, notes, with provenance badges), what-if planned irrigation, CSV export |
| **Setup** | Farms → pivots → fields → plantings as nested, inline-editable lists (replaces the jqGrid setup pages). "Copy last season's plantings" action |
| **Field groups** | Create a group, pick fields, enter shared daily values in the same grid component |
| **Daily entry (bulk)** | One date, whole farm: rows are pivots (one irrigation cell per pivot, inches or run hours) that expand to their fields for per-field rain, overrides and observations. Fast entry after a rain or irrigation day |
| **Settings / account** | Profile, password, units (in/mm), alert preferences, group switcher/invites |
| **Admin** | Users, CSV, announcements, weather status (last fetch per cell, API mode, error counts), impersonate |
| **Public** | Landing page, about/methods (from the architecture doc), user guide PDF, announcements |

### Field status chart (ECharts)

- X axis: season dates; default view about 21 days back + 16 days forward, zoomable to the full season.
- Bars, upward on a secondary axis: rain (blue), irrigation (teal), planned irrigation (hatched).
- Line: AD (inches) observed (solid) → deterministic projection (dashed).
- Band: ensemble P10–P90 for future days.
- Horizontal lines: AD_max (field capacity), target, 0 (MAD trigger), AD_pwp (wilting point).
- `markArea` shading for the forecast region; marker on today.
- Optional toggle to show % soil moisture instead of AD inches.
- Tooltip: all resolved inputs for the day with provenance.

---

## 12. Deployment and operations

- **Hosts**: staging (dev.wisp.cals.wisc.edu, existing box; `systemd --user` and linger confirmed) and a **new production server** (D11). Capistrano + rbenv, same workflow as legacy.
- **Web and jobs on the new hosts**: nginx → Puma, with both Puma and Solid Queue run as `systemd --user` units owned by `deploy` (`wisp-web.service`, `wisp-jobs.service`) and restarted by Capistrano hooks without sudo. This replaces Passenger, so web and jobs are managed the same way. Staging uses the same setup (units `wisp3-web` and `wisp3-jobs`, Puma on 127.0.0.1:3100); see `docs/deployment.md`.
- **Assets**: Node is needed at build time for `vite build`. `vite_rails` hooks into `assets:precompile`, so the Capistrano flow is unchanged.
- **Database**: Postgres on the new server, `wisp3_production`. Nightly `pg_dump` copied off the box.

### New production server: requirements for the sysadmin

| Item | Requirement |
|---|---|
| OS | Current Ubuntu LTS (24.04) or the campus-standard equivalent |
| Size | 2 vCPU, 4 GB RAM, 40 GB disk is ample (the data is small; the largest table is weather cache rows) |
| Packages | nginx, PostgreSQL 16+ (server and `libpq-dev`), build tools for rbenv/ruby-build (Ruby 4.0.x), Node.js 24 LTS, git |
| `deploy` user | SSH key access (port 216 as today), owns `/home/deploy/wisp3`, **`loginctl enable-linger deploy`**, a working `systemctl --user` |
| Network | Inbound 80/443 (and SSH). Outbound HTTPS to `*.open-meteo.com` (API) and GitHub (deploys). Map tiles are loaded by browsers, not the server |
| TLS | Certificate for the production hostname (campus CA or Let's Encrypt via certbot) |
| Mail | A relay that signs DKIM for the sender domain, or SMTP credentials for one (Q6) |
| Backups | Nightly `pg_dump` to off-server storage, 30-day retention; a restore tested once before launch |
| DNS | Decide the hostname switch at launch: `wisp.cals.wisc.edu` moves to the new box; legacy moves to e.g. `legacy.wisp.cals.wisc.edu` (§13) |
- **Mail**: sendmail as now. Before alerts launch, confirm SPF and DKIM for the sender domain with campus IT. Add `List-Unsubscribe` and one-click unsubscribe to alert emails.
- **Secrets**: Rails credentials per environment (`OPEN_METEO_API_KEY`, SMTP if needed).
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
- [ ] Send the §12 server requirements to the sysadmin so the new production box is ready by February.
- **Exit:** a user can sign up, confirm, sign in by password or link, and see an empty dashboard on staging. *(Verified locally in a headless browser, desktop and phone/dark; staging live 2026-10-03; sign-up and email delivery on staging still to check.)*

### Phase 2: Domain and engine

- [x] Migrations and models for §4 (weather tables wait for Phase 3); plants and soil types in `db/reference/*.yml`, loaded by `ReferenceData` on `db:seed` and on every deploy.
- [x] `WaterBalance`, `Canopy`/`CanopyModel`, `CropEt` (`app/services`) with the §5 fixes and unit tests; property tests for AD bounds and water conservation.
- [x] `DailyInputs` resolver (precedence and provenance, including pivot irrigation and run hours); `PlantingBalance` runs a planting's season from the database.
- [x] Golden test harness: `spec/support/legacy_engine.rb` reproduces legacy with each fix switchable (with all fixes it equals `WaterBalance`); `spec/golden` checks each fixture field and attributes every differing day to a fix. Export script `script/legacy/export_golden_fixtures.rb` (checked against the local legacy dev DB, whose 2026 fields have no weather).
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
- [x] Verified locally on the free API: every demo pivot has season-to-date data and a current forecast. Still to check with the commercial key and on staging (TODO.md).
- **Exit:** every pivot in the demo seed data has season-to-date data and a current forecast; comparison report written and decision recorded.

### Phase 4: Core UI

- [ ] Setup pages (farms/pivots/fields/plantings), "copy last season", and a guided first-run setup (target: two-field pivot in under 5 minutes, §13).
- [ ] Pivot location picker (MapLibre, click center, drag radius) used in pivot creation; location required.
- [ ] Editable daily grid component; field status page with the summary box.
- [ ] ECharts chart: observed AD, inputs, thresholds, zoom.
- [ ] Weather panels on the field page from `weather_days` and the forecast (Ben's request): modeled soil moisture by depth (against the field's FC/PWP) and soil temperature, GDD since emergence, temperature, humidity/VPD, wind and cloud cover.
- [ ] Dashboard (field cards, status), bulk daily entry, field groups.
- [ ] Pivot irrigation entry (inches or run hours, which fields it applied to) with "from pivot" badges and per-field overrides in field grids.
- [ ] CSV export (parity with legacy columns).
- [ ] Settings menu with the unit toggle (Q3) and the `units.ts` formatters and parsers used by every display and input.
- [ ] Modeled rain shown next to entered corrections in the grid, chart and season summary (Q7).
- **Exit:** the main legacy features are all available; an internal user can manage a season end to end.

### Phase 5: Forecast projection

- [ ] Deterministic projection through the 16-day forecast.
- [ ] Ensemble spike (et0 per member?), then the ensemble runner, P10/P50/P90 band, crossing probability.
- [ ] Planned irrigation (what-if) and recommended irrigation amount and timing.
- **Exit:** the chart shows observed → forecast → band; adding a planned irrigation updates the projection in under 300 ms.

### Phase 6: Alerts

- [ ] Alert preferences UI; `AlertEvaluatorJob` after each ensemble refresh; daily digest email at the user's chosen hour.
- [ ] Dedupe (`alert_deliveries`), unsubscribe link, `List-Unsubscribe` header, SPF/DKIM check.
- [ ] Admin preview: "what would be sent today".
- **Exit:** staging sends correct digests for test fields across simulated scenarios (rain refill, sudden heat, planned irrigation suppressing an alert).

### Phase 7: Map

- [ ] MapLibre map, USGS imagery + OpenFreeMap streets, pivot circles and arcs colored by status.
- [ ] Map as a dashboard view (the setup picker shipped in Phase 4), status coloring, popovers, farm filter.
- [ ] Moving a pivot (or changing its cell) triggers a backfill and recalculation.
- **Exit:** every pivot in the demo seed data is visible, and editing a location updates its weather within one job cycle.

### Phase 8: Polish, beta, launch

- [ ] Accessibility pass (keyboard grid, contrast, chart table alternative), performance pass, empty states, onboarding tour.
- [ ] Methods/help pages from the architecture doc; updated user guide.
- [ ] Stretch: group invitations and the group switcher UI (A8).
- [ ] Closed beta with a handful of growers or extension agents on staging, each setting up their own operation from scratch (this validates onboarding as well as the app).
- [ ] New production server provisioned (§12), deploy rehearsed, backups and restore tested.
- [ ] Legacy goes read-only (sign-ups disabled, banner) and moves to its legacy hostname; DNS switch; **launch by ~Mar 20, 2027** (§13).
- **Exit:** WISP 3 live on the new server before April 1; announcement emailed to legacy users from the legacy app (new address, create a new account, sign-in links, setup guide).

### After launch

- Forecast accuracy tracking (stored forecasts vs finalized weather).
- PWA / offline-friendly daily entry.
- **GDD-driven canopy curves** (Q2 option C), starting with potato and corn, using the agronomist's input.
- Validated LAI or canopy curves for more crops; sensor integrations; a future AgWeather 2 provider.

---

## 15. Open questions

| # | Question | Status | Needed by |
|---|---|---|---|
| Q1 | Alert threshold and lead-time defaults | **Resolved**: recommendation adopted | – |
| Q2 | How LAI should work, and for which crops | **A + B adopted for 2027**; agronomist contacted; GDD curves on the post-launch list | Review answers by Phase 4 |
| Q3 | Display units | **Resolved**: inches by default, per-user inch/mm toggle in Settings | – |
| Q4 | Pivot-level irrigation | **Resolved** → D9, §4 `pivot_irrigations` | – |
| Q5 | Can the deploy user run `systemd --user` services? | **Resolved**: yes on staging; new production server provisioned with it (D11, §12) | – |
| Q6 | Alert email sender and DKIM | Ask campus IT | Phase 6 |
| Q7 | Per-field rainfall correction | **Resolved**: per-day overrides shown next to modeled values; no multiplier | – |

### Q1. Alert defaults: resolved (recommendation adopted)

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

**Decision:** ship **A + B** for 2027 (already reflected in §5.3). An agronomist has been contacted with the questions above. **C (GDD-driven curves) stays on the post-launch list.**

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
