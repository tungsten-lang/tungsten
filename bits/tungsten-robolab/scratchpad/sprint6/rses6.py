"""rses6.py (sprint 6, agent S6): (1+lambda)-ES for the AT-RISK START GEAR (rk_ tunables of run_gearz.w) on a POOL OF AT-RISK STARTS, labelled beyond-human body.

Why it can work where S5's fresh-seed ES could not: S5's draws were random seeds, of which 7 % are at risk, so the early backward collapse (the biggest hazard) was
one fall per draw; here every candidate runs on 150-300 starts that all begin with the COM behind the ankles (COM0 < rk_thr), 55 % of which fall under F1, so a
change of 10 falls is a many-sigma signal. Every candidate is judged on the SAME seeds (common random numbers); the best offspring of a generation must also beat
the incumbent on a second, separate validation pool before it is accepted. Starts that are not at risk never read an rk_ value, so they are bit-identical to F1.

    .venv/bin/python scratchpad/sprint6/rses6.py NAME BASE.txt --ctl bin/challengers/run_gearz-s6f --train out/sprint6/ar_train.txt --valid out/sprint6/ar_valid.txt \\
        --only "rk_*" --exclude "rk_thr" --seconds 6 --k 240 --k2 200 --lam 8 --workers 6

cost of a start = 0 if it survives the horizon (+ vw x max(0, 1 - v_end / vref): a start that survives by standing still is not a gain), else 1 + (T - t_fall) / T.
Outputs: out/sprint6/NAME.log (one JSON line per generation), scratchpad/sprint6/NAME_best.txt (the incumbent: a full params file), NAME_g<N>.txt (copies).
"""
import argparse
import json
import math
import multiprocessing as mp
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
os.environ["ROBOLAB_CALIB"] = "v4"
os.environ["ROBOLAB_PROFILE"] = "beyond"
os.environ["ROBOLAB_PROFILE_PARTS"] = "strength,speed,tendon,activation"
sys.path.insert(0, os.path.join(ROOT, "playground"))

import numpy as np  # noqa: E402


class Rec:
    def __init__(self):
        self.vf = 0.0
        self.last_t = 0.0
        self.pid = None

    def maybe_capture(self, sim):
        d = sim.d
        if self.pid is None:
            self.pid = sim.m.body("pelvis").id
        t = float(d.time)
        dt = max(t - self.last_t, 1e-6) if self.last_t else 0.004
        self.last_t = t
        k = dt / (0.15 + dt)
        self.vf += (float(d.subtree_linvel[self.pid][0]) - self.vf) * k


def job(args):
    """one rollout of run_v4 (labelled beyond body): returns (fell, time, v_end)"""
    from practice import load_task
    from bridge import Sim
    params, ctl, seed, secs = args
    task = load_task("run_v4")
    task.seed = seed
    rec = Rec()
    try:
        m = Sim(task, params=dict(params), controller=ctl).run(secs, recorder=rec)
    except Exception:
        return (True, 0.0, 0.0)
    return (bool(m.get("fell")), float(m.get("time") or 0.0), rec.vf)


def cost_of(res, secs, vref, vw):
    fell, t, v = res
    if fell:
        return 1.0 + (secs - t) / secs
    return vw * max(0.0, 1.0 - v / vref)


def parse_seed_file(p):
    return [int(x) for x in open(p).read().strip().split(",") if x.strip()]


