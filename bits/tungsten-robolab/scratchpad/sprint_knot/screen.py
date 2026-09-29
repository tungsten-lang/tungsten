"""screen: DIAGNOSTIC. Warm-start screen: evaluate many params files on one body (2 seeds, 20 s) and rank them.

  ROBOLAB_CALIB=v4 [ROBOLAB_PROFILE=...] ROBOLAB_CONTROLLER=... .venv/bin/python scratchpad/sprint_knot/screen.py \
      sprint_touch_v4 FILE... [--seeds None,31] [--seconds 20] [--workers 2] [--top 15]
"""
import argparse, multiprocessing as mp, os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
from search import rollout  # noqa: E402
from practice import read_params  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("task"); ap.add_argument("files", nargs="+")
    ap.add_argument("--seeds", default="None,31"); ap.add_argument("--seconds", type=float, default=20.0)
    ap.add_argument("--attrs", default="objective=2"); ap.add_argument("--workers", type=int, default=2); ap.add_argument("--top", type=int, default=15)
    a = ap.parse_args()
    attrs = {kv.split("=")[0]: float(kv.split("=")[1]) for kv in a.attrs.split(",") if kv}
    seeds = [None if s in ("None", "none") else int(s) for s in a.seeds.split(",")]
    files, params = [], []
    for f in a.files:
        try:
            p = read_params(f)
        except Exception:
            continue
        if "psi_reach" not in p:
            continue
        files.append(f); params.append(p)
    jobs = [(a.task, p, s, a.seconds, attrs) for p in params for s in seeds]
    with mp.Pool(a.workers) as pool:
        res = pool.map(rollout, jobs, chunksize=1)
    k = len(seeds)
    rows = []
    for i, f in enumerate(files):
        rr = res[i * k:(i + 1) * k]
        pk = [m.get("peak_speed_1s") or 0.0 for _, m, _ in rr]
        st = [m.get("steady_speed") or 0.0 for _, m, _ in rr]
        falls = sum(1 for _, m, _ in rr if m.get("fell"))
        rows.append((float(np.mean([s for s, _, _ in rr])), float(np.mean(pk)), float(np.mean(st)), falls, f))
    rows.sort(key=lambda r: -r[0])
    print(f"{len(files)} files x {k} seeds")
    for r in rows[:a.top]:
        print(f"score {r[0]:8.1f} peak {r[1]:5.2f} steady {r[2]:5.2f} falls {r[3]}/{k}  {r[4]}")


if __name__ == "__main__":
    main()
