"""Slow-pass feasibility (round 8 (b)): over a wide stance grid and spot pairs
0.45-0.85 m apart, passes that bounce once and rise to APEX (caught there):
leg clearance (vectorised capsule distances) and a below-crotch gate crossing
both ways, then both hands' reach (push at 1.2 rad, catch from above at 0.6 rad).
Reports the feasible set by arrival speed."""
import sys, itertools, pickle, numpy as np
sys.path.insert(0, "scratchpad/btl"); sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
import stance as st
from plan import path
from plan3 import stance_model, legs_of
from reachmap import ik_real, SEEDS
from armik import tilt
SEEDS2 = SEEDS + ([0.0, 0.3, 0.8, 0.3, 0.0, 0.0], [0.3, 0.3, 1.0, 0.5, 0.3, 0.0], [-0.2, 0.2, 1.2, 0.4, -0.3, 0.0],
                  [0.2, 0.1, -1.0, 0.3, 0.3, 0.0], [0.3, 0.9, 0.3, 1.2, 0, 0], [0.5, 1.2, 0.0, 1.5, 0, 0])
H, ZS, R, G, COR, KR = 0.72, 0.66, 0.12, 9.81, 0.77, 0.17
APEX = float(sys.argv[1]) if len(sys.argv) > 1 else 0.75
VI = np.sqrt(2 * G * (APEX - R)) / COR
VZ0 = -np.sqrt(VI ** 2 - 2 * G * (ZS - R))
TD = (VI + VZ0) / G
TU = COR * VI / G
def bounce(S, E):
    S, E = np.array(S), np.array(E); vh = (E - S) / (TD + (1 - KR) * TU)
    return S + vh * TD, float(np.linalg.norm(vh) * (1 - KR))
def clearance(caps, P):
    out = np.inf
    for a, b, r in caps:
        ab = b - a; t = np.clip((P - a) @ ab / (ab @ ab), 0, 1)
        out = min(out, float(np.min(np.linalg.norm(P - (a + t[:, None] * ab), axis=1))) - R - r)
    return out
def leg_xy(chain, z):
    """xy of the leg axis at heights z (vectorised polyline)."""
    out = np.tile(chain[-1][:2], (len(z), 1)).astype(float)
    top = z >= chain[0][2]; out[top] = chain[0][:2]
    for a, b in zip(chain[:-1], chain[1:]):
        lo, hi = sorted((a[2], b[2])); m = (z >= lo) & (z <= hi)
        f = (z[m] - a[2]) / (b[2] - a[2]); out[m] = a[:2] + f[:, None] * (b - a)[:2]
    return out
def crossing(chains, P):
    crotch = chains["l"][0][2] - 0.06
    pl, pr = leg_xy(chains["l"], P[:, 2]), leg_xy(chains["r"], P[:, 2])
    g = pr - pl; rel = P[:, :2] - pl; s = np.sign(g[:, 0] * rel[:, 1] - g[:, 1] * rel[:, 0])
    k = np.nonzero(s[1:] != s[:-1])[0]
    if len(k) != 1: return None
    i = k[0] + 1; u = float(rel[i] @ g[i] / (g[i] @ g[i]))
    return (round(u, 2), round(float(P[i, 2]), 2), bool(P[i, 2] + R < crotch))
ok = lambda x: x is not None and x[2] and 0.15 < x[0] < 0.85
cache = {}
def reach(side, xy, u, twist, a):
    key = (side, round(xy[0], 2), round(xy[1], 2), round(float(np.arctan2(u[1], u[0])), 1), twist, a)
    if key not in cache:
        n = tilt(u, a); zrel = APEX + (0.8 - H)
        target = np.array([xy[0] - R * n[0], xy[1] - R * n[1], zrel - R * n[2]])
        cache[key] = min((ik_real(side, target, n, s, 0.55, twist) for s in SEEDS2), key=lambda r: r[0] + 0.1 * r[1])[0]
    return cache[key]
if __name__ == "__main__":
    stance_model(H)
    stances = {}
    for fx, fy, bx, by in itertools.product((0.3, 0.4, 0.5, 0.6), (0.05, 0.15, 0.25, 0.35, 0.45), (-0.3, -0.4, -0.5, -0.6), (-0.05, -0.15, -0.25, -0.35, -0.45)):
        front, e1 = st.ik("l", fx, fy); back, e2 = st.ik("r", bx, by, seed=[0.0, 0.2, 0.1, 0.6, -0.59])
        if e1 < 0.035 and e2 < 0.045:
            caps, chains = legs_of(front, back)
            stances[(fx, fy, bx, by)] = ([(np.array(a), np.array(b), r) for a, b, r in caps], chains)
    print(len(stances), "stances; apex", APEX, "vz0", round(VZ0, 2), "td", round(TD, 3), "tu", round(TU, 3), "bounce at", round(TD / (TD + (1 - KR) * TU), 2), flush=True)
    legs = []
    for S in itertools.product((0.15, 0.25, 0.35, 0.45, 0.55), (-0.15, -0.25, -0.35, -0.45)):
        for E in itertools.product((-0.2, -0.1, 0.0, 0.1, 0.2, 0.3), (0.15, 0.25, 0.35, 0.45)):
            dist = float(np.hypot(E[0] - S[0], E[1] - S[1]))
            if not 0.45 <= dist <= 0.85: continue
            B1, v1 = bounce(S, E); P1 = path(S, B1, zs=ZS, vz0=VZ0, zc=APEX)[0][::2]
            B2, v2 = bounce(E, S); P2 = path(E, B2, zs=ZS, vz0=VZ0, zc=APEX)[0][::2]
            for key, (caps, chains) in stances.items():
                x1 = crossing(chains, P1)
                if not ok(x1): continue
                x2 = crossing(chains, P2)
                if not ok(x2): continue
                c = min(clearance(caps, P1), clearance(caps, P2))
                if c < -0.02: continue
                legs.append((round(v1, 2), round(c, 3), key, S, E, round(dist, 2), x1, x2))
    print("leg-feasible", len(legs), "min speed", min((l[0] for l in legs), default=None), flush=True)
    by_pair = {}
    for l in legs:
        k = (l[3], l[4])
        if k not in by_pair or l[1] > by_pair[k][1]: by_pair[k] = l
    print("pairs", len(by_pair), flush=True)
    res = []
    for (S, E), l in sorted(by_pair.items(), key=lambda kv: kv[1][0]):
        S_, E_ = np.array(S), np.array(E); u = (E_ - S_) / np.linalg.norm(E_ - S_)
        best = None
        for twist in (0.3, 0.55, 0.75):
            rr = [reach("r", S_, u, twist, 1.2), reach("l", E_, -u, twist, 1.2), reach("r", S_, u, twist, 0.6), reach("l", E_, -u, twist, 0.6)]
            if best is None or max(rr) < max(best[1]): best = (twist, rr)
        res.append(l + (best[0], [round(x * 100, 1) for x in best[1]]))
        print(res[-1], flush=True)
    pickle.dump((legs, res), open(f"scratchpad/btl/plan7_{APEX}.pkl", "wb"))
