"""Paired comparison of a bcpo scan against the ramp base on the same starts.
usage: cmpcpo.py <off.json> <on.json> [label]
off = new controller, bcpo off (identity check against the earlier base scans val20_ramp.json / tr8_bramp...)
on  = new controller, bcpo on"""
import json, sys
base = "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4/scan/"


def load(fn):
    return {r["seed"]: r for r in json.load(open(fn))}


off = load(sys.argv[1]); on = load(sys.argv[2])
label = sys.argv[3] if len(sys.argv) > 3 else ""
val = load(base + "val20_ramp.json"); tr = load(base + "tr8_bramp_1_b_t_ramp_0.05.json")
feat = {}
for fn in ("liftfeat_val_ramp.json", "liftfeat_tr_ramp.json"):
    for seed, r, snap in json.load(open(base + fn)):
        if snap.get("lift"):
            feat[seed] = snap["lift"]["cpo"]

def lift_t(r):
    for e in r["events"]:
        if e[0].startswith("b_lift"):
            return e[1]
    return None

# identity of the off scan with the old base
same = diff = 0
bad_id = []
for s, r in sorted(off.items()):
    ref = val.get(s) or tr.get(s)
    if ref is None:
        continue
    # events up to 7 s must agree exactly; the standing time when both ran the same horizon
    ev_a = [e for e in r["events"] if e[1] <= 7.0]
    ev_b = [e for e in ref["events"] if e[1] <= 7.0]
    ok = ev_a == ev_b
    if s in val:
        ok = ok and abs((r["stand_time"] or 0) - (ref["stand_time"] or 0)) < 1e-6
    same += ok; diff += (not ok)
    if not ok:
        bad_id.append(s)
print(f"{label} identity (bcpo off vs earlier base): {same} identical, {diff} different {bad_id}")

fixed = broke = both_ok = both_bad = 0
print(f"{'seed':>6} {'cpo@lift':>9} {'base':>22} {'bcpo':>22}  lift base -> bcpo")
for s in sorted(on):
    a = off[s]; b = on[s]
    fa = "OK " if a["good"] else "BAD"; fb = "OK " if b["good"] else "BAD"
    fixed += (not a["good"]) and b["good"]; broke += a["good"] and (not b["good"])
    both_ok += a["good"] and b["good"]; both_bad += (not a["good"]) and (not b["good"])
    la = lift_t(a); lb = lift_t(b)
    print(f"{s:6d} {feat.get(s, float('nan')):+9.3f} {fa} stand {a['stand_time'] or 0:5.1f} bal1 {a['bal1_s'] or 0:5.1f}  {fb} stand {b['stand_time'] or 0:5.1f} bal1 {b['bal1_s'] or 0:5.1f}   {la} -> {lb}")
print(f"{label}: fixed {fixed}, broke {broke}, both ok {both_ok}, both bad {both_bad}")
