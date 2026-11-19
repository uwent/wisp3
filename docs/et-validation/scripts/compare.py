# Modeled against measured ET at the Central Sands potato towers at full cover
# (docs/et-validation/03-results.md). Python 3, standard library only.
#
#   python3 -I docs/et-validation/scripts/compare.py [DIR] [--from MM-DD] [--to MM-DD] [--dry]
#
# Reads DIR/daily.csv from et0.py (DIR defaults to tmp/ameriflux). Days are kept when at least 90% of
# their half-hours have every ET0 input measured, at least 40% have LE measured (most of the day's
# light hours; the rest is ONEFlux's MDS gap filling), and ET0 is at least 1 mm. The window
# defaults to July 1–31, when WISP's potato canopy curve is at full cover for any emergence before
# about May 30; --dry also drops days with rain or irrigation (P > 0.5 mm) that day or the day before.
#
# For each site and the window it reports:
# - the measured ET over FAO-56 ET0 (the crop coefficient the tower shows), as measured and with
#   the window's energy balance closure, C = Σ(H + LE) / Σ(Rn − G), divided out (Bowen ratio kept);
#   G is measured at US-CS5, CS6 and CS8 and taken as 0 over a day elsewhere;
# - WISP 3's crop ET: ET0 × potato's Kc mid 1.15 adjusted each day for wind and minimum RH (FAO-56
#   eq. 62, as CropEt.kc_mid, height 0.6 m);
# - legacy WISP's (AgWeather's) Priestley-Taylor, classic and adjusted (Talib et al. 2024), from the
#   same tower weather, ported from ../ag-weather EvapotranspirationCalculator (full cover: PET);
# and each model's bias against measured ET, uncorrected and closure-corrected.
import csv, math, os, sys
from datetime import date, timedelta

KC_MID, HEIGHT_M = 1.15, 0.6

# --- Legacy WISP (AgWeather v1) ---------------------------------------------------------------

SOLAR_CONSTANT_W = 1367.0
STEFAN_MJ_PER_DAY = 0.0864 * 0.0000000567
SFCEMISS, ALBEDO = 0.96, 0.25


def declin(doy):
    return 0.41 * math.cos(2 * math.pi * (doy - 172.0) / 365.0)


def sunrise_angle(doy, lat):
    return math.acos(-1 * math.tan(declin(doy)) * math.tan(math.radians(lat)))


def day_hours(doy, lat):
    return 24 - 2 * (12 - (12 / math.pi) * sunrise_angle(doy, lat))


def to_clr(doy, lat):
    av_eir = SOLAR_CONSTANT_W * (1 + 0.035 * math.cos(2 * math.pi * doy / 365.0))
    to_eir = (0.0864 / math.pi) * av_eir * (
        sunrise_angle(doy, lat) * math.sin(declin(doy)) * math.sin(math.radians(lat)) +
        math.cos(declin(doy)) * math.cos(math.radians(lat)) * math.sin(sunrise_angle(doy, lat)))
    dh = day_hours(doy, lat)
    return to_eir * (-0.7 + 0.86 * dh) / dh


def legacy_lwnet(t, ea, insol, doy, lat, a1, a2):
    if ea > 0.5:
        sky = a1 + a2 * ea * math.exp(1500 / (273 + t))
    else:
        sky = 1 - 0.261 * math.exp(-0.000777 * t ** 2)
    angstrom = 1.0 - sky / SFCEMISS
    lwu = SFCEMISS * STEFAN_MJ_PER_DAY * (273.15 + t) ** 4
    return angstrom * lwu * min(insol / to_clr(doy, lat), 1.0)


def legacy_et_mm(t, ea, insol, doy, lat, adjusted=False):
    a1, a2 = (0.544, 6.4e-4) if adjusted else (0.7, 5.95e-4)
    rn = (1.0 - ALBEDO) * insol - legacy_lwnet(t, ea, insol, doy, lat, a1, a2)
    sfactor = 0.398 + 0.0171 * t - 0.000142 * t ** 2
    inches = max(1.26 * sfactor * rn / 62.3, 0)
    return inches * 25.4


# --- WISP 3 -----------------------------------------------------------------------------------


def kc_mid(u2, rh_min):
    u2 = min(max(u2, 1.0), 6.0)
    rh_min = min(max(rh_min, 20.0), 80.0)
    return KC_MID + (0.04 * (u2 - 2.0) - 0.004 * (rh_min - 45.0)) * (HEIGHT_M / 3) ** 0.3


# --- Comparison -------------------------------------------------------------------------------

LAT = {"US-CS1": 44.1031, "US-CS3": 44.1394, "US-CS4": 44.1597, "US-CS5": 44.1095, "US-CS6": 44.4297, "US-CS8": 44.4338}


def f(r, k):
    v = r.get(k)
    return float(v) if v not in (None, "") else None


def args():
    a = sys.argv[1:]
    opts = {"dir": "tmp/ameriflux", "from": "07-01", "to": "07-31", "dry": False}
    i = 0
    while i < len(a):
        if a[i] in ("--from", "--to"):
            opts[a[i][2:]] = a[i + 1]
            i += 2
        elif a[i] == "--dry":
            opts["dry"] = True
            i += 1
        else:
            opts["dir"] = a[i]
            i += 1
    return opts


