"""report6: the final tables of round 6 (agent L6): best of six per candidate and seed set, failure accounting, pooled estimates. LABELLED beyond-human body, unlimited run-up, T = 8.95 m.
usage: report6.py   (reads out/lj6/ev_<tag>_<seeds>.json for the sets that exist)"""
import json, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bo6

ROOT = "/Users/erik/tungsten/bits/tungsten-robolab/out/lj6"
CANDS = [("C7", "L4's C7 (F1 runner)"), ("L3", "L3's champion (chain D)"), ("K3", "FINAL K3 (H011 + risk-seeking take-off + shift 0.10)"), ("K2", "K2 (10-generation take-off)"), ("K4", "K4 (K3 + retrained landing)")]
SETS = [("SELECTION", "31001-31480"), ("CONFIRMATION", "32001-32480"), ("TEST", "33001-33480"), ("EXTRA", "35001-35960")]

def fails(rows):
    fell = [r for r in rows if r.get("fell_approach")]
    cx = np.array([r.get("com_x", 0.0) for r in fell])
    return {"fell": len(fell), "mid": int(((cx >= 20) & (cx < 140)).sum()), "near": int((cx >= 140).sum()), "early": int((cx < 20).sum()),
            "foul": sum(1 for r in rows if r.get("foul")), "som": sum(1 for r in rows if r.get("somersault"))}

pooled = {}
for tag, name in CANDS:
    for sname, seeds in SETS:
        f = "%s/ev_%s_%s.json" % (ROOT, tag, seeds)
        if not os.path.exists(f):
            continue
        sd, marks, rows = bo6.load(f)
        s = bo6.summary(marks); ex = bo6.compete_exact(marks); bs = bo6.bootstrap(marks, B=2000)
        fl = fails(rows)
        print("%-4s %-12s n %4d | legal %5.1f %% | legal mean %.2f med %.2f p90 %.2f max %.2f | per-attempt P(>8.95) %5.2f %% (%3d) | BEST OF SIX %5.1f %% [%4.1f, %5.1f] | mean best %.3f | mean mark %.2f | fell %3d (mid %2d near %2d) foul %2d somers %2d" % (
            tag, sname, s["n"], 100 * s["legal_frac"], s["legal_mean"], s["legal_median"], s["legal_p90"], s["legal_max"], 100 * s["p_gt"], s["n_gt"], 100 * ex["p_gt"],
            100 * bs["p6"][0], 100 * bs["p6"][1], ex["mean"], s["mean_all"], fl["fell"], fl["mid"], fl["near"], fl["foul"], fl["som"]))
        if sname != "SELECTION":
            pooled.setdefault(tag, []).append(marks)
for tag, lst in pooled.items():
    m = np.concatenate(lst)
    if len(lst) > 1:
        s = bo6.summary(m); ex = bo6.compete_exact(m); bs = bo6.bootstrap(m, B=2000)
        print("%-4s pooled CONFIRMATION + TEST (+ EXTRA if run), n %d: legal %.1f %%, per-attempt %.2f %%, BEST OF SIX %.1f %% [%.1f, %.1f], mean best %.3f" % (tag, s["n"], 100 * s["legal_frac"], 100 * s["p_gt"], 100 * ex["p_gt"], 100 * bs["p6"][0], 100 * bs["p6"][1], ex["mean"]))