def write_params(path, rep, x, note):
    p = rep.decode(x)
    with open(path, "w") as f:
        f.write(f"# robolab params (sprint 6, rses6.py): {note}\n# \n")
        for k in sorted(p):
            if not k.startswith("__"):
                f.write(f"{k} {float(p[k])!r}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("init")
    ap.add_argument("--ctl", required=True)
    ap.add_argument("--train", required=True)
    ap.add_argument("--valid", required=True)
    ap.add_argument("--only", default="rk_*")
    ap.add_argument("--exclude", default="rk_thr")
    ap.add_argument("--box", default="", help="name=lo:hi,... overrides of the declared boxes")
    ap.add_argument("--seconds", type=float, default=6.0)
    ap.add_argument("--k", type=int, default=240)
    ap.add_argument("--k2", type=int, default=200)
    ap.add_argument("--lam", type=int, default=8)
    ap.add_argument("--mut", type=float, default=5.0)
    ap.add_argument("--sigma", type=float, default=0.08)
    ap.add_argument("--vref", type=float, default=5.5)
    ap.add_argument("--vw", type=float, default=0.3)
    ap.add_argument("--hard", type=float, default=0.25)
    ap.add_argument("--gens", type=int, default=100000)
    ap.add_argument("--max-minutes", type=float, default=600.0)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args()
    from search import BoxRep, describe, parse_list
    from practice import read_params
    ctl = os.path.abspath(a.ctl)
    os.environ["ROBOLAB_CONTROLLER"] = ctl
    init = read_params(a.init)
    tun = describe("run_v4", init)
    if a.box:
        box = {kv.split("=")[0]: tuple(float(x) for x in kv.split("=")[1].split(":")) for kv in a.box.split(",") if kv}
        unknown = sorted(set(box) - {t[0] for t in tun})
        if unknown:
            raise SystemExit("--box names no tunable: " + ", ".join(unknown))
        tun = [(t[0], t[1], *box.get(t[0], (t[2], t[3]))) for t in tun]
    widened, tun2 = [], []
    for (nm, dflt, lo, hi) in tun:
        v = init.get(nm, dflt)
        if v < lo or v > hi:
            pad = 0.1 * (hi - lo)
            widened.append(f"{nm}={v:.4g} (box {lo:g}:{hi:g})")
            lo, hi = min(lo, v - pad), max(hi, v + pad)
        tun2.append((nm, dflt, lo, hi))
    tun = tun2
    if widened:
        print("boxes widened:", "; ".join(widened), flush=True)
    rep = BoxRep.from_tunables(tun, parse_list(a.only), parse_list(a.exclude), init, {})
    train, valid = parse_seed_file(a.train), parse_seed_file(a.valid)
    rng = np.random.default_rng(a.seed)
    logp = os.path.join(ROOT, "out", "sprint6", a.name + ".log")
    bestp = os.path.join(HERE, a.name + "_best.txt")
    log = open(logp, "a")
    t0 = time.time()
    print(f"rses6 {a.name}: {rep.n} tunables, train pool {len(train)}, valid pool {len(valid)}, K {a.k}, K2 {a.k2}, lam {a.lam}, sigma {a.sigma}, {a.seconds} s, "
          f"workers {a.workers}, controller {ctl}", flush=True)
    x = rep.x0.copy()
    write_params(bestp, rep, x, f"start = {a.init}")
    q = min(1.0, a.mut / rep.n)
    n_acc, hard = 0, []

    def evaluate(pool, X, seeds):
        jobs = [(rep.decode(xx), ctl, s, a.seconds) for xx in X for s in seeds]
        res = pool.map(job, jobs, chunksize=1)
        n, k = len(X), len(seeds)
        C = np.array([cost_of(r, a.seconds, a.vref, a.vw) for r in res]).reshape(n, k)
        F = np.array([r[0] for r in res]).reshape(n, k)
        return C, F

    with mp.get_context("spawn").Pool(a.workers) as pool:
        gen = 0
        while gen < a.gens and (time.time() - t0) / 60.0 < a.max_minutes:
            gen += 1
            tg = time.time()
            nh = min(int(round(a.hard * a.k)), len(hard))
            hs = [int(s) for s in rng.choice(hard, nh, replace=False)] if nh else []
            rest = [s for s in train if s not in set(hs)]
            A = hs + [int(s) for s in rng.choice(rest, a.k - len(hs), replace=False)]
            X = [x.copy()]
            for _ in range(a.lam):
                mask = rng.random(rep.n) < q
                if not mask.any():
                    mask[rng.integers(rep.n)] = True
                X.append(np.clip(x + mask * a.sigma * rng.standard_normal(rep.n), 0.0, 1.0))
            X = np.array(X)
            C, F = evaluate(pool, X, A)
            m = C.mean(axis=1)
            j = 1 + int(np.argmin(m[1:]))
            rec = {"gen": gen, "inc_cost": round(float(m[0]), 4), "inc_falls": int(F[0].sum()), "best_cost": round(float(m[j]), 4), "best_falls": int(F[j].sum()),
                   "med_cost": round(float(np.median(m[1:])), 4), "k": len(A)}
            for s, f in zip(A, F[0]):
                if f and s not in hard:
                    hard.append(s)
            hard = hard[-300:]
            accepted = False
            if m[j] < m[0]:
                B = [int(s) for s in rng.choice(valid, min(a.k2, len(valid)), replace=False)]
                CB, FB = evaluate(pool, np.array([x, X[j]]), B)
                mb = CB.mean(axis=1)
                rec.update({"inc_costB": round(float(mb[0]), 4), "inc_fallsB": int(FB[0].sum()), "best_costB": round(float(mb[1]), 4), "best_fallsB": int(FB[1].sum()),
                            "kB": len(B)})
                if mb[1] < mb[0]:
                    accepted = True
                    x = X[j].copy()
                    n_acc += 1
                    write_params(bestp, rep, x, f"{a.name} incumbent after {n_acc} acceptances (generation {gen})")
                    write_params(os.path.join(HERE, f"{a.name}_g{gen}.txt"), rep, x, f"{a.name} incumbent at generation {gen}")
            rec.update({"accepted": accepted, "n_acc": n_acc, "gen_s": round(time.time() - tg, 1), "wall_min": round((time.time() - t0) / 60.0, 1)})
            log.write(json.dumps(rec) + "\n")
            log.flush()
            print(" ".join(f"{k}={v}" for k, v in rec.items()), flush=True)
    print("done", flush=True)


if __name__ == "__main__":
    main()
