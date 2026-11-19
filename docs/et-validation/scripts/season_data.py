# Desai's group's crop dates, irrigation and canopy cover for the potato towers, from their two
# workbooks to tidy CSVs (docs/et-validation/02-data.md, "Crop dates, irrigation and canopy cover").
# Python 3, standard library only (an .xlsx is a zip of XML).
#
#   python3 -I docs/et-validation/scripts/season_data.py [DIR]
#
# DIR defaults to tmp/ameriflux/desai, which holds the workbooks as received (not committed: the
# data are the group's, unpublished) and gets the CSVs:
#
#   seasons.csv            per potato season, what the analysis uses: emergence and full cover
#                          (from canopy cover), vine kill, harvest, and where irrigation comes from
#   sites.csv              per tower: crop, position and the dates, as given
#   irrigation.csv         the pivot logs' entries above zero, as given
#   irrigation_daily.csv   per site and day, first entry to harvest: inches, 0 on a day with none
#   canopy_cover.csv       per site and day with a value, April to October: percent, as given
#
# The irrigation and canopy sheets have no site column; each year is that year's potato tower
# (one portable tower, moved each spring): 2018 US-CS1, 2019 US-CS3, 2020 US-CS4, 2021 US-CS5.
# Nothing is given for 2022 (US-CS6) or 2023 (US-CS8). What's kept and what isn't, and why, is in
# 02-data.md: the "planting" dates are the tower's installation, and 2019's irrigation sheet is a
# rain record, so neither is used.
import csv, os, re, sys, zipfile
import xml.etree.ElementTree as ET
from collections import defaultdict
from datetime import date, datetime, timedelta

DIR = sys.argv[1] if len(sys.argv) > 1 else "tmp/ameriflux/desai"
DATES = os.path.join(DIR, "US_CS_sites_dates_harvest.xlsx")
SEASON = os.path.join(DIR, "US_CS_sites_irrigation_canopy_cover.xlsx")

SITE_BY_YEAR = {2018: "US-CS1", 2019: "US-CS3", 2020: "US-CS4", 2021: "US-CS5"}
# The pivots' applications, by day (2021, 2018 to mid-July) or by start time (2020, 2018 after).
# 2019's sheet is hourly and follows the rain, not the pivot, so it's left out; that season's
# irrigation days come from the tower's gauge, as CS6's and CS8's do.
PIVOT_LOGS = ("US-CS1", "US-CS4", "US-CS5")

NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
REL = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"
EPOCH = datetime(1899, 12, 30)


# --- .xlsx ------------------------------------------------------------------------------------


def read_xlsx(path):
    """{sheet name: [row as a list of values]}; numbers stay numbers, dates stay serials."""
    with zipfile.ZipFile(path) as z:
        strings = []
        if "xl/sharedStrings.xml" in z.namelist():
            for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall("m:si", NS):
                strings.append("".join(t.text or "" for t in si.iter(f"{{{NS['m']}}}t")))
        rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
        targets = {r.get("Id"): r.get("Target") for r in rels}
        book = ET.fromstring(z.read("xl/workbook.xml"))
        sheets = {}
        for s in book.find("m:sheets", NS):
            target = targets[s.get(REL)].lstrip("/")
            target = target if target.startswith("xl/") else "xl/" + target
            sheets[s.get("name")] = parse_sheet(ET.fromstring(z.read(target)), strings)
        return sheets


def parse_sheet(root, strings):
    rows = []
    for row in root.iter(f"{{{NS['m']}}}row"):
        values = {}
        for c in row.findall("m:c", NS):
            col = column_index(re.match(r"[A-Z]+", c.get("r")).group())
            v = c.find("m:v", NS)
            kind = c.get("t")
            if kind == "inlineStr":
                values[col] = "".join(t.text or "" for t in c.iter(f"{{{NS['m']}}}t"))
            elif v is None:
                continue
            elif kind == "s":
                values[col] = strings[int(v.text)]
            elif kind in ("str", "e"):
                values[col] = v.text
            elif kind == "b":
                values[col] = v.text == "1"
            else:
                values[col] = float(v.text)
        width = max(values) + 1 if values else 0
        rows.append([values.get(i) for i in range(width)])
    return rows


def column_index(letters):
    n = 0
    for ch in letters:
        n = n * 26 + ord(ch) - 64
    return n - 1


def to_datetime(serial):
    # Rounded to the minute: Excel's serials carry float noise.
    return EPOCH + timedelta(minutes=round(serial * 1440))


def cell(row, i):
    return row[i] if i < len(row) else None


def as_date(v):
    return to_datetime(v).date() if isinstance(v, float) else None


def site_name(v):
    return v.strip().replace("_", "-") if isinstance(v, str) else None


# --- sites ------------------------------------------------------------------------------------


