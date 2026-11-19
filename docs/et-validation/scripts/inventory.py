# What each AmeriFlux site-year holds for the ET validation (docs/et-validation/02-data.md).
# Python 3, standard library only.
#
#   python3 -I docs/et-validation/scripts/inventory.py [DIR]
#
# DIR defaults to tmp/ameriflux (one folder per site, as unzipped from AmeriFlux; not committed).
# For May 1 to September 30 of each year: the share of half-hours with each variable measured
# (FLUXNET: QC 0; BASE: present), energy balance closure (H + LE) / (Rn - G) over half-hours with
# all four measured, and (H + LE) / Rn over days with all 48 half-hours of the three measured (for
# sites without G: G sums to near zero over a day), ONEFlux's correction (LE_CORR / LE_F_MDS) where offered, and the towers' ET.
import csv, glob, os, statistics as st, sys
from collections import defaultdict

ROOT = sys.argv[1] if len(sys.argv) > 1 else "tmp/ameriflux"
MISSING = -9999.0
LAMBDA = 2.45e6  # J/kg, latent heat of vaporization (FAO-56)
SECONDS = 1800

# FLUXNET column -> (value column, QC column or None); BASE files name them differently.
FLUXNET = {
    "TA": ("TA_F_MDS", "TA_F_MDS_QC"),
    "VPD": ("VPD_F_MDS", "VPD_F_MDS_QC"),
    "WS": ("WS", None),
    "SW_IN": ("SW_IN_F_MDS", "SW_IN_F_MDS_QC"),
    "PA": ("PA", None),
    "RN": ("NETRAD", None),
    "G": ("G_F_MDS", "G_F_MDS_QC"),
    "H": ("H_F_MDS", "H_F_MDS_QC"),
    "LE": ("LE_F_MDS", "LE_F_MDS_QC"),
    "P": ("P", None),
}
BASE = {
    "TA": ("TA", None),  # absent at US-CC1/CC2: derived from RH and VPD below
    "VPD": ("VPD_PI", None),
    "WS": ("WS", None),
    "SW_IN": ("SW_IN", None),
    "PA": ("PA", None),
    "RN": ("NETRAD", None),
    "G": ("G_1_1_1", None),
    "H": ("H", None),
    "LE": ("LE", None),
    "P": ("P", None),
}
VARS = list(FLUXNET)


def num(row, col):
    if col is None or col not in row:
        return None
    try:
        v = float(row[col])
    except ValueError:
        return None
    return None if v <= MISSING else v


def measured(row, spec):
    col, qc = spec
    v = num(row, col)
    if v is None:
        return None
    if qc is not None and num(row, qc) != 0:
        return None
    return v


def ta_from_rh_vpd(rh, vpd_hpa):
    # VPD = es(T) (1 - RH/100), so es = VPD / (1 - RH/100); invert FAO-56 eq. 11 (kPa, °C)
    if rh is None or vpd_hpa is None or rh >= 99.5:
        return None
    import math
    es = vpd_hpa / 10 / (1 - rh / 100)
    if es <= 0:
        return None
    x = math.log(es / 0.6108)
    return 237.3 * x / (17.27 - x)


def site_files(site_dir):
    hh = glob.glob(os.path.join(site_dir, "*_FLUXNET_FLUXMET_HH_*.csv"))
    if hh:
        return hh[0], FLUXNET, 0
    base = glob.glob(os.path.join(site_dir, "*_BASE_HH_*.csv"))
    if base:
        return base[0], BASE, 2  # BASE files have two comment lines
    return None, None, 0


def inventory(site_dir):
    path, spec, skip = site_files(site_dir)
    if not path:
        return []
    years = defaultdict(lambda: {"n": 0, "have": defaultdict(int), "avail": 0.0, "flux": 0.0,
                                 "corr": [], "et": defaultdict(float), "et_days": defaultdict(set),
                                 "day": defaultdict(lambda: [0, 0.0, 0.0])})
    with open(path, encoding="utf-8", errors="replace") as f:
        for _ in range(skip):
            f.readline()
        for row in csv.DictReader(f):
            t = row["TIMESTAMP_START"]
            month = int(t[4:6])
            if not 5 <= month <= 9:
                continue
            y = years[t[:4]]
            y["n"] += 1
            vals = {k: measured(row, spec[k]) for k in VARS}
            if spec is BASE and vals["TA"] is None:
                vals["TA"] = ta_from_rh_vpd(num(row, "RH"), vals["VPD"])
            for k, v in vals.items():
                if v is not None:
                    y["have"][k] += 1
            rn, g, h, le = vals["RN"], vals["G"], vals["H"], vals["LE"]
            if None not in (rn, g, h, le):
                y["avail"] += rn - g
                y["flux"] += h + le
            if None not in (rn, h, le):
                d = y["day"][t[:8]]
                d[0] += 1
                d[1] += rn
                d[2] += h + le
            if spec is FLUXNET:
                le_f, le_c = num(row, "LE_F_MDS"), num(row, "LE_CORR")
                if le_f is not None and le_c is not None and le_f > 50:
                    y["corr"].append(le_c / le_f)
                if 6 <= month <= 8 and le_f is not None:
                    y["et"]["gapfilled"] += le_f * SECONDS / LAMBDA
                    y["et_days"]["gapfilled"].add(t[:8])
                    if le_c is not None:
                        y["et"]["corrected"] += le_c * SECONDS / LAMBDA
                        y["et_days"]["corrected"].add(t[:8])
    out = []
    for year, y in sorted(years.items()):
        n = y["n"] or 1
        rec = {"year": year, "halfhours": y["n"]}
        rec.update({k: y["have"][k] / n for k in VARS})
        rec["closure"] = y["flux"] / y["avail"] if y["avail"] > 0 else None
        full = [d for d in y["day"].values() if d[0] == 48 and d[1] > 0]
        rec["closure_daily"] = sum(d[2] for d in full) / sum(d[1] for d in full) if full else None
        rec["full_days"] = len(full)
        rec["oneflux_corr"] = st.median(y["corr"]) if y["corr"] else None
        for kind in ("gapfilled", "corrected"):
            days = len(y["et_days"][kind])
            rec[f"et_{kind}"] = y["et"][kind] / days if days else None
        out.append(rec)
    return out


def pct(v):
    return "–" if v is None else f"{100 * v:.0f}"


def fmt(v, d=2):
    return "–" if v is None else f"{v:.{d}f}"


def main():
    print("| Site | Year | Half-hours | " + " | ".join(VARS) +
          " | Closure | Days complete | Closure, daily, no G | ONEFlux LE corr. | Jun–Aug ET mm/d (gap-filled) | (corrected) |")
    print("|" + "---|" * (len(VARS) + 9))
    for site_dir in sorted(glob.glob(os.path.join(ROOT, "US-*"))):
        site = os.path.basename(site_dir)
        for r in inventory(site_dir):
            cells = [site, r["year"], str(r["halfhours"])] + [pct(r[k]) for k in VARS]
            cells += [fmt(r["closure"]), str(r["full_days"]), fmt(r["closure_daily"]), fmt(r["oneflux_corr"]), fmt(r["et_gapfilled"]), fmt(r["et_corrected"])]
            print("| " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main()
