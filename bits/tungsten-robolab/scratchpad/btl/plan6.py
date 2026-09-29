"""Cycle planner for slow, high passes: spots 0.45-0.7 m apart, passes that
peak at APEX after the bounce and are caught there, both hands' catch reach
(palm on the ball's far side from the other spot, at the apex height), leg
clearance and a mid-gap crossing both ways, the arrival speed reported."""
import sys, itertools, pickle, numpy as np
sys.path.insert(0, "scratchpad/btl"); sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
import stance as st
from plan import path
from plan3 import stance_model, legs_of, evaluate
from reachmap import ik_real, SEEDS
from armik import tilt
SEEDS2 = SEEDS + ([0.0, 0.3, 0.8, 0.3, 0.0, 0.0], [0.3, 0.3, 1.0, 0.5, 0.3, 0.0], [-0.2, 0.2, 1.2, 0.4, -0.3, 0.0],
                  [0.2, 0.1, -1.0, 0.3, 0.3, 0.0], [0.3, 0.9, 0.3, 1.2, 0, 0], [0.5, 1.2, 0.0, 1.5, 0, 0])
H, ZS, APEX, A, R, G, COR, KR = 0.72, 0.66, 0.75, 1.2, 0.12, 9.81, 0.77, 0.17
VI = np.sqrt(2 * G * (APEX - R)) / COR
VZ0 = -np.sqrt(VI ** 2 - 2 * G * (ZS - R))
TD = (VI + VZ0) / G
TU = COR * VI / G              # bounce to apex
def bounce(S, E):
    S, E = np.array(S), np.array(E); vh = (E - S) / (TD + (1 - KR) * TU)
    return S + vh * TD, float(np.linalg.norm(vh) * (1 - KR))
cache = {}
def reach(side, xy, u, twist, zc, a=A):
    key = (side, round(xy[0], 2), round(xy[1], 2), round(float(np.arctan2(u[1], u[0])), 1), twist, zc, a)
    if key not in cache:
        n = tilt(u, a); zrel = zc + (0.8 - H)
        target = np.array([xy[0] - R * n[0], xy[1] - R * n[1], zrel - R * n[2]])
        cache[key] = min((ik_real(side, target, n, s, 0.55, twist) for s in SEEDS2), key=lambda r: r[0] + 0.1 * r[1])[0]
    return cache[key]
ok = lambda x: x and x[2] and 0.15 < x[0] < 0.85
stance_model(H)
stances = {}
for fx, fy, bx, by in itertools.product((0.35, 0.45, 0.55), (0.12, 0.22, 0.32), (-0.4, -0.55), (-0.1, -0.2, -0.3)):
    front, e1 = st.ik("l", fx, fy); back, e2 = st.ik("r", bx, by, seed=[0.0, 0.2, 0.1, 0.6, -0.59])
    if e1 < 0.035 and e2 < 0.045: stances[(fx, fy, bx, by)] = legs_of(front, back)
print(len(stances), "stances; pass vz0", round(VZ0, 2), "td", round(TD, 3), "tu", round(TU, 3), flush=True)
res = []
diag = []
for twist in (0.3, 0.55, 0.75):
    for S in itertools.product((0.25, 0.35, 0.45, 0.55), (-0.2, -0.3, -0.4)):
        for E in itertools.product((-0.1, 0.0, 0.1, 0.2, 0.3), (0.2, 0.3, 0.4)):
            S_, E_ = np.array(S), np.array(E)
            dist = float(np.linalg.norm(E_ - S_))
            if not 0.45 <= dist <= 0.7:
                continue
            u = (E_ - S_) / dist
            er = reach("r", S_, u, twist, APEX); el = reach("l", E_, -u, twist, APEX)
            # the catch from above: the palm on top, tilted 0.6 rad toward the incoming ball
            cr = reach("r", S_, u, twist, APEX, 0.6); cl = reach("l", E_, -u, twist, APEX, 0.6)
            B1, v1 = bounce(S, E); p1 = path(S, B1, zs=ZS, vz0=VZ0, zc=APEX)[0]
            B2, v2 = bounce(E, S); p2 = path(E, B2, zs=ZS, vz0=VZ0, zc=APEX)[0]
            legs = []
            for key, (caps, chains) in stances.items():
                c1, x1 = evaluate(caps, chains, p1); c2, x2 = evaluate(caps, chains, p2)
                legs.append((round(min(c1, c2), 3), key, x1, x2, bool(ok(x1) and ok(x2))))
            legs.sort(key=lambda l: (-l[4], -l[0]))
            diag.append((twist, S, E, round(dist, 2), round(v1, 2), [round(x * 100, 1) for x in (er, el, cr, cl)], legs[0]))
            if max(er, el) > 0.04:
                continue
            if max(cr, cl) > 0.04:
                continue
            B1, v1 = bounce(S, E); p1 = path(S, B1, zs=ZS, vz0=VZ0, zc=APEX)[0]
            B2, v2 = bounce(E, S); p2 = path(E, B2, zs=ZS, vz0=VZ0, zc=APEX)[0]
            for key, (caps, chains) in stances.items():
                c1, x1 = evaluate(caps, chains, p1)
                if not ok(x1) or c1 < 0.0: continue
                c2, x2 = evaluate(caps, chains, p2)
                if not ok(x2) or c2 < 0.0: continue
                res.append((round(min(c1, c2), 3), twist, key, S, E, round(dist, 2), round(v1, 2), round(er * 100, 1), round(el * 100, 1), x1, x2))
    print("twist", twist, "feasible", len(res), "reach cache", len(cache), flush=True)
res.sort(key=lambda r: -(r[0] - 0.01 * max(r[7], r[8])))
for r in res[:25]: print(r)
pickle.dump((res, diag), open("scratchpad/btl/plan6.pkl", "wb"))
