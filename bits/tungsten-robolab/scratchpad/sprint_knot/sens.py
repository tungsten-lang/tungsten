"""sens: DIAGNOSTIC. One-at-a-time sensitivity of a runner's score to each tunable.
For every tunable, two rollouts with the value moved by +-frac of its declared box (a value
already within `edge` of a bound is also pushed BEYOND the bound by frac, since a skill does not
clamp a params-file value: only the search's box does). Prints d(score), peak_speed_1s, steady, fell.

  ROBOLAB_CALIB=v4 [ROBOLAB_PROFILE=...] ROBOLAB_CONTROLLER=... .venv/bin/python scratchpad/sprint_knot/sens.py \
      sprint_touch_v4 PARAMS --seed 31 --seconds 20 --attrs objective=2 --frac 0.05 --workers 2 --out sens.json
"""
import argparse, json, math, multiprocessing as mp, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
from search import describe, rollout  # noqa: E402
from practice import read_params  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("task"); ap.add_argument("params")
    ap.add_argument("--seed", default="31"); ap.add_argument("--seconds", type=float, default=20.0)
    ap.add_argument("--attrs", default=""); ap.add_argument("--frac", type=float, default=0.05)
    ap.add_argument("--edge", type=float, default=0.03); ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--only"); ap.add_argument("--exclude", default="drv_knee,drv_ankle,drv_gas,drv_hip,drv_ham,drv_swh")
    ap.add_argument("--out")
    a = ap.parse_args()
    init = read_params(a.params)
    tun = describe(a.task, init)
    attrs = {kv.split("=")[0]: float(kv.split("=")[1]) for kv in a.attrs.split(",") if kv}
    seed = None if a.seed in ("None", "none") else int(a.seed)
    excl = set(a.exclude.split(",")) if a.exclude else set()
    only = set(a.only.split(",")) if a.only else None
    jobs = [("base", None, dict(init))]
    for name, dflt, lo, hi in tun:
        if name in excl or (only and name not in only) or name.startswith("tcn"):
            continue
        v = init.get(name, dflt)
        w = hi - lo
        for sgn in (-1, 1):
            nv = v + sgn * a.frac * w
            inside = lo <= nv <= hi
            atedge = (sgn < 0 and v - lo < a.edge * w) or (sgn > 0 and hi - v < a.edge * w)
            if not inside and not atedge:
                nv = min(max(nv, lo), hi)
            p = dict(init); p[name] = nv
            jobs.append((name, (sgn, nv, lo, hi, not inside), p))
    def mk(j):
        return (a.task, j[2], seed, a.seconds, attrs)
    with mp.Pool(a.workers) as pool:
        res = pool.map(rollout, [mk(j) for j in jobs], chunksize=1)
    base = res[0][0]
    print(f"base score {base:.2f} peak {res[0][1].get('peak_speed_1s')} steady {res[0][1].get('steady_speed')} fell {res[0][1].get('fell')}")
    rows = []
    for j, (s, m, w) in zip(jobs[1:], res[1:]):
        rows.append({"name": j[0], "sgn": j[1][0], "value": j[1][1], "lo": j[1][2], "hi": j[1][3], "beyond": j[1][4], "d": s - base,
                     "peak": m.get("peak_speed_1s"), "steady": m.get("steady_speed"), "fell": m.get("fell")})
    rows.sort(key=lambda r: -abs(r["d"]))
    for r in rows[:60]:
        print(f"{r['name']:14s} {'+' if r['sgn']>0 else '-'} v={r['value']:8.4f} [{r['lo']:.2f},{r['hi']:.2f}]{' BEYOND' if r['beyond'] else ''} "
              f"d={r['d']:8.2f} peak={r['peak']} steady={r['steady']} fell={r['fell']}")
    if a.out:
        json.dump({"base": base, "rows": rows}, open(a.out, "w"), indent=1)


if __name__ == "__main__":
    main()
