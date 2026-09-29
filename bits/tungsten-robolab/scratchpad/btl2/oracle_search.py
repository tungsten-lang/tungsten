"""Ceiling study: what release state can the left arm's muscles give the ball, from the recorded arrival?

    .venv/bin/python scratchpad/btl2/oracle_search.py --seed 716 --t-snap 2.0 --window 0.40 --gens 300 --pop 80 \
        --muscles left_arm --out scratchpad/btl2/runs/oracle_716.npz [--vz-only]

The controller is run once (A4, `record`); from the snapshot at t-snap every activation of the chosen muscle set is
replaced by a piecewise-linear program (knots every `--dk` ticks of 5 ms, values in [0, 1]) that CMA-ES searches;
all other muscles replay the recording. The score is computed from the physics trace (see `evaluate`).
"""
import argparse
import os
import sys
import time

import numpy as np

sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
sys.path.insert(0, "scratchpad/btl2")
import oracle_lib as O  # noqa: E402
from common import load  # noqa: E402

G = 9.81
GATE = np.array([0.22, 0.02])   # where the passes cross the gate on the floor (A4's return bounces near here)


def leg_point(chain, z):
    for a, b in zip(chain[:-1], chain[1:]):
        lo, hi = (a[2], b[2]) if a[2] < b[2] else (b[2], a[2])
        if lo <= z <= hi and hi - lo > 1e-9:
            f = (z - a[2]) / (b[2] - a[2])
            return (a + f * (b - a))[:2]
    if z >= max(c[2] for c in chain):
        return np.array(chain[0][:2])
    return np.array(chain[-1][:2])


def gate_crossings(out, start):
    """The task's gate rule replayed on the trace from tick `start`: crossings of the segment joining the two legs' axes
    at the ball's height, strictly between the legs (0 < u < 1), ball top below the crotch, moving across (> 0.3 m/s)."""
    pos, vel, legs = out["pos"], out["vel"], out["legs"]
    found = []
    prev = None
    for i in range(start, len(pos)):
        p, v = pos[i], vel[i]
        cl, cr = legs[i, 0], legs[i, 1]
        z = float(p[2])
        pl, pr = leg_point(cl, z), leg_point(cr, z)
        g = pr - pl
        rel = p[:2] - pl
        s = g[0] * rel[1] - g[1] * rel[0]
        pv, prev = prev, s
        if pv is None or (s > 0) == (pv > 0):
            continue
        gg = float(g @ g)
        if gg < 1e-6:
            continue
        u = float(rel @ g) / gg
        crotch = min(cl[0][2], cr[0][2]) - 0.06
        normal = np.array([-g[1], g[0]]) / np.sqrt(gg)
        across = float(np.dot(v[:2], normal)) * (1.0 if s > 0 else -1.0)
        found.append((i, u, z, across, bool(0.0 < u < 1.0 and z + 0.12 < crotch and across > 0.3)))
    return found


def floor_gate_distance(out, i, x, y):
    a = out["legs"][i, 0, 2][:2]
    b = out["legs"][i, 1, 2][:2]
    p = np.array([x, y])
    t = float(np.clip((p - a) @ (b - a) / max(float((b - a) @ (b - a)), 1e-9), 0.0, 1.0))
    return float(np.linalg.norm(p - (a + t * (b - a))))


def muscle_set(names, which):
    idx = []
    for i, n in enumerate(names):
        if which == "left_arm" and n.startswith("l_") and any(k in n for k in ("shoulder", "elbow", "wrist", "finger")):
            idx.append(i)
        elif which == "left_arm_trunk" and ((n.startswith("l_") and any(k in n for k in ("shoulder", "elbow", "wrist", "finger"))) or n.startswith("spine")):
            idx.append(i)
        elif which == "left_arm_nofinger" and n.startswith("l_") and any(k in n for k in ("shoulder", "elbow", "wrist")):
            idx.append(i)
        elif which == "right_arm" and n.startswith("r_") and any(k in n for k in ("shoulder", "elbow", "wrist", "finger")):
            idx.append(i)
    return idx


RIGHT_TARGET = np.array([0.50, -0.26])   # where the right hand strikes the return (A4's successful returns)
LEFT_TARGET = np.array([-0.12, 0.36])    # where the left hand meets pass 1 (A4: rising through z 0.62)


