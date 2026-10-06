#!/usr/bin/env python3
"""R6, the RETENTION-AWARE backward plan with a DIRECTIONAL retention model (3 Oct 2026). From the gentle dry run (out/tt5/gentle.jsonl: joint-space min-jerk move + pad-space refinement, welded) of every candidate:
reachable = pad error at the planned contact <= 1.5 cm and <= 2.5 deg; retained = ret_lat <= LAT, ret_ax <= AX, ret_n <= NRM (m/s^2: the palm's acceleration across the paddle in its plane / along its long axis / along its
normal; the hand-held paddle was lost above about 80 / 120 / 115). Selection: among reachable and retained candidates the best landing margin; none: the retained candidate with the smallest pad error, else the
reachable one with the smallest ret_lat. Writes out/tt5/rerun_r6_<LAT>.json (seed, off, kind, qlast) for joint_rerun.py --src r6_<LAT> (hand-held execution of the SAME gentle move).
    python3 scratchpad/tt5/retention_select.py --lat 60,80,100 [--ax 120 --nrm 115]       from bits/tungsten-robolab"""
import argparse
import collections
import json

import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("--src", default="out/tt5/gentle.jsonl")
ap.add_argument("--lat", default="60,80,100")
ap.add_argument("--ax", type=float, default=120.0)
ap.add_argument("--nrm", type=float, default=115.0)
ap.add_argument("--tag", default="")
a = ap.parse_args()
rows = [json.loads(l) for l in open(a.src)]
by = collections.defaultdict(list)
for r in rows:
    if r.get("error") or not r.get("perr") or r.get("ret_lat") is None:
        continue
    pe = r["perr"]
    r["pos"], r["ang"] = 100 * float(np.linalg.norm(pe[:3])), float(pe[3])
    r["reached"] = r["pos"] <= 1.5 and r["ang"] <= 2.5
    r["err"] = r["pos"] / 1.5 + r["ang"] / 2.5
    by[r["seed"]].append(r)
print(f"{len(by)} serves, {sum(len(c) for c in by.values())} gentle dry runs; welded outcome of all candidates: solved {100 * np.mean([(r['solved'] or 0) > 0 for c in by.values() for r in c]):.0f} %")
for lat in [float(x) for x in a.lat.split(",")]:
    out, n_ok, n_ret = [], 0, 0
    for sd, c in sorted(by.items()):
        ok = [r for r in c if r["reached"] and r["ret_lat"] <= lat and r["ret_ax"] <= a.ax and r["ret_n"] <= a.nrm]
        if ok:
            ch = max(ok, key=lambda r: r["margin"]); n_ok += 1
        else:
            ret = [r for r in c if r["ret_lat"] <= lat and r["ret_ax"] <= a.ax and r["ret_n"] <= a.nrm]
            if ret:
                ch = min(ret, key=lambda r: r["err"]); n_ret += 1
            else:
                reach = [r for r in c if r["reached"]]
                ch = min(reach or c, key=lambda r: r["ret_lat"])
        out.append(dict(seed=sd, off=ch["off"], kind=ch["kind"], qlast=ch["qlast"], margin=ch["margin"], ret_lat=ch["ret_lat"], ret_ax=ch["ret_ax"], ret_n=ch["ret_n"], solved_weld=ch["solved"], reached=ch["reached"]))
    json.dump(out, open(f"out/tt5/rerun_r6{a.tag}_{int(lat)}.json", "w"))
    nret = sum(1 for o in out if o["ret_lat"] <= lat and o["ret_ax"] <= a.ax and o["ret_n"] <= a.nrm)
    print(f"LAT <= {lat:4.0f}: {n_ok} serves have a reachable AND retained candidate; {n_ret} only a retained one; chosen plans retained on {nret} of {len(out)}; welded gentle outcome of the chosen: {sum(1 for o in out if (o['solved_weld'] or 0) > 0)} of {len(out)}; margin median {np.median([o['margin'] for o in out]):.2f}")
