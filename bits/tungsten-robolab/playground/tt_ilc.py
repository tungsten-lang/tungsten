"""Iterative learning of the table-tennis skill's learned feed-forward map (`lff`), fast path (round 10).

The skill's `lff` adds joint offsets W . phi (phi: the serve's six features, `feat` in the metrics) to the
servo's corrections from the first plan on. The servo's own contribution at the lock (`q_servo`: the integral
and proportional parts) is what the feed-forward still lacked; each iteration runs `k` fresh serves with the
current weights, regresses q_servo on phi by ridge regression and adds `alpha` of the fit to W, so the servo's
work is consolidated into the open-loop command (playground/tasks/myo_tt.py `lff_learn`, on the fast path).

    .venv-myo/bin/python playground/tt_ilc.py --params P --controller C --side 1 --iters 8 --k 90 \
        --out params/x.txt [--resume]

Every `--hold_every` iterations the current weights are scored on `--held` fixed held-out serves. The params file
written after each iteration carries the weights (lff, lff_side, lff0..lff47); the log (JSON lines) has each
iteration's fit statistics and held-out score.
"""

import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import tt_fast  # noqa: E402


def write_params(path, params, header):
    with open(path, "w") as f:
        f.write(f"# {header}\n")
        for k in sorted(params):
            f.write(f"{k} {float(params[k])!r}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--params", required=True)
    ap.add_argument("--controller", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--side", type=int, default=1, help="1 forehand, 2 backhand (lff_side)")
    ap.add_argument("--iters", type=int, default=8)
    ap.add_argument("--k", type=int, default=90, help="fresh serves per iteration")
    ap.add_argument("--alpha", type=float, default=0.6)
    ap.add_argument("--ridge", type=float, default=0.02)
    ap.add_argument("--seed0", type=int, default=730000, help="first training serve (iteration i uses seed0 + i k ...)")
    ap.add_argument("--held0", type=int, default=720000)
    ap.add_argument("--held", type=int, default=120)
    ap.add_argument("--hold_every", type=int, default=2)
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--set", default="")
    ap.add_argument("--resume", action="store_true")
    ap.add_argument("--log")
    a = ap.parse_args()
    os.environ.setdefault("TT_ENV", "P2")
    params = tt_fast.read_params(a.params)
    for kv in filter(None, a.set.split(",")):
        k, v = kv.split("=")
        params[k] = float(v)
    ctl = os.path.abspath(a.controller)
    log = open(a.log or a.out + ".log", "a")
    W = np.zeros((8, 6))
    if a.resume and os.path.exists(a.out):
        p2 = tt_fast.read_params(a.out)
        W = np.array([p2.get(f"lff{i}", 0.0) for i in range(48)]).reshape(8, 6)
    P = dict(params)
    P["lff"] = 1.0
    P["lff_side"] = float(a.side)
    held = list(range(a.held0, a.held0 + a.held))
    pool = tt_fast.pool(a.workers)

    def put(Wm):
        for i in range(48):
            P[f"lff{i}"] = float(np.clip(Wm.flat[i], -3.0, 3.0))

    best = (-1.0, None)
    for it in range(a.iters):
        put(W)
        seeds = list(range(a.seed0 + it * a.k, a.seed0 + (it + 1) * a.k))
        t0 = time.time()
        rows = pool.map(tt_fast.episode, [(dict(P), s, None, ctl) for s in seeds], chunksize=1)
        F, Q = [], []
        for r in rows:
            if "error" in r or r.get("side") != a.side:
                continue
            if r.get("feat") and r.get("q_servo") and abs(r["feat"][5]) < 0.05:
                F.append(r["feat"])
                Q.append(r["q_servo"])
        side_rows = [r for r in rows if "error" not in r and r.get("side") == a.side]
        rec = {"it": it + 1, "solved_side": float(np.mean([r.get("solved", 0) for r in side_rows])) if side_rows else None,
               "hit_side": float(np.mean([r.get("hit", 0) for r in side_rows])) if side_rows else None,
               "n_side": len(side_rows), "n_fit": len(F), "wall_s": round(time.time() - t0)}
        if len(F) >= 10:
            F, Q = np.array(F), np.array(Q)
            lam = a.ridge * len(F)
            dW = np.linalg.solve(F.T @ F + lam * np.eye(F.shape[1]), F.T @ Q).T
            rec["servo_rms"] = float(np.sqrt(np.mean(Q ** 2)))
            rec["servo_rms_per_joint"] = [round(float(x), 4) for x in np.sqrt(np.mean(Q ** 2, axis=0))]
            rec["fit_rms"] = float(np.sqrt(np.mean((Q - F @ dW.T) ** 2)))
            W = W + a.alpha * dW
        put(W)
        write_params(a.out, P, f"tt_ilc side {a.side} iteration {it + 1} (lff weights; {a.params})")
        if (it + 1) % a.hold_every == 0 or it + 1 == a.iters:
            hr = pool.map(tt_fast.episode, [(dict(P), s, None, ctl) for s in held], chunksize=1)
            hs = [r for r in hr if "error" not in r and r.get("side") == a.side]
            rec["held_solved_side"] = float(np.mean([r.get("solved", 0) for r in hs])) if hs else None
            rec["held_n_side"] = len(hs)
            rec["held_solved_all"] = float(np.mean([r.get("solved", 0) for r in hr if "error" not in r]))
            if rec["held_solved_side"] is not None and rec["held_solved_side"] > best[0]:
                best = (rec["held_solved_side"], it + 1)
                write_params(a.out + ".best", P, f"tt_ilc best held-out (iteration {it + 1}, side {a.side}, held-out solved {best[0]:.3f})")
        print(json.dumps(rec), flush=True)
        log.write(json.dumps(rec) + "\n")
        log.flush()
    print("best held-out (side)", best)


if __name__ == "__main__":
    main()
