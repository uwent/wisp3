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
#
# Both corn fields were dryland field corn (Paul Stoy, 2026-11) with no planting dates, so the
# full-canopy windows come from the towers themselves (midday CO2 uptake, NDVI at US-CC2; the
# day-by-day table this prints), and only days with moist soil count: WISP models a well-watered
# crop, and dryland corn on sand runs short of water between rains.
import csv, glob, os, sys
from collections import defaultdict
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # et0.py beside this file
import et0 as e  # noqa: E402

ROOT = sys.argv[1] if len(sys.argv) > 1 else "tmp/ameriflux"
CORN = ("US-CC1", "US-CC2")
WINDOWS = {
    # full canopy, from the towers: US-CC1's midday CO2 uptake doubles between Jul 12 and Jul 19
    # and falls off after Aug 21; US-CC2's NDVI is 0.92–0.96 from Jul 6 (before its fluxes start)
    # until Aug 24's storm, after which it drops to 0.73–0.77
    "US-CC1": ("07-19", "08-21"), "US-CC2": ("08-14", "08-23"),
    "US-CS1": ("07-01", "07-31"), "US-CS3": ("07-01", "07-31"), "US-CS4": ("07-01", "07-31"),
    "US-CS5": ("07-01", "07-31"), "US-CS6": ("07-01", "07-31"), "US-CS8": ("07-01", "07-31"),
}
# The corn towers' sonic anemometers read 0.4–0.9 m/s at midday (US-CS5, over potato a few miles
# away, 2.4–2.9 m/s the same months): they sat at or in the canopy top, where the wind is far below
# the 2 m wind over grass that ET0 needs. So ET0 at the corn towers is run on US-CS5's wind for the
# same half-hour (2.5 m over potato, taken to 2 m as et0.py does), and on their own as recorded for
# comparison.
WIND_FROM = {"US-CC1": "US-CS5", "US-CC2": "US-CS5"}
# Moist soil: the day's mean over the tower's soil moisture sensors (their depths aren't in the
# metadata) at or above the point where FAO-56 has maize begin to run short, depletion of 55% of
# the available water (Table 22, p = 0.55), on WISP's Sand (db/reference/soil_types.yml: field
# capacity 11.2%, wilting point 4.5%): 4.5 + 0.45 × 6.7 = 7.5%.
MOIST_SWC = 7.5


def other_wind(site):
    """Half-hour end → (wind m/s, its height m) from the tower WIND_FROM names."""
    source = WIND_FROM[site]
    return {hh["end"]: (hh["ws"], e.SITES[source]["wind_h"]) for hh in e.read_halfhours(os.path.join(ROOT, source)) if hh["ws"] is not None}


def daytime(site, wind=None):
    """Per day: [half-hours, ET mm, ET0 mm, Rn − G MJ, H + LE MJ, hours, Rn − G with G as 0.1 Rn
    where unmeasured MJ], over each site's daytime hours with every input measured; ET0 on another
    tower's wind (other_wind) when given."""
    meta = e.SITES[site]
    hours = defaultdict(list)
    for hh in e.read_halfhours(os.path.join(ROOT, site)):
        end = hh["end"]
        hours[end if end.minute == 0 else end + timedelta(minutes=30)].append(hh)
    ratio = e.DEFAULT_RS_RSO
    per_day = defaultdict(lambda: [0, 0.0, 0.0, 0.0, 0.0, 0, 0.0])
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
        if not (9 <= hour_end.hour <= 18):
            continue
        ok = [x for x in hh if x["measured"] and x["le"] is not None and x["le_measured"] and None not in (x["rn"], x["h"])]
        if len(ok) != len(hh) or len(hh) != 2:
            continue
        t = sum(x["ta"] for x in hh) / 2
        vpd = sum(x["vpd"] for x in hh) / 2
        if wind is None:
            u2 = e.wind_2m(sum(x["ws"] for x in hh) / 2, meta["wind_h"])
        else:
            other = [wind.get(x["end"]) for x in hh]
            if None in other:
                continue
            u2 = sum(e.wind_2m(ws, h) for ws, h in other) / 2
        pa = sum(x["pa"] for x in hh) / 2
        rs = max(sum(x["sw"] for x in hh) / 2, 0) * e.W_M2_HOUR_TO_MJ
        ea = max(e.es(t) - vpd / 10, 0.01)
        rn0 = e.net_radiation_hourly(rs, ratio, t, ea)
        et0 = e.et0_hourly(t, ea, u2, rn0, 0.1 * rn0, pa)
        day = per_day[hour_end.date()]
        day[0] += 2
        day[1] += sum(x["le"] for x in hh) * e.HH_MJ / e.LAMBDA
        day[2] += et0
        day[3] += sum(x["rn"] - (x["g"] or 0.0) for x in hh) * e.HH_MJ
        day[4] += sum(x["h"] + x["le"] for x in hh) * e.HH_MJ
        day[5] += 1
        day[6] += sum(x["rn"] - (x["g"] if x["g"] is not None else 0.1 * x["rn"]) for x in hh) * e.HH_MJ
    return {d: v for d, v in per_day.items() if v[0] >= 16}


