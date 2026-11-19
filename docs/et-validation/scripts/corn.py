# Corn at US-CC1 and US-CC2 (2021), and the same measure at the potato towers as a check
# (docs/et-validation/05-corn.md). Python 3, standard library only.
#
#   python3 -I docs/et-validation/scripts/corn.py [DIR]
#
# The corn towers' AmeriFlux BASE files aren't gap-filled, so whole days of ET are rare. Instead the
# crop coefficient is a ratio of daytime sums: measured ET over FAO-56 ET0 (WISP's hourly chain,
# from et0.py) over the hours from 08 to 18 local standard time that have LE and every ET0 input
# measured, on days with at least 16 of those 20 half-hours. Closure is the same hours'
# Σ(H + LE) / Σ(Rn − G), with G as 0 where it isn't measured and, as a bound, as FAO-56's daytime
# 0.1 Rn. The potato towers, run the same way over July, show how this daytime
# measure compares with the daily one in 03.
import csv, glob, math, os, sys
from collections import defaultdict
from datetime import timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # et0.py beside this file
import et0 as e  # noqa: E402

ROOT = sys.argv[1] if len(sys.argv) > 1 else "tmp/ameriflux"
WINDOWS = {  # full canopy, judged from the calendar (Central Sands corn planted around May 1)
    "US-CC1": ("07-10", "08-31"), "US-CC2": ("08-14", "08-31"),
    "US-CS1": ("07-01", "07-31"), "US-CS3": ("07-01", "07-31"), "US-CS4": ("07-01", "07-31"),
    "US-CS5": ("07-01", "07-31"), "US-CS6": ("07-01", "07-31"), "US-CS8": ("07-01", "07-31"),
}


def daytime(site):
    meta = e.SITES[site]
    hours = defaultdict(list)
    for hh in e.read_halfhours(os.path.join(ROOT, site)):
        end = hh["end"]
        hours[end if end.minute == 0 else end + timedelta(minutes=30)].append(hh)
    first, last = WINDOWS[site]
    ratio = e.DEFAULT_RS_RSO
    per_day = defaultdict(lambda: [0, 0.0, 0.0, 0.0, 0.0, 0, 0.0])  # half-hours, ET mm, ET0 mm, avail MJ, turb MJ, hours, avail with G modeled MJ
    for hour_end in sorted(hours):
        hh = hours[hour_end]
        utc_end = hour_end - timedelta(hours=e.UTC_OFFSET_H)
        ra = e.ra_hourly(utc_end, meta["lat"], meta["lon"])
        sw = [x["sw"] for x in hh]
        # carry the cloudiness ratio through every hour with shortwave, as et0.py does
        if None not in sw and hh[0]["pa"] is not None:
            rs = max(sum(sw) / len(sw), 0) * e.W_M2_HOUR_TO_MJ
            rso = (0.75 + 2e-5 * e.elevation_from_pressure(hh[0]["pa"])) * ra
            if rso > 0 and e.solar_elevation(utc_end - timedelta(minutes=30), meta["lat"], meta["lon"]) > e.CLOUDINESS_MIN_ELEVATION_DEG:
                ratio = max(e.RS_RSO_MIN, min(1.0, rs / rso))
        md = hour_end.strftime("%m-%d")
        if not (first <= md <= last) or not (9 <= hour_end.hour <= 18):
            continue
        ok = [x for x in hh if x["measured"] and x["le"] is not None and x["le_measured"] and None not in (x["rn"], x["h"])]
        if len(ok) != len(hh) or len(hh) != 2:
            continue
        t = sum(x["ta"] for x in hh) / 2
        vpd = sum(x["vpd"] for x in hh) / 2
        ws = sum(x["ws"] for x in hh) / 2
        pa = sum(x["pa"] for x in hh) / 2
        rs = max(sum(x["sw"] for x in hh) / 2, 0) * e.W_M2_HOUR_TO_MJ
        ea = max(e.es(t) - vpd / 10, 0.01)
        rn0 = e.net_radiation_hourly(rs, ratio, t, ea)
        et0 = e.et0_hourly(t, ea, e.wind_2m(ws, meta["wind_h"]), rn0, 0.1 * rn0, pa)
        day = per_day[hour_end.date()]
        day[0] += 2
        day[1] += sum(x["le"] for x in hh) * e.HH_MJ / e.LAMBDA
        day[2] += et0
        day[3] += sum(x["rn"] - (x["g"] or 0.0) for x in hh) * e.HH_MJ
        day[4] += sum(x["h"] + x["le"] for x in hh) * e.HH_MJ
        day[5] += 1
        day[6] += sum(x["rn"] - (x["g"] if x["g"] is not None else 0.1 * x["rn"]) for x in hh) * e.HH_MJ
    days = [d for d in per_day.values() if d[0] >= 16]
    if not days:
        return None
    et, et0, avail, turb, avail_g = (sum(d[i] for d in days) for i in (1, 2, 3, 4, 6))
    return len(days), et / et0, turb / avail, turb / avail_g


def main():
    print("| Site | Crop | Window | Days | Daytime ET / ET0 | Daytime closure | Corrected | Closure, G = 0.1 Rn where unmeasured | Corrected |")
    print("|---|---|---|---|---|---|---|---|---|")
    for site in WINDOWS:
        if not os.path.isdir(os.path.join(ROOT, site)):
            continue
        r = daytime(site)
        if r:
            n, k, c, cg = r
            print(f"| {site} | {e.SITES[site]['crop']} | {' to '.join(WINDOWS[site])} | {n} | {k:.2f} | {c:.2f} | {k / c:.2f} | {cg:.2f} | {k / cg:.2f} |")


if __name__ == "__main__":
    main()
