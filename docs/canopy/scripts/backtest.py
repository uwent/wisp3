# Backtests ways of combining percent cover readings with a crop's canopy curve (PLAN.md Phase 6.7,
# A.4; docs/canopy/04-backtest.md). Python 3, standard library only.
#
#   python3 -I docs/canopy/scripts/backtest.py [CSV]
#
# Note 04 compared the first six methods; note 06 adds fitting the curve (shift, stretch and height,
# each held toward the default) and a ratio that fades back to the curve after the last reading.
#
# CSV defaults to tmp/legacy_wisp/legacy_canopy_output.csv (not committed; see
# legacy_canopy_export.rb). Errors are in crop ET as a fraction of et0, through the A3600
# percent cover regressions (CropEt at et0 0.2 in), so misses above 80% cover cost nothing.
import csv, math, statistics as st, sys
from collections import defaultdict
from datetime import date

# CropEt.adjusted("pct_cover", 0.2, c) / 0.2 for c = 0..100
ET_RATIO = [0.05, 0.0676, 0.0853, 0.1029, 0.1206, 0.1382, 0.1558, 0.1735, 0.1911, 0.2087, 0.2264, 0.2419, 0.2574, 0.273, 0.2885, 0.304, 0.3195, 0.3351, 0.3506, 0.3661, 0.3817, 0.3963, 0.4109, 0.4255, 0.4401, 0.4547, 0.4693, 0.4839, 0.4985, 0.5131, 0.5277, 0.5416, 0.5555, 0.5694, 0.5833, 0.5972, 0.6112, 0.6251, 0.639, 0.6529, 0.6668, 0.6779, 0.689, 0.7001, 0.7112, 0.7223, 0.7334, 0.7445, 0.7556, 0.7667, 0.7778, 0.7883, 0.7988, 0.8092, 0.8197, 0.8302, 0.8406, 0.8511, 0.8615, 0.872, 0.8825, 0.8891, 0.8958, 0.9025, 0.9092, 0.9159, 0.9225, 0.9292, 0.9359, 0.9426, 0.9492, 0.9543, 0.9594, 0.9645, 0.9695, 0.9746, 0.9797, 0.9848, 0.9898, 0.9949, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]

def et_ratio(cover):
    c = min(max(cover, 0.0), 100.0)
    i = min(int(c), 99)
    return ET_RATIO[i] + (c - i) * (ET_RATIO[i + 1] - ET_RATIO[i])

def growth(cc0, ccx, cgc, t):
    if t < 0:
        return 0.0
    cc = cc0 * math.exp(cgc * t)
    if cc > ccx / 2:
        cc = ccx - 0.25 * ccx * ccx / cc0 * math.exp(-cgc * t)
    return min(cc, ccx)

def decline(ccx, cdc, t):
    return max(0.0, ccx * (1 - 0.05 * (math.exp(3.33 * cdc * t / (ccx + 2.29)) - 1)))

# Defaults from docs/canopy/03-crop-curves.md: (CC0, CCx, CGC /day, decline)
CURVES = {
    "Potato": (0.006, 0.92, 0.18896, ("rule", (7, 25), 42, 50.0)),
    "Field Corn": (0.0049, 0.96, 0.16312, ("aquacrop", 101, 0.11691)),
    "Soybean": (0.0165, 0.98, 0.087, ("aquacrop", 95, 0.02885)),
    "Snap bean": (0.0132, 0.99, 0.11804, None),
    "Shell peas": (0.0453, 0.95, 0.088, None),
    "Sweet Corn": (0.0049, 0.96, 0.124, None),
}

def full_day(cc0, ccx, cgc):
    # CanopyCurve#full_day: days until 98% of ccx
    return math.ceil(math.log(ccx / (4 * (1 - 0.98) * cc0)) / cgc)

def curve(crop, emergence, t, shift=0.0, stretch=1.0, height=1.0):
    """Percent cover t days after emergence (CanopyCurve#cover). shift moves growth later (positive)
    or earlier, stretch slows it (> 1) or speeds it up, height scales the canopy. A calendar decline
    (potato's) keeps its date."""
    cc0, ccx, cgc, dec = CURVES[crop]
    tau = (t - shift) / stretch
    cover = growth(cc0, ccx, cgc, tau)
    if dec and dec[0] == "aquacrop" and tau > dec[1]:
        cover = min(cover, decline(ccx, dec[2], tau - dec[1]))
    if dec and dec[0] == "rule":
        start = max(date(emergence.year, *dec[1]).toordinal(),
                    emergence.toordinal() + shift + stretch * full_day(cc0, ccx, cgc))
        days = emergence.toordinal() + t - start
        if days > 0:
            x = min(days / dec[2], 1.0)
            cover = min(cover, ccx - (ccx - dec[3] / 100) * (3 * x ** 2 - 2 * x ** 3))
    return min(100.0, 100 * cover * height)

