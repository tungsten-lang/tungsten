#!/usr/bin/env python3
"""Slice the ball's path and hit it at every position (Erik, 3 Oct 2026), with the impact model of playground/tt_impact.py (E 0.95, MU 0.012, ALPHA 0.9: T3's fit).

LEVEL 1, the champion's OWN stroke. For every serve of sets A + B (the plain champion's logs, 10 ms ticks), take the pad's normal and world velocity at tick j and the ball's free-path
state at tick j and ask: if the pad had been at the ball at tick j, would the model return it legally (first touch on the opponent's half, over the net)? The set of such ticks is the
LEGAL WINDOW of the stroke in time. Compare it with the tick the contact really happened (or, for a miss, the tick of the closest approach).
LEVEL 2, an IDEAL pad. For slice j and a grid of pad orientations (pitch, yaw) and pad speeds along its normal, the share of legal returns and the best landing margin along the path.
Read-only. A file with a __main__ guard.   .venv-myo/bin/python scratchpad/tt5/slice_model.py       from bits/tungsten-robolab"""
import json
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)
sys.path.insert(0, os.path.join(ROOT, "playground"))
sys.path.insert(0, os.path.join(ROOT, "scratchpad", "tt3"))
import tt_impact as ti  # noqa: E402

E, MU, ALPHA = 0.95, 0.012, 0.9
G = 9.81


def margin(p0, v):
    """landing margin (m) of a ball leaving p0 with velocity v (>0: legal return with that clearance), -1 when it does not even go toward the opponent"""
    x0, y0, z0 = p0
    vx, vy, vz = v[..., 0], v[..., 1], v[..., 2]
    with np.errstate(divide="ignore", invalid="ignore"):
        t1 = -x0 / vx
        zn = z0 + vz * t1 - 0.5 * G * t1 * t1
        disc = vz * vz + 2 * G * (z0 - ti.Z_C)
        t2 = (vz + np.sqrt(np.maximum(disc, 0.0))) / G
        xl = x0 + vx * t2
        yl = y0 + vy * t2
        m = np.minimum.reduce([zn - (ti.NET_TOP + ti.R_BALL), xl - ti.X_FAR, -xl, ti.Y_HI - yl, yl - ti.Y_LO])
    ok = (vx < -0.3) & (t1 > 0) & (disc > 0)
    return np.where(ok, m, -1.0)


def free_path(L, k, t_extra=0.2, dt=0.01):
    """ball states (t, p, v) at 10 ms ticks: the log's own until the last tick before the contact (the whole log for a miss), then ballistic."""
    t, p, v = L[:, 0], L[:, 1:4], L[:, 4:7]
    end = len(L) if k < 0 else max(k, 1)
    T, P, V = list(t[:end]), list(p[:end]), list(v[:end])
    if k >= 0:
        pp, vv, tt = p[end - 1].copy(), v[end - 1].copy(), t[end - 1]
        for _ in range(int(round(t_extra / dt))):
            pp = pp + vv * dt - 0.5 * np.array([0, 0, G]) * dt * dt
            vv = vv + np.array([0, 0, -G]) * dt
            tt += dt
            T.append(tt); P.append(pp.copy()); V.append(vv.copy())
    return np.array(T), np.array(P), np.array(V)


def pad_state(L):
    t, pad, nrm = L[:, 0], L[:, 7:10], L[:, 13:16]
    n = nrm / np.linalg.norm(nrm, axis=1, keepdims=True)
    vp = np.gradient(pad, t, axis=0)
    return n, vp


def level1(rows):
    out = []
    for sd in sorted(rows):
        z = np.load(f"out/tt3/logs_o0/{sd}.npz", allow_pickle=True)
        L, k = z["L"], int(z["contact"])
        r = rows[sd]
        cls = "solved" if r.get("solved", 0) > 0 else ("touched" if k >= 0 else "miss")
        T, P, V = free_path(L, k)
        n, vp = pad_state(L)
        nn = len(T)
        # pad state at slice ticks: for ticks beyond the log keep the last state
        idx = np.minimum(np.arange(nn), len(L) - 1)
        mg = np.array([float(margin(P[j], ti.impact(V[j], ALPHA * vp[idx[j]], n[idx[j]], E, MU))) for j in range(nn)])
        # restrict to the reachable part of the path: ball x >= 1.0 (beyond the table's own-half bounce), height above the floor
        reach = (P[:, 0] >= 1.0) & (P[:, 2] > 0.4)
        legal = (mg > 0) & reach
        kc = (k - 1) if k >= 1 else int(np.argmin(np.linalg.norm(L[:, 1:4] - L[:, 7:10], axis=1)))
        kc = min(kc, nn - 1)
        w = np.nonzero(legal)[0]
        if len(w):
            off = (T[w] - T[kc])
            near = off[np.argmin(np.abs(off))]
            width = int(legal.sum())
        else:
            near, width = None, 0
        out.append(dict(seed=sd, cls=cls, k=k, kc=kc, window_ticks=width, nearest_legal_offset_s=(float(near) if near is not None else None),
                        legal_at_contact=bool(legal[kc]) if kc < nn else False, margin_at_contact=float(mg[kc])))
    return out


