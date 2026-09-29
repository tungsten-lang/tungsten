"""Joint planner: reachable palm contacts (arm IK) x leg clearance (both ways)."""
import sys, numpy as np, itertools, pickle, os
sys.path.insert(0, "scratchpad/btl")
import stance as st
from plan import path, evaluate
from check import bounce_for
from reachmap import ik_real, SEEDS
from armik import tilt
SEEDS2 = SEEDS + ([0.0, 0.3, 0.8, 0.3, 0.0, 0.0], [0.3, 0.3, 1.0, 0.5, 0.3, 0.0], [-0.2, 0.2, 1.2, 0.4, -0.3, 0.0], [0.2, 0.1, -1.0, 0.3, 0.3, 0.0])
cache = {}
def reach(side, xy, u, a, zc):
    key = (side, round(xy[0], 2), round(xy[1], 2), round(float(np.arctan2(u[1], u[0])), 1), round(a, 1), zc)
    if key not in cache:
        n = tilt(u, a); target = np.array([xy[0] - 0.12 * n[0], xy[1] - 0.12 * n[1], zc - 0.12 * n[2]])
        cache[key] = min((ik_real(side, target, n, s, 0.55, 0.0) for s in SEEDS2), key=lambda r: r[0] + 0.1 * r[1])[0]
    return cache[key]
stances = {}
for fx, fy, bx, by in itertools.product((0.3, 0.4, 0.47), (0.12, 0.2, 0.28), (-0.25, -0.4), (-0.15, -0.3)):
    front, e1 = st.ik("l", fx, fy); back, e2 = st.ik("r", bx, by, seed=[0.0, 0.2, 0.1, 0.6, -0.59])
    if e1 < 0.035 and e2 < 0.045: stances[(fx, fy, bx, by)] = (front, back)
print(len(stances), "stances", flush=True)
res = []
for zc in (0.72, 0.82):
    for S in itertools.product((0.1, 0.2, 0.3, 0.4), (-0.3, -0.4, -0.5)):
        for E in itertools.product((0.0, 0.1, 0.2, 0.3, 0.4), (0.3, 0.4, 0.5)):
            S_, E_ = np.array(S), np.array(E)
            B, vh = bounce_for(S, E, zs=zc, zc=zc)
            a = float(np.arctan2(np.linalg.norm(vh), 4.0))
            u = (E_ - S_) / np.linalg.norm(E_ - S_)
            er, el = reach("r", S_, u, a, zc), reach("l", E_, -u, a, zc)
            if max(er, el) > 0.03:
                continue
            for key, (front, back) in stances.items():
                c1, x1 = evaluate(front, back, path(S, B, zs=zc, zc=zc)[0])
                ok = lambda x: x and x[2] and 0.1 < x[0] < 0.9
                if not ok(x1): continue
                B2, _ = bounce_for(E, S, zs=zc, zc=zc)
                c2, x2 = evaluate(front, back, path(E, B2, zs=zc, zc=zc)[0])
                if not ok(x2): continue
                res.append((round(min(c1, c2), 3), zc, key, S, E, round(a, 2), round(er * 100, 1), round(el * 100, 1), B.round(2), x1, x2))
    print("zc", zc, "done", len(res), "ik cache", len(cache), flush=True)
res.sort(key=lambda r: -r[0])
for r in res[:25]: print(r)
pickle.dump(res, open("scratchpad/btl/plan2.pkl", "wb"))
