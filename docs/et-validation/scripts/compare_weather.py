# WISP 3's own weather against the towers (docs/et-validation/04-weather.md). Python 3, standard
# library only.
#
#   python3 -I docs/et-validation/scripts/compare_weather.py [DIR]
#
# Reads DIR/daily.csv (et0.py) and DIR/wisp_weather.csv (weather_at_towers.rb); DIR defaults to
# tmp/ameriflux. Part 1: reference ET from WISP's corrected Open-Meteo weather, Open-Meteo's own
# ET0, and AgWeather's ET, against FAO-56 ET0 from each tower's instruments, by month (April–
# September, days with the tower's inputs measured). Part 2: crop ET at full cover (July, the days
# compare.py keeps) from each weather source against the towers' measured ET, as recorded and
# closure-corrected.
import csv, math, os, statistics as st, sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "tmp/ameriflux"
SITES = ["US-CS1", "US-CS3", "US-CS4", "US-CS5", "US-CS6", "US-CS8"]
KC_MID, HEIGHT_M = 1.15, 0.6


def f(r, k):
    v = r.get(k) if r else None
    return float(v) if v not in (None, "") else None


def kc_mid(wind_mph_10m, rh_min):
    u2 = wind_mph_10m * 0.44704 * 4.87 / math.log(67.8 * 10 - 5.42)
    u2 = min(max(u2, 1.0), 6.0)
    rh_min = min(max(rh_min, 20.0), 80.0)
    return KC_MID + (0.04 * (u2 - 2.0) - 0.004 * (rh_min - 45.0)) * (HEIGHT_M / 3) ** 0.3


tower = {(r["site"], r["date"]): r for r in csv.DictReader(open(os.path.join(ROOT, "daily.csv")))}
wisp = {(r["site"], r["date"]): r for r in csv.DictReader(open(os.path.join(ROOT, "wisp_weather.csv")))}

SOURCES = [("WISP 3 (corrected, FAO-56)", "et0_wisp_mm"), ("Open-Meteo's own ET0", "et0_openmeteo_mm"),
           ("AgWeather classic", "agweather_classic_mm"), ("AgWeather adjusted", "agweather_adjusted_mm")]


def stats(pairs):
    x = [p[0] for p in pairs]
    y = [p[1] for p in pairs]
    ratio = sum(y) / sum(x)
    mae = sum(abs(b - a) for a, b in pairs) / len(pairs)
    r = st.correlation(x, y) if len(pairs) > 2 else float("nan")
    return ratio, mae, r


def usable(t):
    return t and f(t, "et0_mm") is not None and f(t, "inputs_measured") >= 0.9


print("## Reference ET against the towers' FAO-56 ET0\n")
print("Ratio of each source's season total to the tower's (days with both), MAE mm/day, r.\n")
print("| Source | Days | Tower ET0 mm/d | Ratio | MAE | r | Apr | May | Jun | Jul | Aug | Sep |")
print("|---|---|---|---|---|---|---|---|---|---|---|---|")
for label, col in SOURCES:
    pairs, by_month = [], {}
    for key, w in wisp.items():
        t = tower.get(key)
        v = f(w, col)
        if not usable(t) or v is None:
            continue
        pairs.append((f(t, "et0_mm"), v))
        by_month.setdefault(key[1][5:7], []).append((f(t, "et0_mm"), v))
    ratio, mae, r = stats(pairs)
    months = [f"{sum(p[1] for p in by_month[m]) / sum(p[0] for p in by_month[m]):.2f}" if m in by_month else "–" for m in ("04", "05", "06", "07", "08", "09")]
    print(f"| {label} | {len(pairs)} | {sum(p[0] for p in pairs) / len(pairs):.2f} | {ratio:.2f} | {mae:.2f} | {r:.2f} | " + " | ".join(months) + " |")

print("\nBy site, WISP 3 against the tower (ratio, all months):\n")
print("| Site | Days | Ratio | MAE | r |")
print("|---|---|---|---|---|")
for site in SITES:
    pairs = [(f(tower[k], "et0_mm"), f(w, "et0_wisp_mm")) for k, w in wisp.items()
             if k[0] == site and usable(tower.get(k)) and f(w, "et0_wisp_mm") is not None]
    if pairs:
        ratio, mae, r = stats(pairs)
        print(f"| {site} | {len(pairs)} | {ratio:.2f} | {mae:.2f} | {r:.2f} |")

print("\n## Crop ET at full cover (July) against measured ET\n")
print("| Site | Days | Measured mm/d | Closure | WISP 3, tower weather | WISP 3, its own weather | AgWeather classic | AgWeather adjusted |")
print("|---|---|---|---|---|---|---|---|")
tot = {k: 0.0 for k in ("meas", "corr", "tw", "ww", "cl", "ad")}
n_all = 0
for site in SITES:
    rows = []
    for key, t in tower.items():
        if key[0] != site or key[1][5:7] != "07":
            continue
        w = wisp.get(key)
        et0, et = f(t, "et0_mm"), f(t, "et_mm")
        if et0 is None or et is None or f(t, "inputs_measured") < 0.9 or f(t, "le_measured") < 0.4 or et0 < 1:
            continue
        if w is None or None in (f(w, "et0_wisp_mm"), f(w, "wind_mph"), f(w, "rh_min_pct"), f(w, "agweather_classic_mm"), f(w, "agweather_adjusted_mm")):
            continue
        rows.append((t, w))
    if not rows:
        continue
    eb = [t for t, _ in rows if None not in (f(t, "rn_mj"), f(t, "h_mj"), f(t, "le_mj"))]
    closure = sum(f(t, "h_mj") + f(t, "le_mj") for t in eb) / sum(f(t, "rn_mj") - (f(t, "g_mj") or 0) for t in eb)
    meas = sum(f(t, "et_mm") for t, _ in rows)
    corr = meas / closure
    tw = sum(f(t, "et0_mm") * min(max(1.15 + (0.04 * (min(max(f(t, "u2_mean_m_s"), 1), 6) - 2) - 0.004 * (min(max(f(t, "rh_min_pct"), 20), 80) - 45)) * 0.2 ** 0.3, 0), 2) for t, _ in rows)
    ww = sum(f(w, "et0_wisp_mm") * kc_mid(f(w, "wind_mph"), f(w, "rh_min_pct")) for _, w in rows)
    cl = sum(f(w, "agweather_classic_mm") for _, w in rows)
    ad = sum(f(w, "agweather_adjusted_mm") for _, w in rows)
    n = len(rows)
    b = lambda m: f"{100 * (m / meas - 1):+.0f}% / {100 * (m / corr - 1):+.0f}%"
    print(f"| {site} | {n} | {meas / n:.2f} | {closure:.2f} | {b(tw)} | {b(ww)} | {b(cl)} | {b(ad)} |")
    for k, v in (("meas", meas), ("corr", corr), ("tw", tw), ("ww", ww), ("cl", cl), ("ad", ad)):
        tot[k] += v
    n_all += n
b = lambda m: f"{100 * (m / tot['meas'] - 1):+.0f}% / {100 * (m / tot['corr'] - 1):+.0f}%"
print(f"| **All** | {n_all} | {tot['meas'] / n_all:.2f} | {tot['meas'] / tot['corr']:.2f} | {b(tot['tw'])} | {b(tot['ww'])} | {b(tot['cl'])} | {b(tot['ad'])} |")
print("\nEach cell: bias against measured ET as recorded / closure-corrected.")
