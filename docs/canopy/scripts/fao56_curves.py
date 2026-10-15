# Derives AquaCrop-form canopy curves from FAO-56 Table 11 stage lengths, for crops without an
# AquaCrop crop file (docs/canopy/03-crop-curves.md). Python 3, standard library only.
#
#   python3 -I docs/canopy/scripts/fao56_curves.py
#
# Days from emergence: t1 = Lini − gap (cover reaches 10%), t2 = Lini + Ldev − gap (effective full
# cover: 80%, or 95% of CCx where CCx < 84%). gap is planting to emergence (0 for transplants, whose
# Lini FAO-56 counts from transplanting). CC0 and CGC are solved so the AquaCrop growth curve
# passes both points.
import math

def growth(cc0, ccx, cgc, t):
    cc = cc0 * math.exp(cgc * t)
    if cc > ccx / 2:
        cc = ccx - 0.25 * ccx * ccx / cc0 * math.exp(-cgc * t)
    return min(max(cc, 0.0), ccx)

def solve(t1, t2, ccx, full):
    # For a CGC, CC0 follows from CC(t1) = 10% (exponential phase); bisect CGC so CC(t2) = full
    lo, hi = 0.01, 1.0
    for _ in range(200):
        cgc = (lo + hi) / 2
        cc0 = 0.10 * math.exp(-cgc * t1)
        if growth(cc0, ccx, cgc, t2) < full:
            lo = cgc
        else:
            hi = cgc
    return cc0, cgc

def day(cc0, ccx, cgc, thr):
    return next(d for d in range(400) if growth(cc0, ccx, cgc, d) >= thr)

# crop: (FAO-56 row, Lini, Ldev, Lmid, Llate, gap days, CCx, CCx source)
CROPS = {
    "Shell peas (Europe)": ("Peas, Europe, May", 15, 25, 35, 15, 10, 0.95, "assumed"),
    "Shell peas (Idaho)": ("Peas, Idaho, April", 35, 25, 30, 20, 10, 0.95, "assumed"),
    "Onion": ("Onion (dry), Mediterranean, April", 15, 25, 70, 40, 14, 0.95, "assumed"),
    "Cabbage, broccoli": ("Crucifers, Mediterranean, April", 20, 30, 20, 10, 0, 0.95, "assumed"),
    "Carrot": ("Carrots, Mediterranean, Feb/Mar", 30, 40, 60, 20, 14, 0.95, "assumed"),
    "Beets": ("Beets (table), Mediterranean, Apr/May", 15, 25, 20, 10, 7, 0.95, "assumed"),
    "Celery": ("Celery, Mediterranean, April", 25, 40, 45, 15, 0, 0.95, "assumed"),
    "Leafy greens": ("Lettuce, Mediterranean, April", 20, 30, 15, 10, 7, 0.95, "assumed"),
    "Pepper": ("Sweet peppers, Europe/Medit., Apr/June", 28, 35, 40, 20, 0, 0.75, "as tomato (AquaCrop)"),
    "Cucumber": ("Cucumber, Arid, June/Aug", 20, 30, 40, 15, 7, 0.95, "assumed"),
    "Melon": ("Sweet melons, Mediterranean, May", 25, 35, 40, 20, 7, 0.95, "assumed"),
    "Pumpkin, winter squash": ("Pumpkin/winter squash, Europe, June", 25, 35, 35, 25, 7, 0.95, "assumed"),
    "Summer squash": ("Squash/zucchini, Medit./Europe, May/June", 20, 30, 25, 15, 7, 0.95, "assumed"),
    "Sweet potato": ("Sweet potato, Mediterranean, April", 20, 30, 60, 40, 0, 0.95, "assumed"),
    "Wheat, barley (spring)": ("Barley/Oats/Wheat, 35–45° lat., Mar/Apr", 20, 25, 60, 30, 10, 0.95, "assumed"),
    "Asparagus (fern)": ("Asparagus, warm winter, Feb", 50, 30, 100, 50, 0, 0.95, "assumed"),
}

print("| Crop | FAO-56 row | Gap | CCx | CC₀ | CGC /day | 10% / 50% / 80% (days after emergence) | Mid-season ends (days after emergence) |")
print("|---|---|---|---|---|---|---|---|")
for crop, (row, lini, ldev, lmid, llate, gap, ccx, _src) in CROPS.items():
    t1, t2 = lini - gap, lini + ldev - gap
    full = 0.80 if ccx >= 0.84 else 0.95 * ccx
    cc0, cgc = solve(t1, t2, ccx, full)
    d = [day(cc0, ccx, cgc, x) for x in (0.10, 0.50, min(0.80, 0.95 * ccx))]
    print(f"| {crop} | {row} | {gap} | {ccx:.0%} | {cc0:.2%} | {cgc:.3f} | {d[0]} / {d[1]} / {d[2]} | {lini + ldev + lmid - gap} |")
