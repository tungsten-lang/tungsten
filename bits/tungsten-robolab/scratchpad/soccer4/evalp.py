"""Evaluate params files on a seed list: evalp.py --env E --controller C --seeds a:b [--set k=v] [--seconds s] [--key bal_s] P1 [P2 ...]"""
import argparse, json, os, sys, multiprocessing as mp
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
from search4 import read_params, worker

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--env", default="myoChallengeSoccerP2-v0")
    ap.add_argument("--controller", required=True)
    ap.add_argument("--seeds", required=True)
    ap.add_argument("--set", default="")
    ap.add_argument("--seconds", type=float, default=12.0)
    ap.add_argument("--stage", default="bal")
    ap.add_argument("--keys", default="bal_s,bal_l,bal_r,stand_time")
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--json")
    ap.add_argument("params", nargs="+")
    a = ap.parse_args()
    if ":" in a.seeds:
        lo, hi = a.seeds.split(":"); seeds = list(range(int(lo), int(hi)))
    else:
        seeds = [int(s) for s in a.seeds.split(",")]
    keys = a.keys.split(",")
    ctls = a.controller.split(",")
    allres = {}
    with mp.Pool(a.workers) as pool:
        for i, pf in enumerate(a.params):
            p = read_params(pf)
            for kv in a.set.split(","):
                if "=" in kv:
                    k, v = kv.split("="); p[k] = float(v)
            ctl = os.path.abspath(ctls[min(i, len(ctls) - 1)])
            res = pool.map(worker, [(p, s, a.env, ctl, a.seconds, a.stage) for s in seeds])
            ms = [r[1] for r in res]
            summ = {k: round(float(np.mean([float(m.get(k) or 0) for m in ms if not isinstance(m.get(k), str)])), 3) for k in keys}
            summ["score"] = round(float(np.mean([r[0] for r in res])), 3)
            print(pf, os.path.basename(ctl), json.dumps(summ), flush=True)
            per = [(s, {k: m.get(k) for k in keys}) for s, m in zip(seeds, ms)]
            print("   per-seed", [(s, d.get(keys[0])) for s, d in per], flush=True)
            allres[pf] = ms
    if a.json:
        json.dump(allres, open(a.json, "w"))

if __name__ == "__main__":
    main()
