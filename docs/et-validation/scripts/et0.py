# FAO-56 grass reference ET0 from each flux tower's own weather, beside the tower's measured ET, by
# day (docs/et-validation/02-data.md, 03-results.md). Python 3, standard library only.
#
#   python3 -I docs/et-validation/scripts/et0.py [DIR]      writes DIR/daily.csv
#   python3 -I docs/et-validation/scripts/et0.py --check    FAO-56 Rev.1 Example 4.3 (1998's Example 19)
#
# DIR defaults to tmp/ameriflux. ET0 is WISP's hourly chain (app/services/weather/fao56.rb, ported
# below function for function): FAO-56 Rev.1's eq. 2.5a/2.5b each hour (rs 50 s/m while Rn >= 0,
# 200 s/m while Rn < 0; until 2026-11-19 the 1998 eq. 53's 70 s/m, PLAN.md §9 C24), G = 0.1 Rn by
# day and 0.5 Rn at night, net
# longwave from Rs/Rso carried from the last hour with the sun above 17.2°. The towers' half-hours
# (local standard time, UTC−6) are averaged to hours. Wind is taken to 2 m by FAO-56 eq. 47 from the
# instrument's height; vapor pressure is e°(T) − VPD.
#
# Inputs use ONEFlux's filled columns (TA_F, VPD_F, SW_IN_F, WS_F, PA_F: measured, else MDS or ERA5)
# so every hour has a value; `inputs_measured` is the share of the day's half-hours with all five
# measured, and analyses keep days at 0.9 or more. BASE files (US-CC1, CC2) have no filling, no air
# temperature (taken from RH and VPD) and no pressure (from elevation); their hours need all inputs.
import csv, glob, math, os, sys
from collections import defaultdict
from datetime import datetime, timedelta

# --- FAO-56 (as Weather::Fao56) --------------------------------------------------------------

SOLAR_CONSTANT = 0.0820
SIGMA_HOURLY = 2.043e-10
ALBEDO_GRASS = 0.23
CLOUDINESS_MIN_ELEVATION_DEG = 17.2
RS_RSO_MIN = 0.3
DEFAULT_RS_RSO = 0.8
W_M2_HOUR_TO_MJ = 0.0036


def es(t):
    return 0.6108 * math.exp(17.27 * t / (t + 237.3))


def delta(t):
    return 4098 * es(t) / (t + 237.3) ** 2


def gamma(p):
    return 0.000665 * p


def pressure_at_elevation(z):
    return 101.3 * ((293 - 0.0065 * z) / 293) ** 5.26


def elevation_from_pressure(p):
    return (293 - 293 * (p / 101.3) ** (1 / 5.26)) / 0.0065


def wind_2m(u, z):
    return u * 4.87 / math.log(67.8 * z - 5.42)


def solar_terms(t_utc, lon):
    j = t_utc.timetuple().tm_yday
    decl = 0.409 * math.sin(2 * math.pi * j / 365 - 1.39)
    dr = 1 + 0.033 * math.cos(2 * math.pi * j / 365)
    b = 2 * math.pi * (j - 81) / 364
    sc = 0.1645 * math.sin(2 * b) - 0.1255 * math.cos(b) - 0.025 * math.sin(b)
    hours = t_utc.hour + t_utc.minute / 60 + t_utc.second / 3600
    solar_time = hours + lon / 15 + sc
    return decl, dr, math.pi / 12 * (solar_time % 24 - 12)


def solar_elevation(t_utc, lat, lon):
    decl, _, w = solar_terms(t_utc, lon)
    phi = math.radians(lat)
    s = math.sin(phi) * math.sin(decl) + math.cos(phi) * math.cos(decl) * math.cos(w)
    return math.degrees(math.asin(max(-1.0, min(1.0, s))))


def ra_hourly(hour_end_utc, lat, lon):
    decl, dr, w = solar_terms(hour_end_utc - timedelta(minutes=30), lon)
    phi = math.radians(lat)
    ws = math.acos(max(-1.0, min(1.0, -math.tan(phi) * math.tan(decl))))
    w1 = max(-ws, min(ws, w - math.pi / 24))
    w2 = max(-ws, min(ws, w + math.pi / 24))
    ra = 12 * 60 / math.pi * SOLAR_CONSTANT * dr * (
        (w2 - w1) * math.sin(phi) * math.sin(decl) + math.cos(phi) * math.cos(decl) * (math.sin(w2) - math.sin(w1)))
    return max(ra, 0.0)


def rnl_hourly(t, ea, ratio):
    return SIGMA_HOURLY * (t + 273.16) ** 4 * (0.34 - 0.14 * math.sqrt(ea)) * (1.35 * ratio - 0.35)


