"""Replay a set of dumps from their swing start with a controller + params (2 workers), print per-pack rows and category counts.

  kbatch.py --glob 'p1base_n0.05_*' [--glob ...] [--controller C] [--params P] [--set k=v,...] [--lead 2] [--n 48] [--json out.json]
"""
import argparse
import glob
import json
import multiprocessing as mp
import os
import sys
import time

import numpy as np

sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
import kcommon as K
import kreplay as R

_W = None


def _init(controller):
    global _W
    _W = R.Worker(controller)


def one(job):
    path, params, controller, lead, kind = job
    pack = R.load(path)
    if kind == "swing":
        k = R.first_tick(pack, "swing") - lead
    elif kind == "touch":
        k = int(round(pack["row"]["t_touch"] / 0.01)) - 1 - lead
    else:
        k = int(kind)
    m = _W.replay(pack, k, params, controller=controller)
    keep = ["goal", "ball_speed", "t_touch", "cross_y", "pred_y", "launch_deg", "fallen", "t_fall", "t_cross", "strike_zone", "replay_bad", "steps"]
    row = {kk: m.get(kk) for kk in keep}
    row["ok"] = R.kick_ok(m)
    row["score"] = R.score(m)
    row["file"] = os.path.basename(path)
    return row


def category(r):
    if r["goal"]:
        return "goal"
    if r["t_touch"] is None:
        return "no touch"
    sp = r["ball_speed"] or 0
    cy = r["cross_y"] if r["cross_y"] is not None else r["pred_y"]
    if sp < 8.5:
        return "slow"
    if cy is None:
        return "no crossing"
    if abs(cy) < 0.5:
        return "dead zone"
    if abs(cy) > 3.2:
        return "wide"
    if r["fallen"] and r["t_cross"] is None:
        return "good kick, fell"
    return "ok"


def run(files, params, controller, lead=2, workers=2, kind="swing"):
    jobs = [(f, params, controller, lead, kind) for f in files]
    with mp.Pool(workers, initializer=_init, initargs=(controller,)) as pool:
        return pool.map(one, jobs, chunksize=1)


def summarize(rows, tag=""):
    n = len(rows)
    ok = sum(1 for r in rows if r["ok"])
    cats = {}
    for r in rows:
        cats[category(r)] = cats.get(category(r), 0) + 1
    sc = np.mean([r["score"] for r in rows])
    bad = sum(1 for r in rows if r["replay_bad"])
    print(f"{tag} ok {ok}/{n} ({100*ok/n:.0f}%) score {sc:.2f} | " + ", ".join(f"{k} {v}" for k, v in sorted(cats.items(), key=lambda kv: -kv[1])) + (f" | replay mismatch in {bad}" if bad else ""), flush=True)
    return ok, sc


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--glob", action="append", required=True)
    ap.add_argument("--controller", default=None)
    ap.add_argument("--params", default=None)
    ap.add_argument("--set", default="")
    ap.add_argument("--lead", type=int, default=2)
    ap.add_argument("--n", type=int, default=0)
    ap.add_argument("--seeds", default="", help="keep packs whose seed is in lo:hi")
    ap.add_argument("--dir", default="p1base", help="dump directory under ckpt/")
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--json", default="")
    ap.add_argument("--rows", action="store_true")
    a = ap.parse_args()
    files = []
    for g in a.glob:
        files += sorted(glob.glob(R.CK + a.dir + "/" + g + ".pkl.gz") if "/" not in g else glob.glob(g))
    if a.seeds:
        import re
        lo_, hi_ = [int(v) for v in a.seeds.split(":")]
        files = [f for f in files if lo_ <= int(re.search(r"_s(\d+)\.pkl", f).group(1)) < hi_]
    if a.n:
        files = files[:a.n]
    ctl = os.path.abspath(a.controller) if a.controller else K.P1_CTL
    params = K.read_params(a.params) if a.params else K.read_params(K.P1_PARAMS)
    for kv in a.set.split(","):
        if "=" in kv:
            k, v = kv.split("=")
            params[k.strip()] = float(v)
    t0 = time.time()
    rows = run(files, params, ctl, a.lead, a.workers)
    if a.rows:
        for r in rows:
            print(f"  {r['file'][:34]:34s} {category(r):16s} ok {int(r['ok'])} v {r['ball_speed']} cross {r['cross_y'] if r['cross_y'] is not None else r['pred_y']} score {r['score']:.2f}")
    summarize(rows, f"{len(files)} packs, {time.time()-t0:.0f}s")
    if a.json:
        json.dump(rows, open(a.json, "w"), indent=1)
