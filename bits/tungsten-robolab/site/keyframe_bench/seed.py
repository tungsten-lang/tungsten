#!/usr/bin/env python3
"""Seed documents for the Keyframe Bench database (collection `keyframes`, one doc per keyframe, id <set>.<event>).

    python3 site/keyframe_bench/seed.py          # writes site/keyframe_bench/seed/<set>.<event>.json and prints a summary

Sets:
  run_natural   Erik's set 3 of 27 Sep (params/keyframes_erik3.txt): td 0 %, ms 18 %, hr 30 %, to 36 %, kl 38 % ("max knee height"),
                on top of the literature reference. The reference of the extra keyframes is interpolated from the
                literature td / ms / to (the Bench does the same when a keyframe is added). `kl` is seeded as a SUBSET keyframe:
                only the swing hip (the height of the knee) is pinned; the runner never targeted it (it is an optional via point).
  bolt_sprint   the 15 keyframes of Bolt's sprint from blocks (playground/refs/bolt/editor/*.json), unchanged.

A doc without `pinned` means every joint is pinned (what every earlier keyframe meant).
"""
import glob
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
JN = ["hip", "knee", "ankle", "toe", "shoulder", "elbow"]
KEYS = [f"{s}_{j}" for s in ("st", "sw") for j in JN] + ["spine", "pelvis"]

# Literature reference (Novacheck 1998, Hamner & Delp 2013, Fukuchi 2017, Pontzer 2009): the same values as the page's fallback.
LIT = {
    "td": dict(st_hip=30, st_knee=18, st_ankle=0, st_toe=0, sw_hip=-8, sw_knee=55, sw_ankle=12, sw_toe=0, st_shoulder=-18.5, st_elbow=82.1, sw_shoulder=28.5, sw_elbow=87.9, spine=2.4, pelvis=3),
    "ms": dict(st_hip=12, st_knee=40, st_ankle=-20, st_toe=0, sw_hip=20, sw_knee=110, sw_ankle=-5, sw_toe=0, st_shoulder=24.3, st_elbow=87.4, sw_shoulder=-14.3, sw_elbow=82.6, spine=5.9, pelvis=3),
    "to": dict(st_hip=-12, st_knee=15, st_ankle=25, st_toe=-30, sw_hip=55, sw_knee=90, sw_ankle=-2, sw_toe=0, st_shoulder=44.9, st_elbow=90, sw_shoulder=-34.9, sw_elbow=80, spine=3.1, pelvis=3),
}
RUN_EVENTS = [("td", "Touchdown", 0.0), ("ms", "Mid-stance", 18.0), ("hr", "Heel rise", 30.0), ("to", "Toe-off", 36.0), ("kl", "Max knee height", 38.0)]


def minjerk(t):
    return t * t * t * (10 - 15 * t + 6 * t * t)


def side_pose(a, mirror=False):
    st = {j: a["st_" + j] for j in JN}
    sw = {j: a["sw_" + j] for j in JN}
    return {"r": sw if mirror else st, "l": st if mirror else sw, "spine": a["spine"], "pelvis": a["pelvis"]}


def to_stsw(sp):
    o = {f"st_{j}": sp["r"][j] for j in JN}
    o.update({f"sw_{j}": sp["l"][j] for j in JN})
    o["spine"], o["pelvis"] = sp["spine"], sp["pelvis"]
    return o


def lerp_pose(a, b, t):
    return {"r": {k: a["r"][k] + (b["r"][k] - a["r"][k]) * t for k in a["r"]}, "l": {k: a["l"][k] + (b["l"][k] - a["l"][k]) * t for k in a["l"]},
            "spine": a["spine"] + (b["spine"] - a["spine"]) * t, "pelvis": a["pelvis"] + (b["pelvis"] - a["pelvis"]) * t}


def pose_at(events, p, pick):
    """The page's poseAt: keyframes and their mirrors, min-jerk between neighbours (events: [(phase, angles)])."""
    pts = []
    for ph, a in events:
        pts += [(ph, side_pose(a)), (ph + 50, side_pose(a, True))]
    pts.sort(key=lambda x: x[0])
    pts.append((pts[0][0] + 100, pts[0][1]))
    q = p + 100 if p < pts[0][0] else p
    i = 0
    while i < len(pts) - 2 and q > pts[i + 1][0]:
        i += 1
    (pa, a), (pb, b) = pts[i], pts[i + 1]
    t = min(1.0, max(0.0, (q - pa) / max(1e-6, pb - pa)))
    return {k: round(v, 1) for k, v in to_stsw(lerp_pose(a, b, minjerk(t))).items()}


def read_params(path):
    out = {}
    for line in open(path):
        line = line.strip()
        if line and not line.startswith("#"):
            k, v = line.split()[:2]
            out[k] = float(v)
    return out


def main():
    out_dir = os.path.join(HERE, "seed")
    os.makedirs(out_dir, exist_ok=True)
    for f in glob.glob(os.path.join(out_dir, "*.json")):
        os.remove(f)
    docs = []
    params = read_params(os.path.join(ROOT, "params", "keyframes_erik3.txt"))
    lit_events = [(0.0, LIT["td"]), (18.0, LIT["ms"]), (36.0, LIT["to"])]
    for ev, label, phase in RUN_EVENTS:
        angles = {k: params[f"ref_{ev}_{k}"] for k in KEYS}
        assert params[f"ref_{ev}_phase"] == phase, (ev, params[f"ref_{ev}_phase"])
        reference = dict(LIT[ev]) if ev in LIT else pose_at(lit_events, phase, None)
        doc = {"set": "run_natural", "set_label": "Natural run (right stance; the left step is the mirror)", "set_order": 0, "period_s": 0.69,
               "event": ev, "label": label, "phase_pct": phase, "order": phase, "angles": angles, "reference": reference, "edited": True,
               "source": "Erik's set 3 (27 Sep), seeded from params/keyframes_erik3.txt"}
        if ev in ("hr", "kl"):
            doc["user_added"] = True
        if ev == "kl":
            doc["pinned"] = {k: (k == "sw_hip") for k in KEYS}
            doc["source"] += "; a subset keyframe: only the swing hip (the height of the knee) is pinned, the runner does not target it"
        docs.append(doc)
    for f in sorted(glob.glob(os.path.join(ROOT, "playground", "refs", "bolt", "editor", "*.json"))):
        d = json.load(open(f))
        if d.get("set") == "bolt_sprint":
            docs.append(d)
    for d in docs:
        path = os.path.join(out_dir, f"{d['set']}.{d['event']}.json")
        json.dump(d, open(path, "w"), indent=1)
    print(f"wrote {len(docs)} seed docs to {out_dir}: " + ", ".join(f"{d['set']}.{d['event']}" for d in docs))


if __name__ == "__main__":
    main()