def net_radiation_hourly(rs_mj, ratio, t, ea):
    return (1 - ALBEDO_GRASS) * rs_mj - rnl_hourly(t, ea, ratio)


def et0_hourly(t, ea, u2, rn, g, p):
    d, gm = delta(t), gamma(p)
    num = 0.408 * d * (rn - g) + gm * 37 / (t + 273) * u2 * (es(t) - ea)
    resistance = 0.24 if rn >= 0 else 0.96  # Rev.1 Box 2.3: rs 50 s/m by day, 200 s/m at night
    return max(num / (d + gm * (1 + resistance * u2)), 0.0)


def check():
    lat, lon, z = 16 + 13 / 60, -(16 + 15 / 60), 8
    p = pressure_at_elevation(z)
    day_end, night_end = datetime(2026, 10, 1, 16), datetime(2026, 10, 1, 4)
    results = []
    ra = ra_hourly(day_end, lat, lon)
    ea = 0.52 * es(38)
    rso = (0.75 + 2e-5 * z) * ra
    rn = net_radiation_hourly(2.450, 2.450 / rso, 38, ea)
    et0 = et0_hourly(38, ea, 3.3, rn, 0.1 * rn, p)
    results += [("Ra day", ra, 3.543, 0.01), ("Rso", rso, 2.658, 0.01), ("Rn day", rn, 1.749, 0.005), ("ET0 day", et0, 0.656, 0.001)]
    ea = 0.90 * es(28)
    rn = net_radiation_hourly(0.0, 0.8, 28, ea)
    results += [("Ra night", ra_hourly(night_end, lat, lon), 0.0, 1e-9), ("Rn night", rn, -0.100, 0.002),
                ("ET0 night", et0_hourly(28, ea, 1.9, rn, 0.5 * rn, p), 0.004, 0.001),
                ("u2 from 1.0 at 10 m", wind_2m(1.0, 10), 0.748, 0.001)]
    ok = True
    for name, got, want, tol in results:
        good = abs(got - want) <= tol
        ok &= good
        print(f"{'ok ' if good else 'BAD'} {name}: {got:.4f} (FAO-56 Rev.1 {want})")
    return ok


# --- The towers ---------------------------------------------------------------------------------

UTC_OFFSET_H = -6
LAMBDA = 2.45  # MJ/kg
HH_MJ = 1800 / 1e6  # a half-hour's mean W/m² in MJ/m²
MISSING = -9999.0

# Instrument heights from each site's BIFVARINFO (wind); BASE sites have none recorded: 3 m assumed.
SITES = {
    "US-CS1": dict(crop="potato", lat=44.1031, lon=-89.5379, z=328, wind_h=2.5),
    "US-CS3": dict(crop="potato", lat=44.1394, lon=-89.5727, z=328, wind_h=2.5),
    "US-CS4": dict(crop="potato", lat=44.1597, lon=-89.5475, z=328, wind_h=2.5),
    "US-CS5": dict(crop="potato", lat=44.1095, lon=-89.5377, z=328, wind_h=3.0),
    "US-CS6": dict(crop="potato", lat=44.4297, lon=-89.5440, z=328, wind_h=3.0),
    "US-CS8": dict(crop="potato", lat=44.4338, lon=-89.5364, z=328, wind_h=3.0),
    "US-CC1": dict(crop="corn", lat=44.07, lon=-89.68, z=314, wind_h=3.0),
    "US-CC2": dict(crop="corn", lat=44.11, lon=-89.62, z=320, wind_h=3.0),
    "US-CS2": dict(crop="pine", lat=44.1467, lon=-89.5002, z=328, wind_h=None),
    "US-DFK": dict(crop="kernza", lat=43.3453, lon=-89.7154, z=210, wind_h=3.21),
}


def num(row, col):
    v = row.get(col)
    if v is None or v == "":
        return None
    v = float(v)
    return None if v <= MISSING else v


