"""AgWeather v2's corrected hours for WISP's port to match (PLAN.md Phase 8 E, step 6).

Runs v2's own pipeline (`agdata.sources.openmeteo.fetch`, then `correct`) on v2's recorded Open-Meteo
responses (three June 2025 days at the O1280 cell over Stillwater, OK: NBM then best_match from the
historical-forecast API, UTC, unixtime, wind in m/s) and writes each hour's inputs and v2's corrected
shortwave, dew point, RH and ET0 to WISP's spec fixtures. spec/services/weather/v2_match_spec.rb feeds the
same responses through Weather::Hours and checks every hour.

v2 computes the hourly ET0 with FAO-56's 1998 surface resistance (70 s/m every hour); WISP follows the second
edition's (Pereira and others 2025, eq. 2.5a/2.5b: 50 s/m while Rn >= 0, 200 s/m while Rn < 0; PLAN.md §9 C24).
So the ET0 written is v2's `agmodels.weather.et0_hourly_series` on those corrected hours with Rev.1's form
swapped into its `et0_hourly_mm`, until v2 adopts it.

Run from an AgWeather v2 checkout (bbb0a6d; later commits changed the pipeline's output), with WISP 3 beside it:

    uv run python -I ../wisp3/docs/weather-corrections/v2_expected.py ../wisp3

`--et0-only` recomputes just the ET0 from the hours already in the fixture (any v2 commit; how the Rev.1 values
were written, 2026-11-19, from v2 at 7b7aae7, where the 1998 form reproduced the fixture's ET0 exactly).
"""

import json
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path
from unittest import mock

import numpy as np
import requests

from agmodels import weather

wisp = Path(sys.argv[1]).resolve()
out = wisp / "spec/fixtures/files/weather_corrections"


ABOUT = "AgWeather v2's corrected hours at its recorded Open-Meteo responses, ET0 in FAO-56 Rev.1's form (docs/weather-corrections/v2_expected.py)"


def series(values):
    return [None if not np.isfinite(v) else float(v) for v in values]


def et0_hourly_mm_rev1(temperature_c, vapor_pressure_kpa_, wind_speed_2m_m_s, net_radiation_mj, soil_heat_flux_mj, pressure_kpa):
    """Rev.1 eq. 2.5a/2.5b: v2's et0_hourly_mm with (1 + 0.24 u2) by day and (1 + 0.96 u2) at night."""
    t = np.asarray(temperature_c, dtype=float)
    delta = weather.svp_slope_kpa_per_c(t)
    gamma = weather.psychrometric_constant_kpa_per_c(pressure_kpa)
    u2 = np.asarray(wind_speed_2m_m_s, dtype=float)
    rn = np.asarray(net_radiation_mj, dtype=float)
    deficit = weather.saturation_vapor_pressure_kpa(t) - np.asarray(vapor_pressure_kpa_, dtype=float)
    numerator = 0.408 * delta * (rn - soil_heat_flux_mj) + gamma * 37 / (t + 273) * u2 * deficit
    return np.maximum(numerator / (delta + gamma * (1 + np.where(rn >= 0, 0.24, 0.96) * u2)), 0)


def et0_rev1(expected):
    """Each hour's ET0 (mm) from the corrected hours in `expected`, with Rev.1's form."""
    f = lambda key: np.array([np.nan if v is None else v for v in expected[key]], dtype=float)  # noqa: E731
    with mock.patch.object(weather, "et0_hourly_mm", et0_hourly_mm_rev1):
        return weather.et0_hourly_series(
            np.array(expected["hour_end"], dtype="datetime64[s]"),
            expected["latitude"],
            expected["longitude"],
            f("temperature_c"),
            f("dew_point_c"),
            f("wind_speed_10m_m_s"),
            f("pressure_kpa"),
            f("shortwave_w_m2"),
        )


if "--et0-only" in sys.argv:
    expected = json.loads((out / "v2_expected.json").read_text())
    expected["about"] = ABOUT
    expected["et0_mm"] = series(et0_rev1(expected))
    (out / "v2_expected.json").write_text(json.dumps(expected, indent=1) + "\n")
    print(f"wrote {out}/v2_expected.json: ET0 {np.nansum(expected['et0_mm']):.2f} mm (Rev.1)")
    sys.exit()

from agdata.sources import openmeteo  # noqa: E402

fixtures = Path(openmeteo.__file__).parents[3] / "tests/fixtures"
cell = openmeteo.cell_for(36.12, -97.07)


def fake_get(self, address, params=None, **kwargs):
    response = mock.Mock(status_code=200)
    response.json.return_value = json.loads((fixtures / f"openmeteo_historical_{params['models']}.json").read_text())
    return response


with mock.patch.object(requests.Session, "get", fake_get):
    hours, _ = openmeteo.fetch("historical", cell, date(2025, 6, 1), date(2025, 6, 3))
corrected = openmeteo.correct(hours, cell, "historical")


v, raw = corrected.values, corrected.raw
expected = {
    "about": ABOUT,
    "v2_commit": subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip(),
    "latitude": cell.latitude,
    "longitude": cell.longitude,
    "corrections": list(corrected.corrections),
    "hour_end": [int(corrected.start.timestamp()) + 3600 * k for k in range(corrected.count)],
    "temperature_c": series(v["air_temperature"]),
    "dew_point_raw_c": series(raw["dew_point"]),
    "wind_speed_10m_m_s": series(v["wind_speed"]),
    "pressure_kpa": series(v["surface_pressure"]),
    "shortwave_raw_w_m2": series(raw["shortwave_radiation"]),
    "shortwave_w_m2": series(v["shortwave_radiation"]),
    "dew_point_c": series(v["dew_point"]),
    "relative_humidity_percent": series(v["relative_humidity"]),
}
expected["et0_mm"] = series(et0_rev1(expected))
(out / "v2_expected.json").write_text(json.dumps(expected, indent=1) + "\n")
for model in openmeteo.PRIMARY_MODELS:
    shutil.copy(fixtures / f"openmeteo_historical_{model}.json", out / f"openmeteo_historical_{model}.json")
print(f"wrote {out}: {corrected.count} hours, ET0 {np.nansum(expected['et0_mm']):.2f} mm (Rev.1), corrections {corrected.corrections}")
