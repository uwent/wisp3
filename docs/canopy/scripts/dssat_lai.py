# Simulates LAI for field corn, sweet corn and potato in the Central Sands with DSSAT-CSM 4.8
# (CERES-Maize, CERES-Sweetcorn, SUBSTOR-Potato) and fits WISP's LAI curve form to it
# (docs/canopy/05-dssat.md).
#
#   python -I docs/canopy/scripts/dssat_lai.py WORKDIR
#
# Needs DSSATTools 3.0.2 (pip install DSSATTools==3.0.2 scipy; GPL-3, bundles the DSSAT binary) in
# a virtualenv outside the repository. WORKDIR holds hancock.json: Open-Meteo archive daily
# temperature_2m_max/min (°C), precipitation_sum (mm) and shortwave_radiation_sum (MJ/m²) for
# 44.12, -89.53, 2014-01-01..2025-12-31, timezone America/Chicago. Keep WORKDIR's path short
# (tmp/dssat): DSSAT truncates long paths in its config and then can't find the weather file.
# Set TMPDIR to it too, or DSSATTools links its data files into /tmp.
#
# Potential growth: water and nitrogen stress are off (a well-managed pivot), so the soil barely
# matters. Writes WORKDIR/dssat_lai.csv (daily LAI by run) and prints the tables for the note.
import csv, io, json, os, sys, warnings
from datetime import date, timedelta
warnings.filterwarnings("ignore")
import numpy as np
import pandas as pd
from scipy.optimize import curve_fit
from DSSATTools.crop import Maize, SweetCorn, Potato
from DSSATTools.weather import WeatherStation
from DSSATTools.soil import SoilProfile, SoilLayer
from DSSATTools.filex import Planting, Field, SimulationControls, SCGeneral, SCOptions, SCManagement
from DSSATTools.run import DSSAT

W = sys.argv[1]
YEARS = range(2014, 2026)
# Planting dates near the middle of Nocco et al. (2019) Table 1, Isherwood Farms: potato May 1–9,
# field corn May 10–16, sweet corn May 22–June 2 (and a later sowing, as growers stagger them).
# Populations and spacing are typical Wisconsin values.
RUNS = [
  # crop, class, cultivars, (month, day) plantings, Planting kwargs
  ("field_corn", Maize, ["PC0001", "PC0002", "PC0003"], [(5, 12)],
   dict(ppop=8.4, plrs=76, pldp=5)),
  ("sweet_corn", SweetCorn, ["SW0001", "SW0002", "SW0003"], [(5, 28), (6, 20)],
   dict(ppop=6.4, plrs=76, pldp=4)),
  ("potato", Potato, ["IB0003", "IB0005", "IB0011", "IB0012"], [(5, 5)],
   dict(ppop=4.4, plrs=91, pldp=10, plwt=1500, sprl=2)),
]

d = json.load(open(f"{W}/hancock.json"))["daily"]
weather = pd.DataFrame({"date": pd.to_datetime(d["time"]), "srad": d["shortwave_radiation_sum"],
  "tmax": d["temperature_2m_max"], "tmin": d["temperature_2m_min"], "rain": d["precipitation_sum"]})
# Plainfield-like loamy sand, WISP's Loamy Sand (field capacity 0.15, wilting point 0.06)
layers = [SoilLayer(slb=b, slll=0.06, sdul=0.15, ssat=0.38, srgf=r, sbdm=1.55, sloc=oc, slcl=6, slsi=10)
  for b, r, oc in [(15, 1.0, 1.0), (30, 0.8, 0.6), (60, 0.5, 0.3), (90, 0.2, 0.1), (120, 0.1, 0.1)]]
soil = SoilProfile(table=layers, name="WISP000001", salb=0.15, slu1=6, sldr=0.6, slro=60, slnf=1,
  slpf=1, soil_clasification="LS")

def summary_dates(text):
  lines = [l for l in text.splitlines() if l.strip()]
  head = next(i for i, l in enumerate(lines) if l.startswith("@"))
  cols, vals = lines[head].split()[1:], lines[head + 1].split()  # "@" heads the header only
  get = lambda k: vals[cols.index(k)]
  doy = lambda v: None if v == "-99" else date(int(v[:4]), 1, 1) + timedelta(int(v[4:]) - 1)
  return doy(get("EDAT")), doy(get("MDAT"))