def read_halfhours(site_dir):
    """Yields dicts: end (local standard), ta, vpd (hPa), ws, sw, pa, measured (bool), rn, g, h, le,
    le_measured, le_corr, sw_out, lw_in, lw_out, p."""
    hh = glob.glob(os.path.join(site_dir, "*_FLUXNET_FLUXMET_HH_*.csv"))
    if hh:
        with open(hh[0]) as f:
            for r in csv.DictReader(f):
                measured = (num(r, "TA_F_MDS_QC") == 0 and num(r, "VPD_F_MDS_QC") == 0 and
                            num(r, "SW_IN_F_MDS_QC") == 0 and num(r, "WS") is not None and num(r, "PA") is not None)
                yield dict(end=datetime.strptime(r["TIMESTAMP_END"], "%Y%m%d%H%M"),
                           ta=num(r, "TA_F"), vpd=num(r, "VPD_F"), ws=num(r, "WS_F"), sw=num(r, "SW_IN_F"),
                           pa=num(r, "PA_F"), measured=measured, rn=num(r, "NETRAD"), g=num(r, "G_F_MDS"),
                           h=num(r, "H_F_MDS"), le=num(r, "LE_F_MDS"), le_measured=num(r, "LE_F_MDS_QC") == 0,
                           le_corr=num(r, "LE_CORR"), sw_out=num(r, "SW_OUT"), lw_in=num(r, "LW_IN_F_MDS") if num(r, "LW_IN_F_MDS_QC") == 0 else None,
                           lw_out=num(r, "LW_OUT"), p=num(r, "P"))
        return
    base = glob.glob(os.path.join(site_dir, "*_BASE_HH_*.csv"))
    if not base:
        return
    z = SITES[os.path.basename(site_dir)]["z"]
    with open(base[0]) as f:
        f.readline(), f.readline()
        for r in csv.DictReader(f):
            rh, vpd = num(r, "RH"), num(r, "VPD_PI")
            ta = None
            if rh is not None and vpd is not None and rh < 99.5:
                e_s = vpd / 10 / (1 - rh / 100)
                if e_s > 0:
                    x = math.log(e_s / 0.6108)
                    ta = 237.3 * x / (17.27 - x)
            ws, sw = num(r, "WS"), num(r, "SW_IN")
            measured = None not in (ta, vpd, ws, sw)
            le = num(r, "LE")
            yield dict(end=datetime.strptime(r["TIMESTAMP_END"], "%Y%m%d%H%M"), ta=ta, vpd=vpd, ws=ws, sw=sw,
                       pa=pressure_at_elevation(z), measured=measured, rn=num(r, "NETRAD"), g=num(r, "G_1_1_1"),
                       h=num(r, "H"), le=le, le_measured=le is not None, le_corr=None, sw_out=num(r, "SW_OUT"),
                       lw_in=num(r, "LW_IN"), lw_out=num(r, "LW_OUT"), p=num(r, "P"))


def mean(xs):
    xs = [x for x in xs if x is not None]
    return sum(xs) / len(xs) if xs else None


