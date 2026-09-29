"""CMA-ES practice of chosen tunables of the BTL skill on a per-pass objective (round 2 tuner).

    .venv/bin/python scratchpad/btl2/tune.py --ctl bin/challengers/btl2-b1 --init params/dribble_btl_a4.txt \
        --fixed bt_ychain=1 --only br_zh,br_dzc,... --bounds br_zh=0.4:1.0,... --seeds 801,809,... --secs 4.2 \
        --objective p3 --gens 40 --pop 12 --workers 2 --sigma 0.15 --out scratchpad/btl2/params/p3a.txt --log scratchpad/btl2/runs/p3a.log

Each candidate is scored as the mean of the objective over the seeds (one rollout per seed, in a worker
pool: at most 2 workers on this machine). The best candidate is written to --out at every improvement; a run is
resumable with --init pointing at that file (its values override --fixed). Bounds default to the skill's declared
ones (search bounds only, the skill does not clamp) and can be widened with --bounds name=lo:hi,...

Objectives (per rollout result r, params p):
  p3   passes 2 and 3 with the right hand's second stroke (br_*): 2*ok2 + 3*ok3 + 1.5*ok4 + 0.5*dense(pass 3) - rise shortfall
  p2   the left hand's return: 3*ok2 + dense(pass 2) - shortfall of the rise apex below 0.62 (chain seeds: pass 1 received)
  chain3  the first three passes: sum of 3*ok_k + 0.5*dense_k (the round-1 style chain objective)
"""
import argparse
import os
import sys
import time

import numpy as np

sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
sys.path.insert(0, "scratchpad/btl2")
from multiprocessing import get_context  # noqa: E402

from common import load, parse_over, write_params  # noqa: E402


def dense(pl, spot):
    from dribble_btl import pass_score
    return pass_score(pl, spot)


def spots(p):
    from dribble_btl import spots_of
    return spots_of(p)


def obj_p3(r, p):
    lead, back = spots(p)
    pl = r["pass_log"]
    g = lambda k: pl[k] if len(pl) > k else None
    ok = lambda x: 1.0 if x and x["ok"] else 0.0
    p2, p3, p4 = g(1), g(2), g(3)
    s = 2.0 * ok(p2) + 3.0 * ok(p3) + 1.5 * ok(p4) + 0.5 * dense(p3, lead)
    if p3 and p3.get("rise_apex"):
        s -= 2.0 * max(0.0, 0.62 - p3["rise_apex"])
    if r.get("carried"):
        s -= 5.0
    return s


def obj_p2(r, p):
    lead, back = spots(p)
    pl = r["pass_log"]
    g = lambda k: pl[k] if len(pl) > k else None
    ok = lambda x: 1.0 if x and x["ok"] else 0.0
    p2 = g(1)
    s = 3.0 * ok(p2) + dense(p2, back)
    if p2 and p2.get("rise_apex"):
        s -= 4.0 * max(0.0, 0.62 - p2["rise_apex"])
    if r.get("carried"):
        s -= 5.0
    return s


def obj_chain3(r, p):
    lead, back = spots(p)
    pl = r["pass_log"]
    s = 0.0
    for k in range(3):
        x = pl[k] if len(pl) > k else None
        s += (1.0 if k == 0 else 1.5) * (3.0 * (1.0 if x and x["ok"] else 0.0) + 0.5 * dense(x, lead if k % 2 == 0 else back))
    if r.get("carried"):
        s -= 5.0
    return s


OBJ = {"p3": obj_p3, "p2": obj_p2, "chain3": obj_chain3}


