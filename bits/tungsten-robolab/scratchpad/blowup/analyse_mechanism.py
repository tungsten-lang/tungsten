"""The sliver mechanism at scale, from the telemetry of the guarded arena rollouts (tasks/myo_soccer_ng.py): per entry and pooled,
how many substeps the right rectus femoris line spent at each |margin| from its wrap tangent, how many substeps fell in the NaN sliver
(0 < margin < 1e-7: survived, or NaN), the exact 1 - dot of each, the NaN events, and the expected number of events from the
P(NaN | exact 1 - dot) table measured on the real library.

usage: analyse_mechanism.py [--cache DIR | --evals]      default: every rollout row in scratchpad/blowup/evalcache, split by trial and controller
"""
import glob
import json
import math
import os
import sys
from collections import defaultdict

HERE = "/Users/erik/tungsten/bits/tungsten-robolab"
EDGES = [0.0, 1e-8, 6e-8, 1e-7, 1e-6, 1e-5, 1e-4, 1e-3, 1e-2, 1e9]
LABELS = ["<1e-8", "1e-8..6e-8", "6e-8..1e-7", "1e-7..1e-6", "1e-6..1e-5", "1e-5..1e-4", "1e-4..1e-3", "1e-3..1e-2", ">1e-2"]

rows = []   # (trial, controller tag, seed, row)
for f in sorted(glob.glob(os.path.join(HERE, "scratchpad", "blowup", "evals", "*.json"))):
    d = json.load(open(f))
    tag = os.path.basename(d["controller"])
    metric = os.path.basename(f).split("-")[0]
    trial = "310" if metric == "bal1_300" else "hold20"
    for s, r in zip(d["seeds"], d["rows"]):
        if "error" not in r:
            rows.append((trial, tag, s, r))
if not rows:
    print("no evals yet")
    sys.exit(0)
# keep the newest file per (trial, tag) only
seen = {}
for f in sorted(glob.glob(os.path.join(HERE, "scratchpad", "blowup", "evals", "*.json"))):
    d = json.load(open(f))
    metric = os.path.basename(f).split("-")[0]
    seen[("310" if metric == "bal1_300" else "hold20", os.path.basename(d["controller"]))] = f
rows = []
for (trial, tag), f in sorted(seen.items()):
    d = json.load(open(f))
    for s, r in zip(d["seeds"], d["rows"]):
        if "error" not in r:
            rows.append((trial, tag, s, r))


def parse_hist(txt):
    if not txt:
        return None
    a, b = txt.split("|")
    return [int(x) for x in a.split(",")], [int(x) for x in b.split(",")]


def pois_ci(k, z=1.96):
    """approximate 95 % interval for a Poisson count k (exact-ish via Wilson-Hilferty / gamma quantiles)"""
    lo = 0.0 if k == 0 else k * (1 - 1 / (9 * k) - z / (3 * math.sqrt(k))) ** 3
    hi = (k + 1) * (1 - 1 / (9 * (k + 1)) + z / (3 * math.sqrt(k + 1))) ** 3
    return max(lo, 0.0), hi


groups = defaultdict(list)
for trial, tag, s, r in rows:
    groups[(trial, tag)].append((s, r))
tot = {"events": 0, "visits": 0, "expected": 0.0, "sub": 0}
for (trial, tag), lst in sorted(groups.items()):
    pos = [0] * 9
    neg = [0] * 9
    substeps = 0
    visits = 0
    events = 0
    expected = 0.0
    ev_omd = []
    vis_omd = []
    secs = 0.0
    hover = []
    for s, r in lst:
        h = parse_hist(r.get("wrap_r_hist"))
        if h:
            for i in range(9):
                pos[i] += h[0][i]
                neg[i] += h[1][i]
            substeps += int(r.get("wrap_r_substeps") or 0)
            hv = (sum(h[0][:6]) + sum(h[1][:6])) / max(int(r.get("wrap_r_substeps") or 1), 1)   # substeps within 1e-4 of the tangent (bins 0..5)
            hover.append((s, hv))
        visits += int(r.get("wrap_r_visits") or 0)
        events += int(r.get("nan_events") or 0)
        expected += float(r.get("nan_expected") or 0.0)
        secs += float(r.get("time") or 0.0)
        ev_omd += [float(x) for x in (r.get("nan_omd") or "").split(";") if x]
        vis_omd += [float(x) for x in (r.get("wrap_r_visit_omd") or "").split(";") if x]
    print(f"== trial {trial}, entry {tag}: {len(lst)} starts, {secs:.0f} start-seconds, {substeps} substeps watched (t >= 3 s)")
    print("   substeps by |margin| (positive = wrap active | negative):")
    print("   " + "  ".join(f"{LABELS[i]}: {pos[i]}|{neg[i]}" for i in range(9)))
    lo, hi = pois_ci(events)
    print(f"   NaN events {events} (95 % {lo:.1f}..{hi:.1f}) = {1000 * events / max(secs, 1):.2f} per 1000 start-seconds; sliver states (0 < margin < 1e-7): survived {visits} + NaN {len(ev_omd)}; "
          f"expected NaN from the table {expected:.2f}")
    if ev_omd:
        print("   exact 1-dot of the NaN states:", " ".join(f"{x:.1e}" for x in sorted(ev_omd)))
    hv_sorted = sorted(hover, key=lambda x: -x[1])
    n_hov = sum(1 for _, v in hover if v > 0.01)
    evs = [(s, r.get("nan_events"), r.get("nan_first_t"), r.get("nan_tendons"), r.get("nan_mirror")) for s, r in lst if (r.get("nan_events") or 0) > 0]
    if evs:
        print("   starts with NaN events (seed, events, first t, tendons, mirror-first):", "; ".join(f"{a} x{int(b)} @{c} {d} m{int(e or 0)}" for a, b, c, d, e in evs))
    print(f"   starts with > 1 % of the substeps within 1e-4 of the tangent: {n_hov} of {len(hover)}; top: " + " ".join(f"{s}:{v:.2f}" for s, v in hv_sorted[:8]))
    tot["events"] += events
    tot["visits"] += visits + len(ev_omd)
    tot["expected"] += expected
    tot["sub"] += substeps
print()
print(f"pooled: {tot['events']} NaN events among {tot['visits']} sliver states (P = {tot['events'] / max(tot['visits'], 1):.3f}); expected events from the table {tot['expected']:.2f}; {tot['sub']} substeps watched")
