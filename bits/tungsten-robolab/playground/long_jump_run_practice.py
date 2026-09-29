"""Practice driver for LongJumpRunSkill (several searches in lockstep).

search.py's library (describe, BoxRep, Problem, Search, run_searches) with
several methods / seeds sharing one worker pool, so a sequential method keeps
the workers busy too (as hurdle_hs_practice.py does). Rollouts run the
controller named by ROBOLAB_CONTROLLER (set it to a frozen copy: a rebuild
during practice must not change the program being scored).

    ROBOLAB_CONTROLLER=bin/challengers/long_jump_run-x .venv/bin/python playground/long_jump_run_practice.py \\
        long_jump_p95 --init params/long_jump_p95_init.txt --only 'j_*' --methods bo:1,sep_cma:2 \\
        --budget 600 --workers 4 --seeds None --out out/long_jump_run/a
"""

import argparse
import json
import multiprocessing as mp
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from search import BoxRep, Problem, Search, describe, parse_list, read_params, run_searches  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("task")
    ap.add_argument("--init", nargs="+", default=[], help="params files, later ones override earlier ones")
    ap.add_argument("--only")
    ap.add_argument("--exclude")
    ap.add_argument("--fixed", default="")
    ap.add_argument("--methods", default="bo:1", help="method:seed[:sigma],... run in lockstep")
    ap.add_argument("--budget", type=int, default=600)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--sigma", type=float, default=0.1)
    ap.add_argument("--seeds", default="None")
    ap.add_argument("--risk", type=float, default=0.5)
    ap.add_argument("--seconds", type=float, default=0.0)
    ap.add_argument("--out", required=True, help="output prefix: <out>_<method>_s<seed>.txt / .jsonl")
    a = ap.parse_args()
    init = {}
    for p in a.init:
        init.update(read_params(p))
    fixed = {}
    for kv in a.fixed.split(","):
        if kv:
            k, v = kv.split("=")
            fixed[k] = float(v)
    init.update(fixed)
    tun = describe(a.task, init)
    rep = BoxRep.from_tunables(tun, parse_list(a.only), parse_list(a.exclude), init, fixed)
    seeds = parse_list(a.seeds, int) or [None]
    prob = Problem(a.task, rep, seeds, a.seconds, a.risk)
    searches = []
    for spec in a.methods.split(","):
        parts = spec.split(":")
        method, seed = parts[0], int(parts[1]) if len(parts) > 1 else 1
        sigma = float(parts[2]) if len(parts) > 2 else a.sigma
        tag = f"{a.out}_{method}_s{seed}"
        searches.append(Search(prob, method, a.budget, seed, sigma, out=tag + ".txt", log=tag + ".jsonl"))
    print(f"practice {a.task}: {rep.n} tunables, {len(searches)} searches x {a.budget} rollouts, seeds {seeds}, "
          f"controller {os.environ.get('ROBOLAB_CONTROLLER')}", flush=True)
    print("tunables:", " ".join(rep.names), flush=True)
    t0 = time.time()

    def progress(s):
        m = s.best[2] or {}
        if isinstance(m, list):
            m = m[0] if m else {}
        keys = ("official_m", "effective_m", "board_offset_m", "takeoff_vx", "takeoff_vz", "takeoff_angle_deg", "flight_s")
        brief = {k: m.get(k) for k in keys if k in m}
        print(f"{s.label} gen {s.gen} used {s.used} best {s.best[0]:.4f} ({time.time() - t0:.0f}s) {json.dumps(brief)}",
              flush=True)

    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with mp.Pool(a.workers) as pool:
        run_searches(searches, pool, progress)
    best = max(searches, key=lambda s: s.best[0])
    print("best", best.label, best.best[0], flush=True)


if __name__ == "__main__":
    main()
