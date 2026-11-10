"""AgWeather v2's corrected hours for WISP's port to match (PLAN.md Phase 8 E, step 6).

Runs v2's own pipeline (`agdata.sources.openmeteo.fetch`, then `correct`) on v2's recorded Open-Meteo
responses (three June 2025 days at the O1280 cell over Stillwater, OK: NBM then best_match from the
historical-forecast API, UTC, unixtime, wind in m/s) and writes each hour's inputs and v2's corrected
shortwave, dew point, RH and ET0 to WISP's spec fixtures. spec/services/weather/v2_match_spec.rb feeds the
same responses through Weather::Hours and checks every hour.

Run from an AgWeather v2 checkout (bbb0a6d or later), with WISP 3 beside it:

    uv run python -I ../wisp3/docs/weather-corrections/v2_expected.py ../wisp3
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

from agdata.sources import openmeteo

wisp = Path(sys.argv[1]).resolve()
out = wisp / "spec/fixtures/files/weather_corrections"
fixtures = Path(openmeteo.__file__).parents[3] / "tests/fixtures"
cell = openmeteo.cell_for(36.12, -97.07)


def fake_get(self, address, params=None, **kwargs):
    response = mock.Mock(status_code=200)
    response.json.return_value = json.loads((fixtures / f"openmeteo_historical_{params['models']}.json").read_text())
    return response


with mock.patch.object(requests.Session, "get", fake_get):
    hours, _ = openmeteo.fetch("historical", cell, date(2025, 6, 1), date(2025, 6, 3))
corrected = openmeteo.correct(hours, cell, "historical")


def series(values):
    return [None if not np.isfinite(v) else float(v) for v in values]


v, raw = corrected.values, corrected.raw
expected = {
    "about": "AgWeather v2's corrected hours at its recorded Open-Meteo responses (docs/weather-corrections/v2_expected.py)",
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
    "et0_mm": series(v["et0"]),
}
(out / "v2_expected.json").write_text(json.dumps(expected, indent=1) + "\n")
for model in openmeteo.PRIMARY_MODELS:
    shutil.copy(fixtures / f"openmeteo_historical_{model}.json", out / f"openmeteo_historical_{model}.json")
print(f"wrote {out}: {corrected.count} hours, ET0 {np.nansum(v['et0']):.2f} mm, corrections {corrected.corrections}")
