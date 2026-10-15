# Checks FAO AquaCrop default canopy curves against the 2026 legacy WISP percent cover readings
# (docs/canopy/02-published-curves.md). Python 3, standard library only.
#
#   python3 -I docs/canopy/scripts/aquacrop_check.py WORKDIR
#
# WORKDIR holds aq/crop_params.py (from github.com/aquacropos/aquacrop,
# aquacrop/entities/crops/crop_params.py; parsed as a literal, never run) and om/LAT_LON.json
# (Open-Meteo archive daily temperature_2m_max/min in °F, 2026-04-15..2026-10-10, for each rounded
# location). Readings come from tmp/legacy_wisp/legacy_canopy_output.csv (not committed; see
# legacy_canopy_export.rb). Run from the repository root.
import ast, csv, json, math, sys, statistics as st
from collections import defaultdict
from datetime import date, timedelta
S=sys.argv[1]
src=open(f"{S}/aq/crop_params.py").read()
CP=ast.literal_eval(ast.parse(src).body[0].value)
def cc_growth(p,t,cgc):
  cc0=p['PlantPop']*p['SeedSize']/1e8; ccx=p['CCx']
  cc=cc0*math.exp(cgc*t)
  if cc>ccx/2: cc=ccx-0.25*ccx*ccx/cc0*math.exp(-cgc*t)
  return min(max(cc,0),ccx)
def cc_decline(p,t,cdc):
  ccx=p['CCx']; return max(0,ccx*(1-0.05*(math.exp(t*cdc*3.33/(ccx+2.29))-1)))
def gdd_c(tx,tn,tb,tu):
  # Fahrenheit in → °C GDD (AquaCrop method 3-ish: clip both to [tb,tu])
  tx=(tx-32)/1.8; tn=(tn-32)/1.8
  tx=min(max(tx,tb),tu); tn=min(max(tn,tb),tu); return (tx+tn)/2-tb
rows=list(csv.DictReader(open('tmp/legacy_wisp/legacy_canopy_output.csv')))
P=defaultdict(list)
for r in rows: P[r['planting']].append(r)
def cross(pts,t):
  for (d0,c0),(d1,c1) in zip(pts,pts[1:]):
    if c0<t<=c1: return d0+(t-c0)*(d1-d0)/(c1-c0)
seen=set(); series=defaultdict(list)
for p in P.values():
  r0=p[0]
  if r0['default_emergence']=='true': continue
  e=date.fromisoformat(r0['emergence_date'])
  pts=sorted(((date.fromisoformat(r['date'])-e).days, float(r['pct_cover'])) for r in p)
  sig=(r0['crop'],r0['emergence_date'],r0['lat'],r0['lon'],tuple(c for d,c in pts[:5]))
  if sig in seen or len([1 for d,c in pts if c<80])<3: continue
  seen.add(sig); series[r0['crop']].append((e,r0['lat'],r0['lon'],pts))
W={}
def temps(la,lo):
  if (la,lo) not in W:
    d=json.load(open(f"{S}/om/{la}_{lo}.json"))['daily']
    W[(la,lo)]={date.fromisoformat(t):(a,b) for t,a,b in zip(d['time'],d['temperature_2m_max'],d['temperature_2m_min'])}
  return W[(la,lo)]
def model_days(p,cal,thr,e=None,la=None,lo=None):
  # days since emergence for the curve to reach thr (fraction)
  for d in range(0,200):
    if cal:
      t=d; cgc=p['CGC_CD']
    else:
      T=temps(la,lo); t=sum(gdd_c(*T[e+timedelta(i)],p['Tbase'],p['Tupp']) for i in range(d)); cgc=p['CGC']
    if cc_growth(p,t,cgc)>=thr: return d
  return None
MAP={'Potato':['Potato','PotatoGDD','PotatoLocalGDD'],'Field Corn':['Maize','MaizeGDD'],'Soybean':['Soybean','SoybeanGDD'],
     'Snap bean':['DryBean','DryBeanGDD'],'Sweet Corn':['Maize','MaizeGDD']}
for crop,names in MAP.items():
  obs50=[cross(s[3],50) for s in series[crop]]; obs80=[cross(s[3],80) for s in series[crop]]
  o50=[x for x in obs50 if x]; o80=[x for x in obs80 if x]
  print(f"\n{crop}: observed days to 50% {min(o50):.0f}-{max(o50):.0f} (median {st.median(o50):.0f}), to 80% {min(o80):.0f}-{max(o80):.0f} (median {st.median(o80):.0f})")
  for n in names:
    p=CP[n]; cal=p['CalendarType']==1
    cc0=p['PlantPop']*p['SeedSize']/1e8
    if cal:
      m50,m80=model_days(p,True,.5),model_days(p,True,.8)
      sen=p['SenescenceCD']-p['EmergenceCD']
      print(f"  {n:15} CC0 {cc0*100:.2f}% CCx {p['CCx']*100:.0f}% CGC {p['CGC_CD']}/day: 50% day {m50}, 80% day {m80}; decline from day {sen} (CDC {p['CDC_CD']}/day), maturity day {p['MaturityCD']-p['EmergenceCD']}")
    else:
      r50=[];r80=[];err=[]
      for (e,la,lo,pts),a,b in zip(series[crop],obs50,obs80):
        m50,m80=model_days(p,False,.5,e,la,lo),model_days(p,False,.8,e,la,lo)
        r50.append(m50); r80.append(m80)
        if a: err.append(m50-a)
        if b: err.append(m80-b)
      print(f"  {n:15} Tbase {p['Tbase']}°C CGC {p['CGC']}/°Cd: 50% days {min(r50)}-{max(r50)}, 80% days {min(r80)}-{max(r80)}; mean error {st.mean(err):+.1f} d, MAE {st.mean(abs(x) for x in err):.1f} d")
  if True:
    # calendar errors too
    for n in names:
      p=CP[n]
      if p['CalendarType']!=1: continue
      m50,m80=model_days(p,True,.5),model_days(p,True,.8)
      err=[m50-a for a in obs50 if a]+[m80-b for b in obs80 if b]
      print(f"  {n:15} calendar: mean error {st.mean(err):+.1f} d, MAE {st.mean(abs(x) for x in err):.1f} d")
