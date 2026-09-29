"""Joint planner over pelvis height: reachable palm contacts x leg clearance both ways."""
import sys, numpy as np, itertools, pickle, os, mujoco
sys.path.insert(0, "scratchpad/btl"); sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
import stance as st
from plan import path, seg_dist, leg_point
from check import bounce_for
from reachmap import ik_real, SEEDS
from armik import tilt
from dribble_v3 import DribbleV3Task
R_ = 0.12
SEEDS2 = SEEDS + ([0.0, 0.3, 0.8, 0.3, 0.0, 0.0], [0.3, 0.3, 1.0, 0.5, 0.3, 0.0], [-0.2, 0.2, 1.2, 0.4, -0.3, 0.0], [0.2, 0.1, -1.0, 0.3, 0.3, 0.0])
cache = {}
def reach(side, xy, u, a, zc, H):
    zrel = round(zc + (0.8 - H), 2)
    key = (side, round(xy[0], 2), round(xy[1], 2), round(float(np.arctan2(u[1], u[0])), 1), round(a, 1), zrel)
    if key not in cache:
        n = tilt(u, a); target = np.array([xy[0] - R_ * n[0], xy[1] - R_ * n[1], zrel - R_ * n[2]])
        cache[key] = min((ik_real(side, target, n, s, 0.55, 0.0) for s in SEEDS2), key=lambda r: r[0] + 0.1 * r[1])[0]
    return cache[key]
def stance_model(H):
    t = DribbleV3Task(); t.pelvis_height = H
    m = mujoco.MjModel.from_xml_string(t.xml(t.builder())); d = mujoco.MjData(m); t.reset(m, d)
    st.m, st.d = m, d
def legs_of(lq, rq):
    caps, chains = [], {}
    for s, q in (("l", lq), ("r", rq)):
        st.fk(s, q); d = st.d
        hip, knee, ank = d.body(f"{s}_thigh").xpos.copy(), d.body(f"{s}_shin").xpos.copy(), d.body(f"{s}_foot").xpos.copy()
        caps += [(hip, knee, 0.06), (knee, ank, 0.045)]
        g = d.geom(f"{s}_foot"); caps.append((g.xpos + g.xmat.reshape(3, 3) @ np.array([-0.1, 0, 0]), g.xpos + g.xmat.reshape(3, 3) @ np.array([0.1, 0, 0]), 0.035))
        chains[s] = [hip, knee, ank]
    return caps, chains
def evaluate(caps, chains, pts):
    clear = min(seg_dist(p, a, b) - R_ - r for p in pts[::2] for (a, b, r) in caps)
    crotch = chains["l"][0][2] - 0.06; cross = None; prev = None
    for p in pts:
        pl, pr = leg_point(chains["l"], p[2]), leg_point(chains["r"], p[2])
        g = pr - pl; rel = p[:2] - pl; s = g[0] * rel[1] - g[1] * rel[0]
        if prev is not None and np.sign(s) != np.sign(prev):
            cross = (round(float(rel @ g / (g @ g)), 2), round(float(p[2]), 2), bool(p[2] + R_ < crotch))
        prev = s
    return clear, cross
ok = lambda x: x and x[2] and 0.1 < x[0] < 0.9
if __name__ == "__main__":
    res = []
    for H in (0.8, 0.72, 0.66):
        stance_model(H)
        reachx = (H * H - 0.0) ** 0.5
        stances = {}
        for fx, fy, bx, by in itertools.product((0.3, 0.4, 0.5, 0.6), (0.12, 0.2, 0.28), (-0.25, -0.4, -0.55), (-0.15, -0.3)):
            front, e1 = st.ik("l", fx, fy); back, e2 = st.ik("r", bx, by, seed=[0.0, 0.2, 0.1, 0.6, -0.59])
            if e1 < 0.035 and e2 < 0.045: stances[(fx, fy, bx, by)] = legs_of(front, back)
        print("H", H, len(stances), "stances", flush=True)
        for zc in (0.62, 0.72):
            for S in itertools.product((0.1, 0.2, 0.3, 0.4), (-0.3, -0.4, -0.5)):
                for E in itertools.product((0.0, 0.1, 0.2, 0.3, 0.4), (0.3, 0.4, 0.5)):
                    S_, E_ = np.array(S), np.array(E)
                    B, vh = bounce_for(S, E, zs=zc, zc=zc)
                    a0 = float(np.arctan2(np.linalg.norm(vh), 4.0))
                    u = (E_ - S_) / np.linalg.norm(E_ - S_)
                    for slack in (0.0, 0.3):
                        a = a0 + slack
                        er, el = reach("r", S_, u, a, zc, H), reach("l", E_, -u, a, zc, H)
                        if max(er, el) <= 0.03:
                            break
                    else:
                        continue
                    p1 = path(S, B, zs=zc, zc=zc)[0]
                    B2, _ = bounce_for(E, S, zs=zc, zc=zc)
                    p2 = path(E, B2, zs=zc, zc=zc)[0]
                    for key, (caps, chains) in stances.items():
                        c1, x1 = evaluate(caps, chains, p1)
                        if not ok(x1) or c1 < -0.02: continue
                        c2, x2 = evaluate(caps, chains, p2)
                        if not ok(x2): continue
                        res.append((round(min(c1, c2), 3), H, zc, key, S, E, round(a, 2), slack, round(er * 100, 1), round(el * 100, 1), B.round(2), round(float(np.linalg.norm(vh)), 2), x1, x2))
            print(" H", H, "zc", zc, "results", len(res), "best", max((r[0] for r in res), default=None), flush=True)
    res.sort(key=lambda r: -r[0])
    for r in res[:30]: print(r)
    pickle.dump(res, open("scratchpad/btl/plan3.pkl", "wb"))