rows = []
dssat = DSSAT(os.path.join(W, "run"))
for crop, klass, cultivars, plantings, kw in RUNS:
  for cul in cultivars:
    cultivar = klass(cul)
    name = str(cultivar["vrname"] if klass is not Potato else cultivar["var-name"]).strip()
    for (m, dd) in plantings:
      for y in YEARS:
        # The calendar year's weather; every crop matures before December
        wsta = WeatherStation(table=weather[(weather.date >= f"{y}-01-01") & (weather.date < f"{y + 1}-01-01")],
          lat=44.12, long=-89.53, insi="HANC", elev=333)
        field = Field(id_field="WISP0001", wsta=wsta, id_soil=soil)
        pdate = date(y, m, dd)
        sc = SimulationControls(general=SCGeneral(sdate=pdate - timedelta(7)),
          options=SCOptions(water="N", nitro="N"), management=SCManagement(irrig="N", ferti="N", harvs="M"))
        dssat.run_treatment(field=field, cultivar=cultivar, planting=Planting(pdate=pdate, ppoe=kw["ppop"], **kw),
          simulation_controls=sc, verbose=False)
        edate, mdate = summary_dates(dssat.output_files["Summary"])
        pg = dssat.output_tables["PlantGro"]
        for day, lai in zip(pg.index.date, pg.LAID):
          rows.append(dict(crop=crop, cultivar=f"{cul} {name}", planting=pdate.isoformat(),
            emergence=edate.isoformat(), maturity=mdate and mdate.isoformat(), date=day.isoformat(),
            dae=(day - edate).days, lai=float(lai)))
dssat.close()

with open(f"{W}/dssat_lai.csv", "w", newline="") as f:
  w = csv.DictWriter(f, fieldnames=rows[0].keys()); w.writeheader(); w.writerows(rows)
df = pd.DataFrame(rows)

# WISP's curve form (CanopyModel): LAI = a · d^b · e^(−c·d), d = days since emergence
form = lambda t, a, b, c: a * np.power(t, b) * np.exp(-c * t)
wis = lambda t: form(t, 9e-12, 7.95, 0.1)

print("## Runs by cultivar (medians over seasons; days since emergence)\n")
print("| Crop | Cultivar | Planting | Emergence (days after planting) | Peak LAI | Peak day | LAI 1 / LAI 3 reached (day) | Maturity (day) |")
print("|---|---|---|---|---|---|---|---|")
for (crop, cul, pmd), g in df.assign(pmd=df.planting.str[5:]).groupby(["crop", "cultivar", "pmd"], sort=False):
  per = []
  for p, s in g.groupby("planting"):
    s = s[s.dae >= 0]
    pk = s.loc[s.lai.idxmax()]
    reach = lambda v: s[s.lai >= v].dae.min()
    e = s.emergence.iloc[0]; mt = s.maturity.iloc[0]
    per.append(dict(emerge=(date.fromisoformat(e) - date.fromisoformat(p)).days, peak=pk.lai, pday=pk.dae,
      l1=reach(1), l3=reach(3), mat=(date.fromisoformat(mt) - date.fromisoformat(e)).days if isinstance(mt, str) else np.nan))
  q = pd.DataFrame(per).median()
  print(f"| {crop} | {cul} | {pmd} | {q.emerge:.0f} | {q.peak:.2f} | {q.pday:.0f} | {q.l1:.0f} / {q.l3:.0f} | {q.mat:.0f} |")

print("\n## Fits of a · d^b · e^(−c·d) to the mean daily LAI over cultivars and seasons\n")
print("| Crop | Planting | a | b | c | Peak LAI (day) | RMSE | Season spread at the peak (p10–p90) |")
print("|---|---|---|---|---|---|---|---|")
fits = {}
for (crop, pmd), g in df.assign(pmd=df.planting.str[5:]).groupby(["crop", "pmd"], sort=False):
  g = g[(g.dae > 0) & (g.dae <= 140)]
  # Only up to each run's maturity; after it LAID is the dead canopy left standing
  g = g[g.maturity.isna() | (g.date <= g.maturity)]
  mean = g.groupby("dae").lai.mean()
  t, y = mean.index.values.astype(float), mean.values
  (a, b, c), _ = curve_fit(lambda t, la, b, c: form(t, np.exp(la), b, c), t, y, p0=(np.log(1e-8), 6, 0.08), maxfev=20000)
  a = np.exp(a)
  tt = np.arange(1, 141); fy = form(tt, a, b, c); pk = tt[fy.argmax()]
  rmse = float(np.sqrt(np.mean((form(t, a, b, c) - y) ** 2)))
  at_pk = g[g.dae == pk].lai
  fits[(crop, pmd)] = (a, b, c)
  print(f"| {crop} | {pmd} | {a:.3g} | {b:.3g} | {c:.3g} | {fy.max():.2f} ({pk}) | {rmse:.2f} | {at_pk.quantile(.1):.2f}–{at_pk.quantile(.9):.2f} |")