def summarize1(out):
    print("LEVEL 1: the champion's own pad state (normal, velocity) at each tick, the ball's free-path state at that tick: 'if the pad had been at the ball then, is the return legal?'")
    for cls in ("solved", "touched", "miss"):
        o = [x for x in out if x["cls"] == cls]
        if not o:
            continue
        nonempty = [x for x in o if x["window_ticks"] > 0]
        at_c = [x for x in o if x["legal_at_contact"]]
        offs = np.array([abs(x["nearest_legal_offset_s"]) for x in nonempty])
        print(f"  {cls:8s} n {len(o):3d}: the model calls the contact tick legal on {len(at_c):3d}; a legal tick EXISTS somewhere on the reachable path on {len(nonempty):3d};"
              + (f" nearest legal tick from the contact tick: median {1000 * np.median(offs):.0f} ms, p75 {1000 * np.percentile(offs, 75):.0f}, p90 {1000 * np.percentile(offs, 90):.0f}; window width median {np.median([x['window_ticks'] for x in nonempty]) * 10:.0f} ms" if len(nonempty) else ""))
    t = [x for x in out if x["cls"] == "touched"]
    for tol in (0.01, 0.02, 0.03, 0.05, 0.08, 0.12, 0.2):
        c = sum(1 for x in t if x["nearest_legal_offset_s"] is not None and abs(x["nearest_legal_offset_s"]) <= tol)
        print(f"    touched-but-not-returned: contact moved by at most {int(tol * 1000):3d} ms would give a legal return (model, pad state of that tick, perfect position) on {c:3d} of {len(t)}")


def level2(rows, seeds):
    pit = np.arange(-30.0, 60.1, 2.0)
    yaw = np.arange(-30.0, 30.1, 2.0)
    print("LEVEL 2: an IDEAL pad at each slice of the ball's path (the share of the pitch x yaw grid, 91 x 31, that returns legally; pad speed along its normal 0 / +1 / +2 m/s toward -x)")
    res = {}
    for sd in seeds:
        z = np.load(f"out/tt3/logs_o0/{sd}.npz", allow_pickle=True)
        L, k = z["L"], int(z["contact"])
        T, P, V = free_path(L, k)
        print(f"  seed {sd} ({'solved' if rows[sd].get('solved', 0) > 0 else ('touched' if k >= 0 else 'MISS')}, contact tick {k}):  tick  t    ball x y z      |v|   legal share v=0 / 1 / 2 m/s   best margin v=0 (pitch, yaw)")
        nrm = ti.normals_grid(pit, yaw)
        for j in range(len(T)):
            if not (P[j, 0] >= 1.0 and P[j, 2] > 0.4) or j % 3:
                continue
            shares, best = [], None
            for sp in (0.0, 1.0, 2.0):
                vp = np.array([-sp, 0.0, 0.0])
                v = ti.impact(V[j], ALPHA * vp, nrm, E, MU)
                m = margin(P[j], v)
                shares.append(float((m > 0).mean()))
                if sp == 0.0:
                    a, b = np.unravel_index(int(np.argmax(m)), m.shape)
                    best = (float(m[a, b]), float(pit[a]), float(yaw[b]))
            print(f"           {j:4d} {T[j]:.2f}  {P[j, 0]:.2f} {P[j, 1]:+.2f} {P[j, 2]:.2f}  {np.linalg.norm(V[j]):.2f}      {100 * shares[0]:5.1f} / {100 * shares[1]:5.1f} / {100 * shares[2]:5.1f} %       {best[0]:+.2f} ({best[1]:.0f}, {best[2]:.0f})")
        res[sd] = True
    return res


def main():
    rows = {}
    for s in ("A", "B"):
        for l in open(f"out/tt3/o0_{s}.jsonl"):
            r = json.loads(l)
            rows[r["seed"]] = r
    out = level1(rows)
    json.dump(out, open("out/tt5/level1.json", "w"), indent=1)
    summarize1(out)
    miss = [x["seed"] for x in out if x["cls"] == "miss"]
    pick = miss[:2]
    level2(rows, pick)


if __name__ == "__main__":
    main()