def site_days(site, site_dir):
    meta = SITES[site]
    lat, lon = meta["lat"], meta["lon"]
    hours = defaultdict(list)
    days = defaultdict(lambda: defaultdict(list))
    for hh in read_halfhours(site_dir):
        # the half-hour ending at :30 belongs to the hour ending at the next :00
        end = hh["end"]
        hour_end = end if end.minute == 0 else end + timedelta(minutes=30)
        hours[hour_end].append(hh)
        day = (end - timedelta(minutes=1)).date()  # the half-hour ending at midnight is the day before's
        days[day]["hh"].append(hh)
    # ET0 hour by hour, in time order so the cloudiness ratio carries
    ratio = DEFAULT_RS_RSO
    et0_by_day, rnl_by_day, hours_by_day = defaultdict(float), defaultdict(float), defaultdict(int)
    rso_by_day, ea_by_day, rh_by_day, u2_by_day = defaultdict(float), defaultdict(list), defaultdict(list), defaultdict(list)
    for hour_end in sorted(hours):
        hh = hours[hour_end]
        t, vpd, ws, sw, pa = (mean([x[k] for x in hh]) for k in ("ta", "vpd", "ws", "sw", "pa"))
        utc_end = hour_end - timedelta(hours=UTC_OFFSET_H)
        ra = ra_hourly(utc_end, lat, lon)
        if None in (t, vpd, ws, sw, pa) or meta["wind_h"] is None:
            continue
        sw = max(sw, 0.0)
        rs = sw * W_M2_HOUR_TO_MJ
        rso = (0.75 + 2e-5 * elevation_from_pressure(pa)) * ra
        if rso > 0 and solar_elevation(utc_end - timedelta(minutes=30), lat, lon) > CLOUDINESS_MIN_ELEVATION_DEG:
            ratio = max(RS_RSO_MIN, min(1.0, rs / rso))
        ea = max(es(t) - vpd / 10, 0.01)
        rn = net_radiation_hourly(rs, ratio, t, ea)
        g = (0.1 if ra > 0 else 0.5) * rn
        day = (hour_end - timedelta(minutes=1)).date()
        et0_by_day[day] += et0_hourly(t, ea, wind_2m(ws, meta["wind_h"]), rn, g, pa)
        rnl_by_day[day] += rnl_hourly(t, ea, ratio)
        hours_by_day[day] += 1
        rso_by_day[day] += rso
        ea_by_day[day].append(ea)
        rh_by_day[day].append(100 * min(ea / es(t), 1.0))
        u2_by_day[day].append(wind_2m(ws, meta["wind_h"]))
    out = []
    for day in sorted(days):
        hh = days[day]["hh"]
        n = len(hh)
        if n != 48:
            continue
        rec = {"site": site, "crop": meta["crop"], "date": day.isoformat(), "et0_hours": hours_by_day.get(day, 0)}
        rec["et0_mm"] = et0_by_day[day] if hours_by_day.get(day) == 24 else None
        rec["inputs_measured"] = sum(x["measured"] for x in hh) / n
        le = [x["le"] for x in hh]
        rec["le_measured"] = sum(x["le_measured"] for x in hh) / n
        rec["et_mm"] = sum(le) * HH_MJ / LAMBDA if None not in le else None
        corr = [x["le_corr"] for x in hh]
        rec["et_oneflux_corr_mm"] = sum(corr) * HH_MJ / LAMBDA if None not in corr else None
        for k in ("rn", "g", "h"):
            xs = [x[k] for x in hh]
            rec[f"{k}_mj"] = sum(xs) * HH_MJ if None not in xs else None
        rec["le_mj"] = sum(le) * HH_MJ if None not in le else None
        avail = None if rec["rn_mj"] is None else rec["rn_mj"] - (rec["g_mj"] or 0.0)
        rec["g_measured"] = rec["g_mj"] is not None
        turb = None if None in (rec["h_mj"], rec["le_mj"]) else rec["h_mj"] + rec["le_mj"]
        rec["closure"] = turb / avail if turb is not None and avail and avail > 1 else None
        # albedo from midday hours (10–14 LST), with the sun well up
        mid = [x for x in hh if 10 <= x["end"].hour <= 14 and x["sw"] and x["sw"] > 200 and x["sw_out"] is not None]
        rec["albedo_midday"] = sum(x["sw_out"] for x in mid) / sum(x["sw"] for x in mid) if len(mid) >= 6 else None
        lw = [(x["lw_in"], x["lw_out"]) for x in hh]
        rec["lw_net_loss_mj"] = sum(o - i for i, o in lw) * HH_MJ if all(i is not None and o is not None for i, o in lw) else None
        full = hours_by_day.get(day) == 24
        rec["rnl_fao_mj"] = rnl_by_day[day] if full else None
        rec["rso_mj"] = rso_by_day[day] if full else None
        rec["ea_mean_kpa"] = mean(ea_by_day[day]) if full else None
        rec["rh_min_pct"] = min(rh_by_day[day]) if full else None
        rec["u2_mean_m_s"] = mean(u2_by_day[day]) if full else None
        ps = [x["p"] for x in hh]
        rec["p_mm"] = sum(ps) if None not in ps else None
        rec["ta_mean_c"] = mean([x["ta"] for x in hh])
        rec["vpd_max_hpa"] = max((x["vpd"] for x in hh if x["vpd"] is not None), default=None)
        rec["ws_mean_m_s"] = mean([x["ws"] for x in hh])
        rec["sw_in_mj"] = sum(max(x["sw"], 0) for x in hh if x["sw"] is not None) * HH_MJ
        out.append(rec)
    return out


COLUMNS = ["site", "crop", "date", "et0_mm", "et0_hours", "inputs_measured", "et_mm", "le_measured", "et_oneflux_corr_mm",
           "rn_mj", "g_mj", "g_measured", "h_mj", "le_mj", "closure", "albedo_midday", "lw_net_loss_mj", "rnl_fao_mj",
           "p_mm", "ta_mean_c", "vpd_max_hpa", "ws_mean_m_s", "sw_in_mj", "rso_mj", "ea_mean_kpa", "rh_min_pct",
           "u2_mean_m_s"]


def main():
    if "--check" in sys.argv:
        sys.exit(0 if check() else 1)
    if not check():
        sys.exit("FAO-56 check failed")
    root = next((a for a in sys.argv[1:] if not a.startswith("-")), "tmp/ameriflux")
    rows = []
    for site in SITES:
        d = os.path.join(root, site)
        if os.path.isdir(d):
            got = site_days(site, d)
            print(f"{site}: {len(got)} days, {sum(1 for r in got if r['et0_mm'] is not None and r['inputs_measured'] >= 0.9)} with measured ET0 inputs", file=sys.stderr)
            rows += got
    path = os.path.join(root, "daily.csv")
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=COLUMNS)
        w.writeheader()
        for r in rows:
            w.writerow({k: (f"{v:.4f}" if isinstance(v, float) else v) for k, v in r.items()})
    print(f"wrote {path}", file=sys.stderr)


if __name__ == "__main__":
    main()