def main():
    o = args()
    rows = list(csv.DictReader(open(os.path.join(o["dir"], "daily.csv"))))
    by_key = {(r["site"], r["date"]): r for r in rows}
    print(f"Window {o['from']} to {o['to']}{', dry days only' if o['dry'] else ''}.\n")
    print("| Site | Season | Days | ET0 mm/d | Measured mm/d | Closure | Measured/ET0 | Closure-corrected/ET0 | WISP 3 Kc | "
          "WISP 3 bias | Classic PT bias | Adjusted PT bias | WISP 3 bias, corrected | Classic, corrected | Adjusted, corrected |")
    print("|" + "---|" * 15)
    totals = []
    lw_rows = []
    for site, lat in LAT.items():
        seasons = sorted({r["date"][:4] for r in rows if r["site"] == site})
        for year in seasons:
            d0 = date.fromisoformat(f"{year}-{o['from']}")
            d1 = date.fromisoformat(f"{year}-{o['to']}")
            days = []
            d = d0
            while d <= d1:
                r = by_key.get((site, d.isoformat()))
                d += timedelta(days=1)
                if r is None:
                    continue
                et0, et = f(r, "et0_mm"), f(r, "et_mm")
                if et0 is None or et is None or f(r, "inputs_measured") < 0.9 or f(r, "le_measured") < 0.4 or et0 < 1:
                    continue
                if o["dry"]:
                    prev = by_key.get((site, (date.fromisoformat(r["date"]) - timedelta(days=1)).isoformat()))
                    if (f(r, "p_mm") or 0) > 0.5 or (prev and (f(prev, "p_mm") or 0) > 0.5):
                        continue
                days.append(r)
            if len(days) < 5:
                continue
            doy = lambda r: date.fromisoformat(r["date"]).timetuple().tm_yday
            et0 = sum(f(r, "et0_mm") for r in days)
            meas = sum(f(r, "et_mm") for r in days)
            wisp = sum(f(r, "et0_mm") * kc_mid(f(r, "u2_mean_m_s"), f(r, "rh_min_pct")) for r in days)
            classic = sum(legacy_et_mm(f(r, "ta_mean_c"), f(r, "ea_mean_kpa"), f(r, "sw_in_mj"), doy(r), lat) for r in days)
            adjusted = sum(legacy_et_mm(f(r, "ta_mean_c"), f(r, "ea_mean_kpa"), f(r, "sw_in_mj"), doy(r), lat, True) for r in days)
            eb = [r for r in days if None not in (f(r, "rn_mj"), f(r, "h_mj"), f(r, "le_mj"))]
            avail = sum(f(r, "rn_mj") - (f(r, "g_mj") or 0.0) for r in eb)
            closure = sum(f(r, "h_mj") + f(r, "le_mj") for r in eb) / avail if avail > 0 else None
            corr = meas / closure if closure else None
            n = len(days)
            kc_mean = wisp / et0
            bias = lambda model, ref: f"{100 * (model / ref - 1):+.0f}%" if ref else "–"
            print(f"| {site} | {year} | {n} | {et0 / n:.2f} | {meas / n:.2f} | {closure:.2f} | {meas / et0:.2f} | {corr / et0:.2f} | {kc_mean:.2f} | "
                  f"{bias(wisp, meas)} | {bias(classic, meas)} | {bias(adjusted, meas)} | {bias(wisp, corr)} | {bias(classic, corr)} | {bias(adjusted, corr)} |")
            totals.append((n, et0, meas, corr, wisp, classic, adjusted))
            # net longwave, all window days with the four radiometers
            for r in days:
                lw, rnl = f(r, "lw_net_loss_mj"), f(r, "rnl_fao_mj")
                if lw is None or rnl is None:
                    continue
                t, ea, insol = f(r, "ta_mean_c"), f(r, "ea_mean_kpa"), f(r, "sw_in_mj")
                lw_rows.append((site, lw, rnl, legacy_lwnet(t, ea, insol, doy(r), lat, 0.7, 5.95e-4),
                                legacy_lwnet(t, ea, insol, doy(r), lat, 0.544, 6.4e-4), insol / f(r, "rso_mj")))
    if totals:
        n = sum(t[0] for t in totals)
        et0, meas, corr, wisp, classic, adjusted = (sum(t[i] for t in totals) for i in range(1, 7))
        print(f"| **All** | | {n} | {et0 / n:.2f} | {meas / n:.2f} | {meas / corr:.2f} | {meas / et0:.2f} | {corr / et0:.2f} | {wisp / et0:.2f} | "
              f"{100 * (wisp / meas - 1):+.0f}% | {100 * (classic / meas - 1):+.0f}% | {100 * (adjusted / meas - 1):+.0f}% | "
              f"{100 * (wisp / corr - 1):+.0f}% | {100 * (classic / corr - 1):+.0f}% | {100 * (adjusted / corr - 1):+.0f}% |")
    if lw_rows:
        print("\nNet longwave loss, MJ/m² a day (measured: LW_OUT − LW_IN from the four-component radiometer):\n")
        print("| Site | Days | Measured | FAO-56 (eq. 39, hourly) | Legacy classic (Idso) | Legacy adjusted |")
        print("|---|---|---|---|---|---|")
        for site in LAT:
            xs = [x for x in lw_rows if x[0] == site]
            if xs:
                k = len(xs)
                print(f"| {site} | {k} | {sum(x[1] for x in xs) / k:.2f} | {sum(x[2] for x in xs) / k:.2f} | {sum(x[3] for x in xs) / k:.2f} | {sum(x[4] for x in xs) / k:.2f} |")
        clear = [x for x in lw_rows if x[5] >= 0.8]
        for label, xs in (("All days", lw_rows), ("Clear days (Rs/Rso ≥ 0.8)", clear)):
            if xs:
                k = len(xs)
                print(f"| {label} | {k} | {sum(x[1] for x in xs) / k:.2f} | {sum(x[2] for x in xs) / k:.2f} | {sum(x[3] for x in xs) / k:.2f} | {sum(x[4] for x in xs) / k:.2f} |")


if __name__ == "__main__":
    main()