print("\n## Against the WIS field corn curve (CanopyModel)\n")
a, b, c = fits[("field_corn", "05-12")]
print("| Day since emergence | " + " | ".join(str(x) for x in range(10, 131, 10)) + " |")
print("|---|" + "---|" * 13)
print("| WIS v6.3.11 | " + " | ".join(f"{wis(x):.2f}" for x in range(10, 131, 10)) + " |")
print("| DSSAT fit | " + " | ".join(f"{form(x, a, b, c):.2f}" for x in range(10, 131, 10)) + " |")
fc = df[(df.crop == "field_corn") & (df.dae >= 0)].groupby("dae").lai.mean()
print("| DSSAT mean | " + " | ".join(f"{fc.get(x, float('nan')):.2f}" for x in range(10, 131, 10)) + " |")

# Timing check against the 2026 percent cover readings (docs/canopy/01-legacy-readings.md), with
# LAI converted to cover by DSSAT's own extinction coefficient for ET (KEP = 0.68 in the MZCER,
# SWCER and PTSUB species files): cover = 1 − e^(−0.68·LAI), so 50% is LAI 1.02 and 80% LAI 2.37.
K = 0.68
lai_at = lambda cover: -np.log(1 - cover) / K
OBSERVED = {"field_corn": (26, 40), "sweet_corn": (34, 46), "potato": (22, 32)}
print("\n## Days from emergence to 50% / 80% cover (cover = 1 − e^(−0.68·LAI))\n")
print("| Crop | 2026 readings (median) | DSSAT runs: median (p10–p90) | DSSAT fit | WIS curve |")
print("|---|---|---|---|---|")
first = lambda t, y, v: next((int(x) for x, z in zip(t, y) if z >= v), None)
tt = np.arange(0, 141)
for crop, (o50, o80) in OBSERVED.items():
  per = [(first(s.dae, s.lai, lai_at(.5)), first(s.dae, s.lai, lai_at(.8)))
    for _, s in df[(df.crop == crop) & (df.dae >= 0)].groupby(["cultivar", "planting"])]
  p = pd.DataFrame(per, columns=["d50", "d80"])
  cell = lambda c: f"{p[c].median():.0f} ({p[c].quantile(.1):.0f}–{p[c].quantile(.9):.0f})"
  fit = fits[next(k for k in fits if k[0] == crop)]
  fy = form(np.maximum(tt, 1), *fit)
  wc = f"{first(tt, wis(np.maximum(tt, 1)), lai_at(.5))} / {first(tt, wis(np.maximum(tt, 1)), lai_at(.8))}" if crop == "field_corn" else "–"
  print(f"| {crop} | {o50} / {o80} | {cell('d50')} / {cell('d80')} | {first(tt, fy, lai_at(.5))} / {first(tt, fy, lai_at(.8))} | {wc} |")

print("\n## Field corn: sensitivity to k\n")
print("| k | LAI at 50% / 80% | DSSAT runs | WIS curve | 2026 |")
print("|---|---|---|---|---|")
fc = df[(df.crop == "field_corn") & (df.dae >= 0)].groupby(["cultivar", "planting"])
for k in (0.5, 0.68, 0.85, 1.0, 1.5):
  l50, l80 = -np.log(.5) / k, -np.log(.2) / k
  p = pd.DataFrame([(first(s.dae, s.lai, l50), first(s.dae, s.lai, l80)) for _, s in fc]).median()
  w = wis(np.maximum(tt, 1))
  print(f"| {k} | {l50:.2f} / {l80:.2f} | {p[0]:.0f} / {p[1]:.0f} | {first(tt, w, l50)} / {first(tt, w, l80)} | 26 / 40 |")

# Through WISP's Kc = 1.1 × (1 − e^(−1.5·LAI)) (CropEt)
kc = lambda lai: 1.1 * (1 - np.exp(-1.5 * lai))
fit = fits[("field_corn", "05-12")]
print("\n## Field corn: Kc through CropEt\n")
print("| Day since emergence | 20 | 30 | 40 | 50 | 60 |\n|---|---|---|---|---|---|")
print("| Kc, WIS curve | " + " | ".join(f"{kc(wis(x)):.2f}" for x in range(20, 61, 10)) + " |")
print("| Kc, DSSAT fit | " + " | ".join(f"{kc(form(x, *fit)):.2f}" for x in range(20, 61, 10)) + " |")
early = sum(kc(form(x, *fit)) - kc(wis(x)) for x in range(1, 61))
late = sum(kc(form(x, *fit)) - kc(wis(x)) for x in range(100, 131))
print(f"\nKc-days more with DSSAT: days 1–60 {early:.1f} ({early * 0.18:.1f} in at 0.18 in/day), "
  f"days 100–130 {late:.1f} ({late * 0.15:.1f} in at 0.15 in/day)")