def corn_extras(site):
    """Per day from the BASE file: mean soil moisture over the sensors (%), rain (mm, US-CC2 only),
    and the midday (11–14) means of CO2 flux (µmol m⁻² s⁻¹, negative is uptake) and NDVI."""
    path = glob.glob(os.path.join(ROOT, site, "*_BASE_HH_*.csv"))[0]
    days = defaultdict(lambda: defaultdict(list))
    with open(path) as f:
        f.readline(), f.readline()
        for r in csv.DictReader(f):
            end = datetime.strptime(r["TIMESTAMP_END"], "%Y%m%d%H%M")
            day = days[(end - timedelta(minutes=1)).date()]
            swc = [v for v in (e.num(r, k) for k in r if k.startswith("SWC_")) if v is not None]
            if swc:
                day["swc"].append(sum(swc) / len(swc))
            if e.num(r, "P") is not None:
                day["p"].append(e.num(r, "P"))
            if 11 <= end.hour <= 14:
                for k in ("FC", "NDVI"):
                    if e.num(r, k) is not None:
                        day[k].append(e.num(r, k))

    def mean(xs):
        return sum(xs) / len(xs) if xs else None
    return {d: dict(swc=mean(v["swc"]), p=sum(v["p"]) if v["p"] else None, fc=mean(v["FC"]), ndvi=mean(v["NDVI"]))
            for d, v in days.items()}


def in_window(site, day):
    first, last = WINDOWS[site]
    return first <= day.strftime("%m-%d") <= last


def summary(days):
    et, et0, avail, turb, avail_g = (sum(d[i] for d in days) for i in (1, 2, 3, 4, 6))
    return len(days), et / et0, turb / avail, turb / avail_g


def fmt(v, places=2):
    return "–" if v is None else f"{v:.{places}f}"


def main():
    sites = [s for s in WINDOWS if os.path.isdir(os.path.join(ROOT, s))]
    # each site's ET0 on the wind it's run on (WIND_FROM's tower for corn), and the corn towers' own
    runs = {(s, "own" if s not in WIND_FROM else WIND_FROM[s]): daytime(s, other_wind(s) if s in WIND_FROM else None) for s in sites}
    runs.update({(s, "own"): daytime(s) for s in sites if s in WIND_FROM})
    extras = {s: corn_extras(s) for s in CORN if s in sites}

    for site in extras:
        main_run, own = runs[(site, WIND_FROM[site])], runs[(site, "own")]
        print(f"\n{site}, each day with a daytime ratio (* in the window)\n")
        print(f"| Day | Daytime ET / ET0 | On its own wind | Closure | Soil moisture % | Rain mm | Midday CO2 flux | Midday NDVI |")
        print("|---|---|---|---|---|---|---|---|")
        for day in sorted(set(main_run) | set(own)):
            d, o, x = main_run.get(day), own.get(day), extras[site].get(day, {})
            mark = " *" if in_window(site, day) else ""
            closure = (d or o)[4] / (d or o)[3]
            print(f"| {day:%b %d}{mark} | {fmt(d and d[1] / d[2])} | {fmt(o and o[1] / o[2])} | {closure:.2f} | {fmt(x.get('swc'), 1)} | {fmt(x.get('p'), 1)} | {fmt(x.get('fc'), 0)} | {fmt(x.get('ndvi'))} |")

    print("\n| Site | Crop | Window | Wind | Soil | Days | Daytime ET / ET0 | Daytime closure | Corrected | Closure, G = 0.1 Rn where unmeasured | Corrected |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for (site, wind), per_day in runs.items():
        window = {d: v for d, v in per_day.items() if in_window(site, d)}
        groups = [("", list(window.values()))]
        if site in extras:
            swc = lambda d: extras[site].get(d, {}).get("swc")  # noqa: E731
            groups = [(f"moist (≥ {MOIST_SWC}%)", [v for d, v in window.items() if swc(d) is not None and swc(d) >= MOIST_SWC]),
                      ("dry", [v for d, v in window.items() if swc(d) is not None and swc(d) < MOIST_SWC])]
        for soil, days in groups:
            if not days:
                continue
            n, k, c, cg = summary(days)
            print(f"| {site} | {e.SITES[site]['crop']} | {' to '.join(WINDOWS[site])} | {wind} | {soil} | {n} | {k:.2f} | {c:.2f} | {k / c:.2f} | {cg:.2f} | {k / cg:.2f} |")


if __name__ == "__main__":
    main()
