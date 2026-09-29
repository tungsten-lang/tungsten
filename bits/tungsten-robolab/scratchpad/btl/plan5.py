"""Cycle planner at pelvis 0.72: stance x twist x spots. A cycle is feasible when
both passes clear the legs and cross the gate between them, and each hand can put
its palm on the ball's far side from the other spot (the catch of the incoming
pass and the push of the outgoing one share that pose), from the arm IK."""
import sys, os, itertools, pickle, numpy as np
sys.path.insert(0, "scratchpad/btl"); sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
import stance as st
from plan import path
from plan3 import stance_model, legs_of, evaluate
from check import bounce_for
from reachmap import ik_real, SEEDS
from armik import tilt
SEEDS2 = SEEDS + ([0.0, 0.3, 0.8, 0.3, 0.0, 0.0], [0.3, 0.3, 1.0, 0.5, 0.3, 0.0], [-0.2, 0.2, 1.2, 0.4, -0.3, 0.0],
                  [0.2, 0.1, -1.0, 0.3, 0.3, 0.0], [0.3, 0.9, 0.3, 1.2, 0, 0], [0.5, 1.2, 0.0, 1.5, 0, 0])
H, ZC, A, R = 0.72, 0.66, 1.2, 0.12
cache = {}
def reach(side, xy, u, twist):
    """palm on the ball's side away from direction u (pushing along u), tilted A from down."""
    key = (side, round(xy[0], 2), round(xy[1], 2), round(float(np.arctan2(u[1], u[0])), 1), twist)
    if key not in cache:
        n = tilt(u, A); zrel = ZC + (0.8 - H)
        target = np.array([xy[0] - R * n[0], xy[1] - R * n[1], zrel - R * n[2]])
        cache[key] = min((ik_real(side, target, n, s, 0.55, twist) for s in SEEDS2), key=lambda r: r[0] + 0.1 * r[1])[0]
    return cache[key]
ok = lambda x: x and x[2] and 0.15 < x[0] < 0.85
stance_model(H)
stances = {}
for fx, fy, bx, by in itertools.product((0.35, 0.45), (0.12, 0.22, 0.32), (-0.4, -0.55), (-0.1, -0.2, -0.3)):
    front, e1 = st.ik("l", fx, fy); back, e2 = st.ik("r", bx, by, seed=[0.0, 0.2, 0.1, 0.6, -0.59])
    if e1 < 0.035 and e2 < 0.045: stances[(fx, fy, bx, by)] = legs_of(front, back)
print(len(stances), "stances", flush=True)
res = []
for twist in (0.3, 0.55, 0.75):
    for S in itertools.product((0.25, 0.35, 0.45, 0.55), (-0.3, -0.4, -0.5)):
        for E in itertools.product((-0.1, 0.0, 0.1, 0.2, 0.3), (0.35, 0.45, 0.55)):
            S_, E_ = np.array(S), np.array(E)
            u = (E_ - S_) / np.linalg.norm(E_ - S_)
            er = reach("r", S_, u, twist)    # one spine twist for both arms
            el = reach("l", E_, -u, twist)
            if max(er, el) > 0.04:
                continue
            B1, _ = bounce_for(S, E, zs=ZC, zc=ZC); p1 = path(S, B1, zs=ZC, zc=ZC)[0]
            B2, _ = bounce_for(E, S, zs=ZC, zc=ZC); p2 = path(E, B2, zs=ZC, zc=ZC)[0]
            for key, (caps, chains) in stances.items():
                c1, x1 = evaluate(caps, chains, p1)
                if not ok(x1) or c1 < 0.0: continue
                c2, x2 = evaluate(caps, chains, p2)
                if not ok(x2) or c2 < 0.0: continue
                res.append((round(min(c1, c2), 3), twist, key, S, E, round(er * 100, 1), round(el * 100, 1), x1, x2))
    print("twist", twist, "feasible", len(res), "reach cache", len(cache), flush=True)
res.sort(key=lambda r: -(r[0] - 0.01 * max(r[5], r[6])))
for r in res[:25]: print(r)
pickle.dump(res, open("scratchpad/btl/plan5.pkl", "wb"))
