"""scan: one-at-a-time parameter moves of a gear around a practice file, flying-start lab (task sprint_touch_v4x).

  source scratchpad/sprint2/env.sh; ROBOLAB_SNAP=run_v4_p95j [ROBOLAB_TRUNK_STAB=2000,100,300] \
   .venv/bin/python scratchpad/sprint2/scan.py PARAMS --gear 5 --moves "k_reach=0.25,0.6;psi_to=-0.5" --seeds 0,1,3,4 [--seconds 12]

Each move name is a gear-K twin: value(s) written as g<K>_<name>. Prints per move: falls, mean peak of survivors, mean of the stance columns.
"""
import argparse, multiprocessing as mp, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import numpy as np
import lab
from practice import read_params

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("params"); ap.add_argument("--gear", type=int, default=5)
    ap.add_argument("--moves", required=True); ap.add_argument("--seeds", default="0,1,3,4")
    ap.add_argument("--seconds", type=float, default=12.0); ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--task", default="sprint_touch_v4x")
    ap.add_argument("--controller", default=os.path.join(ROOT, "bin", "challengers", "run_gear-v4c"))
    ap.add_argument("--attrs", default="objective=3,fly_touch=2,fall_pen=300")
    ap.add_argument("--base", action="store_true", help="also run the unmodified file")
    a = ap.parse_args()
    p0 = read_params(a.params)
    attrs = {kv.split("=")[0]: float(kv.split("=")[1]) for kv in a.attrs.split(",") if kv}
    seeds = [int(s) for s in a.seeds.split(",")]
    cases = [("base", {})] if a.base else []
    for mv in a.moves.split(";"):
        if not mv:
            continue
        name, vals = mv.split("=")
        for v in vals.split(","):
            cases.append((f"{name}={v}", {f"g{a.gear}_{name}": float(v)}))
    jobs = []
    for label, ch in cases:
        p = dict(p0); p.update(ch)
        for s in seeds:
            jobs.append((a.task, p, s, a.seconds, "flying", attrs, a.controller, None, None, 0.5, False))
    with mp.Pool(a.workers) as pool:
        res = pool.map(lab.run_one, jobs, chunksize=1)
    cols = ["tc", "flight", "step", "th_td", "th_lo", "kn_td", "kn_max", "fz_mean", "fz_peak", "pitch_rock"]
    print(f"{'move':22s} falls  peak   steady | " + " ".join(f"{c:>8s}" for c in cols))
    k = len(seeds)
    for i, (label, _) in enumerate(cases):
        rr = res[i * k:(i + 1) * k]
        ok = [r for r in rr if "error" not in r and not r["fell"]]
        falls = sum(1 for r in rr if r.get("fell") or "error" in r)
        if ok:
            pk = np.mean([r["peak"] for r in ok]); sd = np.mean([r["steady"] for r in ok])
            row = " ".join(f"{np.nanmean([r.get(c, np.nan) for r in ok]):8.3f}" for c in cols)
        else:
            pk = sd = 0.0; row = ""
        print(f"{label:22s} {falls}/{k}  {pk:6.3f} {sd:6.3f} | {row}")



if __name__ == '__main__':
    main()