def sites(book):
    out = {}
    crop = None
    for row in book["lat_long info"][1:]:
        name = cell(row, 0)
        if isinstance(name, str) and name.lower().endswith("sites"):
            crop = "potato" if "potato" in name.lower() else "pine"
            continue
        if not isinstance(cell(row, 1), float):
            continue
        site = site_name(name)
        lat, lon = cell(row, 1), cell(row, 2)
        note = ""
        if lon > 0:  # US_CS7 is given as 89.544297 E: the sign dropped
            lon, note = -lon, "longitude given as east; sign corrected"
        if isinstance(cell(row, 5), str):
            note = "; ".join(x for x in (note, f"{as_date(cell(row, 4))}: {cell(row, 5)}") if x)
        out[site] = {"site": site, "crop": crop, "lat": lat, "lon": lon, "note": note}

    section = None
    for row in book["plantation_harvest dates"][1:]:
        name = cell(row, 0)
        if isinstance(name, str) and "collection dates" in name:
            section = "record"
            continue
        site = site_name(name)
        if site not in out:
            continue
        s = out[site]
        if section == "record":
            s["record_start"] = as_date(cell(row, 1))
            end = cell(row, 2)
            s["record_end"] = as_date(end) if isinstance(end, float) else end
        else:
            s["planting_given"] = as_date(cell(row, 1))
            for i in (1, 2, 3):
                s[f"vine_kill_{i}"] = as_date(cell(row, 1 + i))
            s["harvest"] = as_date(cell(row, 5))
    return out


# --- irrigation and canopy --------------------------------------------------------------------


def irrigation(book):
    rows = []
    for row in book["irrigation"][1:]:
        when, inches = cell(row, 0), cell(row, 1)
        if not isinstance(when, float) or not isinstance(inches, float) or inches <= 0:
            continue
        t = to_datetime(when)
        site = SITE_BY_YEAR[t.year]
        if site not in PIVOT_LOGS:
            continue
        rows.append({
            "site": site,
            "date": t.date(),
            "time": t.strftime("%H:%M") if (t.hour, t.minute) != (0, 0) else "",
            "irrigation_in": round(inches, 3),
        })
    return rows


def irrigation_daily(entries, site_info):
    by_day = defaultdict(float)
    for e in entries:
        by_day[(e["site"], e["date"])] += e["irrigation_in"]
    out = []
    for site in PIVOT_LOGS:
        days = [d for s, d in by_day if s == site]
        d, end = min(days), max([site_info[site]["harvest"], *days])
        while d <= end:
            out.append({"site": site, "date": d, "irrigation_in": round(by_day.get((site, d), 0.0), 3)})
            d += timedelta(days=1)
    return out


def canopy(book):
    out = []
    for row in book["canopy-cover"][1:]:
        when, pct = cell(row, 0), cell(row, 1)
        if not isinstance(when, float) or not isinstance(pct, float):
            continue
        d = to_datetime(when).date()
        if not 4 <= d.month <= 10:  # the winter rows are all 1, a placeholder
            continue
        out.append({"site": SITE_BY_YEAR[d.year], "date": d, "canopy_cover_pct": pct})
    return out


def seasons(site_info, cover):
    """Per potato season: emergence is the first day canopy cover rises above the 1% the sheet
    holds for bare ground; full cover the first and last days at 100%."""
    by_site = defaultdict(list)
    for r in cover:
        by_site[r["site"]].append((r["date"], r["canopy_cover_pct"]))
    out = []
    for site, s in site_info.items():
        if s["crop"] != "potato":
            continue
        days = sorted(by_site.get(site, []))
        full = [d for d, v in days if v >= 100]
        out.append({
            "site": site,
            "year": s["record_start"].year,
            "emergence": next((d for d, v in days if v > 1), None),
            "full_cover_start": full[0] if full else None,
            "full_cover_end": full[-1] if full else None,
            "vine_kill": s.get("vine_kill_1"),
            "harvest": s.get("harvest"),
            "canopy": canopy_basis(site, days),
            "irrigation": "pivot log" if site in PIVOT_LOGS else "tower rain gauge",
        })
    return out


def canopy_basis(site, days):
    if not days:
        return "none: full cover from the tower (ET/ET0, albedo)"
    if site in ("US-CS1", "US-CS3"):
        return "phases only (day-by-day values templated)"
    return "observed"


# --- output -----------------------------------------------------------------------------------


def write(name, fields, rows):
    path = os.path.join(DIR, name)
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({k: fmt(r.get(k)) for k in fields})
    print(f"{path}: {len(rows)} rows")


def fmt(v):
    if v is None:
        return ""
    if isinstance(v, date):
        return v.isoformat()
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v)


def main():
    info = sites(read_xlsx(DATES))
    book = read_xlsx(SEASON)
    entries = irrigation(book)

    cover = canopy(book)

    write(
        "seasons.csv",
        ["site", "year", "emergence", "full_cover_start", "full_cover_end", "vine_kill", "harvest",
         "canopy", "irrigation"],
        sorted(seasons(info, cover), key=lambda s: s["year"]),
    )
    write(
        "sites.csv",
        ["site", "crop", "lat", "lon", "record_start", "record_end", "planting_given",
         "vine_kill_1", "vine_kill_2", "vine_kill_3", "harvest", "note"],
        sorted(info.values(), key=lambda s: (s["crop"] != "potato", s["site"])),
    )
    write("irrigation.csv", ["site", "date", "time", "irrigation_in"], entries)
    write("irrigation_daily.csv", ["site", "date", "irrigation_in"], irrigation_daily(entries, info))
    write("canopy_cover.csv", ["site", "date", "canopy_cover_pct"], cover)


main()