# Methods: each takes the known readings [(t, cover)] and returns a predictor t -> cover
def linear(crop, em, known):
    pts = [(0, 0.0)] + [p for p in known if p[0] > 0]
    def f(t):
        if t >= pts[-1][0]:
            return pts[-1][1]
        for (t0, c0), (t1, c1) in zip(pts, pts[1:]):
            if t0 <= t <= t1:
                return c0 + (c1 - c0) * (t - t0) / (t1 - t0)
    return f

def curve_only(crop, em, known):
    return lambda t: curve(crop, em, t)

def fit_scale(crop, em, known, shift=0.0):
    # least squares s for cover ≈ s · curve, in cover units
    num = sum(c * curve(crop, em, t, shift) for t, c in known)
    den = sum(curve(crop, em, t, shift) ** 2 for t, c in known)
    return num / den if den > 0 else 1.0

def sse(crop, em, known, shift, s):
    return sum((c - min(100, s * curve(crop, em, t, shift))) ** 2 for t, c in known)

def scaled(crop, em, known):
    s = fit_scale(crop, em, known)
    return lambda t: min(100.0, s * curve(crop, em, t))

SHIFTS = [x / 2 for x in range(-60, 61)]

def shifted(crop, em, known):
    d = min(SHIFTS, key=lambda d: sse(crop, em, known, d, 1.0))
    return lambda t: curve(crop, em, t, d)

def shift_scale(crop, em, known):
    if len(known) < 2:
        return shifted(crop, em, known)
    best = min(((sse(crop, em, known, d, fit_scale(crop, em, known, d)), d) for d in SHIFTS))
    d = best[1]
    s = fit_scale(crop, em, known, d)
    return lambda t: min(100.0, s * curve(crop, em, t, d))

def ratio(crop, em, known):
    # the curve times a ratio interpolated between readings (1 at emergence), held after the last
    pts = [(0, 1.0)] + [(t, c / max(curve(crop, em, t), 1.0)) for t, c in known if t > 0]
    def r(t):
        if t >= pts[-1][0]:
            return pts[-1][1]
        for (t0, r0), (t1, r1) in zip(pts, pts[1:]):
            if t0 <= t <= t1:
                return r0 + (r1 - r0) * (t - t0) / (t1 - t0)
    return lambda t: min(100.0, r(t) * curve(crop, em, t))

# Fitting (note 06): shift, stretch and height, each held toward the default by a penalty. A reading
# is worth (reading − curve)² / NOISE²; moving the curve costs (shift / SHIFT_SD)² and the same for
# log stretch and log height, so a lone reading barely moves it and many readings fit it closely.
# Readings of 80% or more count only as "at least 80" (growers stop there and hold, note 01).
# The search is CanopyFit's: shifts −15..15 days, stretch and height in steps of e^0.05 (stretch up to
# e^±0.3, height up to e^±0.2), on a coarse grid and then around its best.
PRIOR = {"noise": 10.0, "shift": 5.0, "stretch": 0.15, "height": 0.10}
MAX_SHIFT, STRETCH_STEPS, HEIGHT_STEPS, STEP = 15, 6, 4, 0.05
FADE_DAYS = 14
_fits = {}