def job(args):
    ctl, params, seed, secs, name = args
    from bridge import Sim
    from dribble_btl import DribbleBtlTask
    t = DribbleBtlTask()
    t.body_kind = "v3"
    t.seed = seed
    try:
        r = Sim(t, params=params, controller=ctl).run(secs)
    except Exception as e:  # a crashed controller scores badly, the search goes on
        return -20.0, {"err": str(e)[:80], "ok": [0, 0, 0, 0], "streak": 0}
    pl = r["pass_log"]
    return OBJ[name](r, params), {"ok": [1 if len(pl) > k and pl[k]["ok"] else 0 for k in range(4)], "streak": r["btl_streak"]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ctl", required=True)
    ap.add_argument("--init", required=True)
    ap.add_argument("--fixed", default="")
    ap.add_argument("--only", required=True)
    ap.add_argument("--bounds", default="")
    ap.add_argument("--seeds", required=True)
    ap.add_argument("--secs", type=float, default=4.2)
    ap.add_argument("--objective", default="p3")
    ap.add_argument("--gens", type=int, default=40)
    ap.add_argument("--pop", type=int, default=0)
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--sigma", type=float, default=0.15)
    ap.add_argument("--cma-seed", type=int, default=7)
    ap.add_argument("--out", required=True)
    ap.add_argument("--log", required=True)
    a = ap.parse_args()
    import practice as pr
    base = load(a.init)
    fixed = parse_over(a.fixed)
    for k, v in fixed.items():
        base.setdefault(k, v)  # the init's own values win, as in search.py
    names = a.only.split(",")
    decl = {t[0]: t for t in pr.describe("dribble_btl_v3", {**fixed, **base})}
    lo = np.array([decl[n][2] for n in names])
    hi = np.array([decl[n][3] for n in names])
    for kv in filter(None, a.bounds.split(",")):
        k, v = kv.split("=")
        l, h = v.split(":")
        i = names.index(k)
        lo[i], hi[i] = float(l), float(h)
    seeds = [int(s) for s in a.seeds.split(",")]

    def to_params(x):
        p = dict(base)
        p.update({n: float(l + (h - l) * v) for n, l, h, v in zip(names, lo, hi, np.clip(x, 0, 1))})
        return p

    x0 = np.array([(base.get(n, decl[n][1]) - l) / (h - l) for n, l, h in zip(names, lo, hi)]).clip(0, 1)
    es = pr.CMA(x0, a.sigma, a.pop or None, seed=a.cma_seed)
    os.makedirs(os.path.dirname(a.log) or ".", exist_ok=True)
    logf = open(a.log, "a")

    def log(msg):
        print(msg, flush=True)
        logf.write(msg + "\n")
        logf.flush()

    log(f"# {time.strftime('%Y-%m-%d %H:%M:%S')} tune {vars(a)}")
    t0 = time.time()
    with get_context("spawn").Pool(a.workers) as pool:
        def score_all(xs):
            jobs = [(a.ctl, to_params(x), sd, a.secs, a.objective) for x in xs for sd in seeds]
            res = pool.map(job, jobs, chunksize=1)
            k = len(seeds)
            out = []
            for i in range(len(xs)):
                rows = res[i * k:(i + 1) * k]
                okc = np.sum([r[1]["ok"] for r in rows], axis=0).tolist()
                out.append((float(np.mean([r[0] for r in rows])), okc, [r[1]["streak"] for r in rows]))
            return out
        base_s = score_all([x0])[0]
        best = (base_s[0], x0.copy(), base_s[1])
        write_params(a.out, to_params(x0), f"tune {a.objective} start {base_s[0]:.3f} ok {base_s[1]}")
        log(f"gen 0 score {base_s[0]:.3f} ok1-4 {base_s[1]} streaks {base_s[2]}")
        for g in range(a.gens):
            xs = es.ask()
            res = score_all(xs)
            sc = [r[0] for r in res]
            es.tell(xs, [s - 10.0 * float(np.sum(np.maximum(0, x - 1) + np.maximum(0, -x))) for s, x in zip(sc, xs)])
            k = int(np.argmax(sc))
            if sc[k] > best[0]:
                best = (sc[k], np.clip(xs[k], 0, 1), res[k][1])
                write_params(a.out, to_params(best[1]), f"tune {a.objective} gen {g + 1} score {best[0]:.3f} ok {best[2]} seeds {seeds}")
            log(f"gen {g + 1} best {best[0]:.3f} {best[2]} gen-best {sc[k]:.3f} {res[k][1]} streaks {res[k][2]} sigma {es.sigma:.3f} ({time.time() - t0:.0f}s)")
    log("# done")


if __name__ == "__main__":
    main()