ARR = {"pos_dz": 0.04, "vel_dz": 0.25, "target": None, "vt": None, "pre": True}   # arrival shaping (set by the searches)


def evaluate(out, mode="full", who="l", arrival=True):
    """Score (lower is better) and a summary of one replayed trace of the left hand's return: the ball must be touched
    by the left hand; its release is the last tick of left contact before the next floor bounce; then it must cross the
    leg gate (the task's rule), touch no leg, and rise toward the right hand's strike zone with energy."""
    pos, vel, cf = out["pos"], out["vel"], out["cf"]
    n = len(pos)
    pc, rc = (0, 1) if who == "l" else (1, 0)
    target = RIGHT_TARGET if who == "l" else LEFT_TARGET
    touch = np.nonzero(cf[:, pc] > 0.3)[0]
    if len(touch) == 0:
        # a miss: guided by how close the palm came to the ball
        si = 0 if who == "l" else 1
        dmin = float(np.min(np.linalg.norm(out["palm"][:, si] - pos, axis=1)))
        return 12.0 + 30.0 * max(0.0, dmin - 0.15), {"touch": False}
    first = touch[0]
    fl = np.nonzero(cf[first:, 2] > 0.2)[0]
    if len(fl) == 0:
        return 20.0, {"touch": True, "bounced": False}
    b = first + fl[0]
    seg = touch[touch < b]
    rel = seg[-1] if len(seg) else first
    p, v = pos[rel], vel[rel]
    vh = float(np.hypot(v[0], v[1]))
    s = {"touch": True, "bounced": True, "rel_t": out["t0"] + (rel + 1) * 0.005, "p": p.copy(), "v": v.copy(), "vh": vh}
    if mode == "vz":
        return -(-v[2]) + 0.3 * abs(vh - 1.6), s
    # the rise after the bounce: to the first right-hand touch, z 0.60 rising, or the end of the trace
    end = n - 1
    for i in range(b + 2, n):
        if cf[i, rc] > 0.3 or (vel[i, 2] > 0 and pos[i, 2] >= 0.60) or (vel[i, 2] < 0 and pos[i, 2] > 0.3 and i > b + 12):
            end = i
            break
    pa = pos[end]
    va = vel[end]
    vpost = vel[min(b + 3, n - 1)]     # just after the bounce
    apex = pos[min(b + 3, n - 1), 2] + max(vpost[2], 0.0) ** 2 / (2 * G)
    bx, by = pos[b, 0], pos[b, 1]
    bgd = floor_gate_distance(out, b, bx, by)
    cross = [c for c in gate_crossings(out, rel) if c[0] <= end]
    valid = [c for c in cross if c[4]]
    body = int(np.sum(cf[rel + 1:end + 1, 3] > 0.3))
    # the incoming ball must not touch the arm or the body before the palm does (that fails the previous pass)
    if ARR["pre"]:
        pre = int(np.sum(cf[:first, 3] > 0.3)) + int(out["prehit"][first] > 0)
        body += pre
    s.update({"bounce": (float(bx), float(by)), "bgd": bgd, "apex": float(apex), "arrive": pa[:2].copy(), "arrive_z": float(pa[2]),
              "gate": len(valid), "body": body, "va": va.copy()})
    J = 0.0
    J += 3.0 * (0 if valid else 1)
    J += 2.0 * max(0.0, bgd - 0.10)
    J += 5.0 * max(0.0, 0.68 - apex)
    if arrival:
        tg = target if ARR["target"] is None else np.array(ARR["target"])
        J += ARR.get("w_pos", 2.0) * max(0.0, float(np.hypot(*(pa[:2] - tg))) - ARR["pos_dz"])
        vt = np.array([1.5, -1.5]) if who == "l" else np.array([-1.5, 1.5])       # pass 1's arrival at the left hand, mirrored
        if ARR["vt"] is not None:
            vt = np.array(ARR["vt"])
        J += ARR.get("w_vel", 0.6) * max(0.0, float(np.hypot(*(va[:2] - vt))) - ARR["vel_dz"])
    J += (3.0 + 0.5 * min(body, 5)) if body > 0 else 0.0          # a leg hit fails the pass
    return J, s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=716)
    ap.add_argument("--params", default="params/dribble_btl_a4.txt")
    ap.add_argument("--ctl", default="bin/challengers/btl2-b1")
    ap.add_argument("--t-snap", type=float, default=2.0)
    ap.add_argument("--window", type=float, default=0.40, help="length of the searched program (s)")
    ap.add_argument("--eval", type=float, default=0.80, help="length of the replayed trace (s)")
    ap.add_argument("--dk", type=int, default=5)
    ap.add_argument("--gens", type=int, default=300)
    ap.add_argument("--pop", type=int, default=80)
    ap.add_argument("--sigma", type=float, default=0.15)
    ap.add_argument("--muscles", default="left_arm")
    ap.add_argument("--hand", default="l")
    ap.add_argument("--mode", default="full")
    ap.add_argument("--cma-seed", type=int, default=3)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    import practice as pr
    params = load(a.params)
    rec = O.record(a.seed, params, a.ctl, a.t_snap, a.t_snap + a.eval + 0.05)
    rp = O.Replay(rec)
    k0 = rec["k0"]
    nprog = int(round(a.window / 0.005))
    n = int(round(a.eval / 0.005))
    idx = muscle_set(rec["names"], a.muscles)
    kt = np.arange(0, nprog + 1, a.dk)
    K = len(kt)
    print(f"muscles {len(idx)} knots {K} dims {len(idx) * K} ticks {n}", flush=True)
    base = rec["acts"][k0:k0 + n + 1]

    def program(x):
        X = np.clip(x.reshape(len(idx), K), 0.0, 1.0)
        ov = {}
        tt = np.arange(n)
        for r, mi in enumerate(idx):
            arr = base[:n, mi].copy()
            arr[:nprog + 1] = np.interp(np.arange(nprog + 1), kt, X[r])
            ov[mi] = arr
        return ov

    def f(x):
        out = rp.run(program(x), ticks=n)
        return evaluate(out, a.mode, a.hand)

    # start from the recording sampled at the knots (smoothed over +-2 ticks)
    x0 = np.zeros((len(idx), K))
    for r, mi in enumerate(idx):
        for j, k in enumerate(kt):
            lo, hi = max(0, k - 2), min(len(base), k + 3)
            x0[r, j] = base[lo:hi, mi].mean()
    x0 = x0.reshape(-1)
    s0, sm0 = f(x0)
    print("start score", round(s0, 3), {k: (np.round(v, 2).tolist() if hasattr(v, "shape") else (round(float(v), 3) if isinstance(v, (float, np.floating)) else v)) for k, v in sm0.items()}, flush=True)
    es = pr.CMA(x0, a.sigma, a.pop, seed=a.cma_seed)
    best = (s0, x0.copy(), sm0)
    t0 = time.time()
    for g in range(a.gens):
        xs = es.ask()
        res = [f(x) for x in xs]
        sc = [r[0] + 5.0 * float(np.sum(np.maximum(0, x - 1) + np.maximum(0, -x))) / len(x) * 0 for r, x in zip(res, xs)]
        es.tell(xs, [-s for s in sc])
        k = int(np.argmin(sc))
        if sc[k] < best[0]:
            best = (sc[k], xs[k].copy(), res[k][1])
        if g % 10 == 0 or g == a.gens - 1:
            sm = best[2]
            print(f"gen {g} best {best[0]:.3f} v {np.round(sm.get('v', np.zeros(3)), 2).tolist()} vh {sm.get('vh', 0):.2f} apex {sm.get('apex', 0):.2f} bounce {np.round(sm.get('bounce', (0, 0)), 2).tolist()} bgd {sm.get('bgd', 0):.2f} gate {sm.get('gate')} arrive {np.round(sm.get('arrive', (0, 0)), 2).tolist()} z {sm.get('arrive_z', 0):.2f} body {sm.get('body')} "
                  f"sigma {es.sigma:.3f} ({time.time() - t0:.0f}s)", flush=True)
            np.savez(a.out, x=best[1], idx=np.array(idx), kt=kt, seed=a.seed, t_snap=a.t_snap, score=best[0])
    print("done")


if __name__ == "__main__":
    main()