def fit(crop, em, known, prior=PRIOR):
    """(shift, stretch, height) for the readings known"""
    key = (crop, em, tuple(known), tuple(prior.items()))
    if key not in _fits:
        costs = {}
        def cost(d, ks, kh):
            if (d, ks, kh) not in costs:
                k, h = math.exp(ks * STEP), math.exp(kh * STEP)
                misses = 0.0
                for t, c in known:
                    model = curve(crop, em, t, d, k, h)
                    miss = max(0.0, 80.0 - model) if c >= 80 else c - model
                    misses += (miss / prior["noise"]) ** 2
                costs[(d, ks, kh)] = (misses + (d / prior["shift"]) ** 2 + (ks * STEP / prior["stretch"]) ** 2
                                      + (kh * STEP / prior["height"]) ** 2)
            return costs[(d, ks, kh)]
        coarse = [(d, ks, kh) for d in range(-MAX_SHIFT, MAX_SHIFT + 1, 3)
                  for ks in range(-STRETCH_STEPS, STRETCH_STEPS + 1, 2) for kh in range(-HEIGHT_STEPS, HEIGHT_STEPS + 1, 2)]
        d0, ks0, kh0 = min(coarse, key=lambda c: cost(*c))
        fine = [(d, ks, kh) for d in range(max(d0 - 2, -MAX_SHIFT), min(d0 + 2, MAX_SHIFT) + 1)
                for ks in range(max(ks0 - 1, -STRETCH_STEPS), min(ks0 + 1, STRETCH_STEPS) + 1)
                for kh in range(max(kh0 - 1, -HEIGHT_STEPS), min(kh0 + 1, HEIGHT_STEPS) + 1)]
        d, ks, kh = min(fine, key=lambda c: cost(*c))
        _fits[key] = (d, math.exp(ks * STEP), math.exp(kh * STEP))
    return _fits[key]

def through(base, known, fade):
    """base times a ratio: reading ÷ base at each reading, 1 at emergence, linear between readings; after
    the last, held (fade None) or easing back to 1 over fade days"""
    pts = [(0, 1.0)] + [(t, c / max(base(t), 1.0)) for t, c in known if t > 0]
    def r(t):
        t_last, r_last = pts[-1]
        if t >= t_last:
            return r_last if fade is None else r_last + (1 - r_last) * min(1.0, (t - t_last) / fade)
        for (t0, r0), (t1, r1) in zip(pts, pts[1:]):
            if t0 <= t <= t1:
                return r0 + (r1 - r0) * (t - t0) / (t1 - t0)
    return lambda t: min(100.0, r(t) * base(t))

def fitted_curve(crop, em, known, prior=PRIOR):
    d, k, h = fit(crop, em, known, prior)
    return lambda t: curve(crop, em, t, d, k, h)

def ratio_fading(crop, em, known):
    return through(lambda t: curve(crop, em, t), known, FADE_DAYS)

def fitted_ratio_held(crop, em, known):
    return through(fitted_curve(crop, em, known), known, None)

def fitted_ratio_fading(crop, em, known, prior=PRIOR):
    return through(fitted_curve(crop, em, known, prior), known, FADE_DAYS)

METHODS = {"linear (now)": linear, "curve only": curve_only, "scaled": scaled, "shifted": shifted,
           "shift + scale": shift_scale, "ratio between readings": ratio,
           "ratio, fading": ratio_fading, "fitted curve": fitted_curve,
           "fitted + ratio held": fitted_ratio_held, "fitted + ratio fading": fitted_ratio_fading}

def load(path):
    rows = list(csv.DictReader(open(path)))
    plantings = defaultdict(list)
    for r in rows:
        plantings[r["planting"]].append(r)
    seen, series = set(), []
    for p in plantings.values():
        r0 = p[0]
        if r0["crop"] not in CURVES or r0["default_emergence"] == "true":
            continue
        em = date.fromisoformat(r0["emergence_date"])
        pts = sorted(((date.fromisoformat(r["date"]) - em).days, float(r["pct_cover"])) for r in p)
        sig = (r0["crop"], r0["emergence_date"], r0["lat"], r0["lon"], tuple(c for _, c in pts[:5]))
        if sig in seen or len([1 for _, c in pts if c < 80]) < 3:
            continue
        seen.add(sig)
        series.append((r0["crop"], em, pts))
    return series

def err(f, t, c):
    return abs(et_ratio(f(t)) - et_ratio(c)), abs(f(t) - c)

