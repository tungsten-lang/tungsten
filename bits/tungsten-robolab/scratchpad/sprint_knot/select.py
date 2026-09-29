"""select: validation pass over a search's archive (playground/hsearch.py --archive) or over params files.

  ROBOLAB_CALIB=v4 [ROBOLAB_PROFILE=...] ROBOLAB_CONTROLLER=... .venv/bin/python scratchpad/sprint_knot/select.py \
      sprint_touch_v4 --archive arch.npz --top 12 --seeds 51,52,...,62 --seconds 30 --workers 4 --out best.txt [--files a.txt b.txt]

Candidates: the `top` archive entries that survived every training seed, best training score first (near-duplicates
under `--dedup` normalised L-inf are dropped), plus any --files. Each runs the validation seeds; ranked by falls
(fewest first) then the arena's metric (mean peak_speed_1s of the survivors), the best goes to --out.
"""
import argparse, json, multiprocessing as mp, os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
from search import rollout, write_params  # noqa: E402
from practice import read_params  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("task"); ap.add_argument("--archive"); ap.add_argument("--files", nargs="*", default=[])
    ap.add_argument("--top", type=int, default=12); ap.add_argument("--dedup", type=float, default=0.004)
    ap.add_argument("--seeds", default="51,52,53,54,55,56,57,58,59,60,61,62"); ap.add_argument("--seconds", type=float, default=30.0)
    ap.add_argument("--attrs", default="objective=2"); ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--out"); ap.add_argument("--label", default="select")
    a = ap.parse_args()
    attrs = {kv.split("=")[0]: float(kv.split("=")[1]) for kv in a.attrs.split(",") if kv}
    seeds = [None if s in ("None", "none") else int(s) for s in a.seeds.split(",")]
    cands = []  # (name, params)
    if a.archive:
        z = np.load(a.archive, allow_pickle=True)
        X, F, ran = z["X"], z["F"], z["ran"]
        names = [str(n) for n in z["names"]]
        lo, hi, v0, x0 = z["lo"], z["hi"], z["v0"], z["x0"]
        fixed = json.loads(str(z["fixed"]))
        full = int(np.max(ran))
        order = [i for i in np.argsort(-F) if ran[i] == full]
        kept = []
        for i in order:
            if all(np.max(np.abs(X[i] - X[j])) > a.dedup for j in kept):
                kept.append(i)
            if len(kept) >= a.top:
                break
        for i in kept:
            v = lo + (hi - lo) * np.clip(X[i], 0, 1)
            v = np.where(X[i] == x0, v0, v)
            p = dict(fixed); p.update({n: float(x) for n, x in zip(names, v)})
            cands.append((f"arch#{i} train {F[i]:.1f}", p))
    for f in a.files:
        cands.append((f, read_params(f)))
    jobs = [(a.task, p, s, a.seconds, attrs) for _, p in cands for s in seeds]
    with mp.Pool(a.workers) as pool:
        res = pool.map(rollout, jobs, chunksize=1)
    k = len(seeds)
    rows = []
    for i, (name, p) in enumerate(cands):
        rr = res[i * k:(i + 1) * k]
        falls = sum(1 for _, m, _ in rr if m.get("fell"))
        pk = [m.get("peak_speed_1s") or 0.0 for _, m, _ in rr if not m.get("fell")]
        rows.append((falls, -(float(np.mean(pk)) if pk else 0.0), name, p, float(np.mean(pk)) if pk else 0.0, float(np.min(pk)) if pk else 0.0))
    rows.sort(key=lambda r: (r[0], r[1]))
    for f, _, name, _, mean, mn in rows:
        print(f"falls {f:2d}/{k}  mean peak {mean:6.3f}  min {mn:6.3f}  {name}")
    if a.out and rows:
        best = rows[0]
        write_params(a.out, a.label, best[3], -1000.0 * best[0] + best[4], [{"falls": best[0], "mean_peak": best[4], "name": best[2]}])
        print("wrote", a.out, best[2])


if __name__ == "__main__":
    main()
