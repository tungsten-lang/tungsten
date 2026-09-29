"""try: DIAGNOSTIC. Evaluate variants of a params file: each variant is a comma-separated name=value list
applied on top of the base file. Prints per variant the score, peak / steady speed, falls and stance geometry
over the given seeds (mean; fell count).

  ROBOLAB_CALIB=v4 [ROBOLAB_PROFILE=...] ROBOLAB_CONTROLLER=... .venv/bin/python scratchpad/sprint_knot/try.py \
      sprint_touch_v4 BASE.txt --seeds None,31,32 --seconds 20 --attrs objective=2 --workers 2 \
      "gate_push=1" "gate_push=1,gate_swing=1" "t_push_max=0.15"
"""
import argparse, multiprocessing as mp, os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
from search import rollout  # noqa: E402
from practice import read_params  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("task"); ap.add_argument("params"); ap.add_argument("variants", nargs="*")
    ap.add_argument("--seeds", default="None,31,32"); ap.add_argument("--seconds", type=float, default=20.0)
    ap.add_argument("--attrs", default=""); ap.add_argument("--workers", type=int, default=2)
    a = ap.parse_args()
    base = read_params(a.params)
    attrs = {kv.split("=")[0]: float(kv.split("=")[1]) for kv in a.attrs.split(",") if kv}
    seeds = [None if s in ("None", "none") else int(s) for s in a.seeds.split(",")]
    variants = [""] + list(a.variants)
    jobs = []
    for v in variants:
        p = dict(base)
        for kv in v.split(","):
            if kv:
                k, x = kv.split("="); p[k] = float(x)
        for s in seeds:
            jobs.append((a.task, p, s, a.seconds, attrs))
    with mp.Pool(a.workers) as pool:
        res = pool.map(rollout, jobs, chunksize=1)
    k = len(seeds)
    for i, v in enumerate(variants):
        rr = res[i * k:(i + 1) * k]
        def mean(key):
            xs = [m.get(key) for _, m, _ in rr if m.get(key) is not None]
            return float(np.mean(xs)) if xs else float("nan")
        falls = sum(1 for _, m, _ in rr if m.get("fell"))
        print(f"{v or 'BASE':38s} score {np.mean([s for s,_,_ in rr]):8.2f} peak {mean('peak_speed_1s'):5.2f} steady {mean('steady_speed'):5.2f} "
              f"falls {falls}/{k} tc {mean('contact_time'):.3f} fl {mean('flight_time'):.3f} thTD {mean('thigh_td'):5.2f} thLO {mean('thigh_lo'):5.2f} "
              f"knTD {mean('knee_td'):4.2f} knMax {mean('knee_max'):4.2f} fz {mean('stance_fz'):4.2f} pkGRF {mean('peak_grf'):5.2f}")


if __name__ == "__main__":
    main()
