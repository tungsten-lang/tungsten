"""The noise-ladder table: controllers x rungs, full rollouts (kladder.job), per-start rows to JSON.

  kltable.py --entry base:bin/champions/soccer_p1-20260926-151503:playground/arena/params/soccer_p1-20260926-151503.txt [--entry label:ctl:params ...]
             --seeds 6000:6016 --rungs 0,0.05,0.1,0.25,0.5 --offsets "-0.05:0,-0.1:0,0:0.1,0:-0.1" --json out/ladder_final.json

A rung is a joint-noise scale of the P2 draw (+-0.02 rad): 0.05 = +-0.001, 0.1 = +-0.002, 0.25 = +-0.005, 0.5 = +-0.01, 1.0 = the official +-0.02. An offset
dx:dy moves the root from the P1 stance (39, 0) (dx = -0.1: 10 cm short of the ball's stance), at noise 0.
`--official` adds the official P2 reset (noise 1 and the draw's own root position) on the given seeds.
"""
import argparse
import json
import multiprocessing as mp
import os
import sys
import time

import numpy as np

sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
import kcommon as K
import kladder as L


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--entry", action="append", required=True, help="label:controller:params")
    ap.add_argument("--seeds", default="6000:6016")
    ap.add_argument("--rungs", default="0,0.05,0.1,0.25,0.5")
    ap.add_argument("--offsets", default="-0.05:0,-0.1:0,0:0.1,0:-0.1")
    ap.add_argument("--official", default="", help="seeds lo:hi for the official P2 reset")
    ap.add_argument("--set", default="")
    ap.add_argument("--seconds", type=float, default=5.5)
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--json", default="")
    a = ap.parse_args()
    lo, hi = a.seeds.split(":")
    seeds = list(range(int(lo), int(hi)))
    extra = {}
    for kv in a.set.split(","):
        if "=" in kv:
            k, v = kv.split("=")
            extra[k.strip()] = float(v)
    cells = []
    for r in a.rungs.split(","):
        if r:
            cells.append((f"noise {r}", float(r), 0.0, 0.0, seeds))
    for o in a.offsets.split(","):
        if o:
            dx, dy = [float(v) for v in o.split(":")]
            cells.append((f"offset dx {dx:+.2f} dy {dy:+.2f}", 0.0, dx, dy, seeds))
    if a.official:
        l2, h2 = a.official.split(":")
        cells.append(("official P2 reset", 1.0, None, None, list(range(int(l2), int(h2)))))
    out = {}
    t0 = time.time()
    for ent in a.entry:
        label, ctl, params = ent.split(":", 2)
        p = K.read_params(params)
        p.update(extra)
        ctl = os.path.abspath(ctl)
        jobs = []
        for name, nz, dx, dy, sd in cells:
            for s in sd:
                jobs.append((p, ctl, s, nz, dx, dy, a.seconds, "", "x", None))
        with mp.Pool(a.workers) as pool:
            rows = pool.map(L.job, jobs, chunksize=1)
        out[label] = rows
        i = 0
        print(f"== {label} ({time.time()-t0:.0f}s)")
        for name, nz, dx, dy, sd in cells:
            rs = rows[i:i + len(sd)]
            i += len(sd)
            g = sum(1 for r in rs if r["goal"])
            ok = sum(1 for r in rs if r["kick_ok"])
            sp = np.mean([r["ball_speed"] or 0 for r in rs])
            print(f"  {name:28s} goals {g:2d}/{len(rs)}  kick_ok {ok:2d}/{len(rs)}  ball {sp:5.2f} m/s  touched {sum(1 for r in rs if r['t_touch'] is not None):2d}  fallen {sum(1 for r in rs if r['fallen']):2d}", flush=True)
    if a.json:
        json.dump(out, open(a.json, "w"), indent=1)


if __name__ == "__main__":
    main()