def main():
    series = load(sys.argv[1] if len(sys.argv) > 1 else "tmp/legacy_wisp/legacy_canopy_output.csv")
    print(f"{len(series)} series: " + ", ".join(f"{k} {v}" for k, v in sorted(defaultdict(int, {c: sum(1 for s in series if s[0] == c) for c, _, _ in series}).items())))
    for test in ("forward", "rest of season", "interpolate"):
        print(f"\n## {test}: mean |error| in ET/et0 (cover points), by crop and overall")
        crops = sorted({s[0] for s in series})
        print("| Method | " + " | ".join(crops) + " | All |")
        print("|---|" + "---|" * (len(crops) + 1))
        for name, method in METHODS.items():
            by_crop = defaultdict(list)
            for crop, em, pts in series:
                if test == "forward":
                    # with readings 1..k, predict reading k+1 (only while the canopy is developing)
                    for k in range(1, len(pts)):
                        if pts[k - 1][1] >= 80:
                            break
                        f = method(crop, em, pts[:k])
                        by_crop[crop].append(err(f, *pts[k]))
                elif test == "rest of season":
                    # with readings 1..k, predict every later reading (weeks ahead, where a held ratio lingers)
                    for k in range(1, len(pts)):
                        if pts[k - 1][1] >= 80:
                            break
                        f = method(crop, em, pts[:k])
                        by_crop[crop] += [err(f, t, c) for t, c in pts[k:]]
                else:
                    known, hidden = pts[0::2], pts[1::2]
                    f = method(crop, em, known)
                    by_crop[crop] += [err(f, t, c) for t, c in hidden]
            cells = [f"{st.mean(e for e, _ in by_crop[c]):.3f} ({st.mean(p for _, p in by_crop[c]):.0f})" for c in crops]
            everything = [x for c in crops for x in by_crop[c]]
            cells.append(f"**{st.mean(e for e, _ in everything):.3f}** ({st.mean(p for _, p in everything):.0f})")
            print(f"| {name} | " + " | ".join(cells) + " |")
    sparse(series)
    sensitivity(series)
    # Fitted scale and shift per series, with all its readings
    print("\n## Fitted scale (all readings) and shift per series")
    for crop, em, pts in series:
        growth_pts = [p for p in pts if p[1] < 80] or pts
        s = fit_scale(crop, em, growth_pts)
        d = min(SHIFTS, key=lambda d: sse(crop, em, growth_pts, d, 1.0))
        rms = math.sqrt(sse(crop, em, growth_pts, 0, s) / len(growth_pts))
        print(f"{crop:11} {em}  scale {s:.2f}  shift {d:+.1f} d  rms after scaling {rms:.0f} pts  ({len(growth_pts)} readings < 80%)")

def sparse(series):
    """With only the first n readings: how far the fit moves the curve, and the rest of the season's error"""
    print("\n## Sparse readings: the first n only")
    print("| Readings | Series | Mean |shift| (d) | Mean |stretch − 1| | Mean |height − 1| | Curve only | Ratio between readings | Fitted + ratio fading |")
    print("|---|---|---|---|---|---|---|---|")
    for n in (1, 2, 3, 5):
        rows = [(crop, em, pts) for crop, em, pts in series if len(pts) > n]
        moves = [fit(crop, em, pts[:n]) for crop, em, pts in rows]
        errors = {name: [] for name in ("curve only", "ratio between readings", "fitted + ratio fading")}
        for crop, em, pts in rows:
            for name in errors:
                f = METHODS[name](crop, em, pts[:n])
                errors[name] += [err(f, t, c)[0] for t, c in pts[n:]]
        print(f"| {n} | {len(rows)} | {st.mean(abs(d) for d, _, _ in moves):.1f} | {st.mean(abs(k - 1) for _, k, _ in moves):.2f} | "
              f"{st.mean(abs(h - 1) for _, _, h in moves):.2f} | " + " | ".join(f"{st.mean(e):.3f}" for e in errors.values()) + " |")

def sensitivity(series):
    """The proposed method with the prior held half or twice as tightly (forward and rest of season)"""
    print("\n## Prior strength: fitted + ratio fading, forward / rest of season")
    for label, scale in (("looser (2× SDs)", 2.0), ("as proposed", 1.0), ("tighter (½ SDs)", 0.5)):
        prior = {**PRIOR, **{k: v * scale for k, v in PRIOR.items() if k != "noise"}}
        fwd, rest = [], []
        for crop, em, pts in series:
            for k in range(1, len(pts)):
                if pts[k - 1][1] >= 80:
                    break
                f = fitted_ratio_fading(crop, em, pts[:k], prior)
                fwd.append(err(f, *pts[k])[0])
                rest += [err(f, t, c)[0] for t, c in pts[k:]]
        print(f"- {label}: {st.mean(fwd):.3f} / {st.mean(rest):.3f}")

if __name__ == "__main__":
    main()
