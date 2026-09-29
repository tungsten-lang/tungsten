"""alt_try: DIAGNOSTIC. Variants of a params file: mean alternation amplitude (ms; RMS of |dgap|/2 of the aerial gaps, t >= 9 s), peak speed, falls.
  env... alt_try.py TASK BASE.txt --seeds 141,142,143 --seconds 30 --workers 3 "label::name=v,name=v" ..."""
import argparse, multiprocessing as mp, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(ROOT, "playground"))
import numpy as np
from practice import load_task, read_params
from bridge import Sim
from alt_growth import runs_of

def one(job):
    task_name, params, ctl, seed, secs, attrs = job
    task = load_task(task_name); task.seed = seed
    for k, v in attrs.items(): setattr(task, k, v)
    sim = Sim(task, params=params, controller=ctl)
    m = sim.run(secs)
    r = np.array([(x[0], x[3], x[4]) for x in task.rec], float)
    t = r[:, 0]; lc = r[:, 1] > 0.5; rc = r[:, 2] > 0.5
    iv = [(t[a], t[b - 1]) for a, b in runs_of(~lc & ~rc, t, 0.0, 0.01)]
    g = np.array([b - a for a, b in iv]); tg = np.array([a for a, b in iv])
    alt = np.abs(np.diff(g)) / 2.0; ta = tg[1:]
    sel = (ta >= 9.0) & (ta < t[-1] - 0.3)
    return bool(m["fell"]), float(t[-1]), float(m.get("peak_speed_1s") or 0.0), float(np.sqrt(np.mean(alt[sel] ** 2))) * 1000 if sel.sum() > 3 else float("nan"), float(np.mean(alt[sel] > 0.010)) if sel.sum() > 3 else float("nan")

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("task"); ap.add_argument("params"); ap.add_argument("variants", nargs="*")
    ap.add_argument("--seeds", default="141,142,143"); ap.add_argument("--seconds", type=float, default=30.0); ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--controller"); ap.add_argument("--attrs", default="")
    a = ap.parse_args()
    base = read_params(a.params); attrs = {kv.split("=")[0]: float(kv.split("=")[1]) for kv in a.attrs.split(",") if kv}
    seeds = [int(s) for s in a.seeds.split(",")]
    variants = [""] + list(a.variants); jobs = []
    for v in variants:
        p = dict(base)
        for kv in v.split("::")[-1].split(","):
            if kv: k, x = kv.split("="); p[k] = float(x)
        for s in seeds: jobs.append((a.task, p, a.controller, s, a.seconds, attrs))
    with mp.Pool(a.workers) as pool: res = pool.map(one, jobs, chunksize=1)
    k = len(seeds)
    for i, v in enumerate(variants):
        rr = res[i * k:(i + 1) * k]
        lab = (v or "BASE").split("::")[0][:40]
        print(f"{lab:40s} falls {sum(r[0] for r in rr)}/{k}  peak {np.mean([r[2] for r in rr]):5.2f}  alt_rms {np.nanmean([r[3] for r in rr]):5.1f} ms  frac>10ms {np.nanmean([r[4] for r in rr]):.2f}")
