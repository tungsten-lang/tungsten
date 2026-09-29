import sys, numpy as np, itertools
sys.path.insert(0, "scratchpad/btl")
import stance as st
G, R, COR, KR = 9.81, 0.12, 0.77, 0.17

def seg_dist(p, a, b):
    ab = b - a; t = np.clip(np.dot(p - a, ab) / np.dot(ab, ab), 0, 1)
    return np.linalg.norm(p - (a + t * ab))

def path(S, B, zs=0.78, vz0=-3.5, zc=0.75, dt=0.002):
    S, B = np.array(S, float), np.array(B, float)
    vi = np.sqrt(vz0 ** 2 + 2 * G * (zs - R)); td = (vi + vz0) / G
    vh = (B - S) / td; vo = COR * vi; vh2 = vh * (1 - KR)
    disc = vo ** 2 - 2 * G * (zc - R)
    tu = (vo - np.sqrt(disc)) / G if disc > 0 else vo / G
    pts = []
    for t in np.arange(0, td, dt):
        xy = S + vh * t; pts.append((xy[0], xy[1], zs + vz0 * t - 0.5 * G * t * t))
    for t in np.arange(0, tu, dt):
        xy = B + vh2 * t; pts.append((xy[0], xy[1], R + vo * t - 0.5 * G * t * t))
    E = B + vh2 * tu
    return np.array(pts), E, td, tu, vh

def leg_point(chain, z):
    """xy of a leg's axis at height z (hip -> knee -> ankle polyline)."""
    for a, b in zip(chain[:-1], chain[1:]):
        lo, hi = sorted((a[2], b[2]))
        if lo <= z <= hi:
            f = (z - a[2]) / (b[2] - a[2]); return (a + f * (b - a))[:2]
    return (chain[-1] if z < chain[-1][2] else chain[0])[:2]

def evaluate(lq, rq, pts):
    caps = st.legs(lq, rq)
    clear = min(seg_dist(p, a, b) - R - r for p in pts for (_, a, b, r) in caps)
    chains = {}
    for s, q in (("l", lq), ("r", rq)):
        st.fk(s, q)
        chains[s] = [st.d.body(f"{s}_thigh").xpos.copy(), st.d.body(f"{s}_shin").xpos.copy(), st.d.body(f"{s}_foot").xpos.copy()]
    crotch = chains["l"][0][2] - 0.06
    cross = None
    prev = None
    for p in pts:
        pl, pr = leg_point(chains["l"], p[2]), leg_point(chains["r"], p[2])
        g = pr - pl; rel = p[:2] - pl
        s = g[0] * rel[1] - g[1] * rel[0]
        if prev is not None and np.sign(s) != np.sign(prev[0]):
            u = np.dot(rel, g) / np.dot(g, g)
            cross = (round(float(u), 2), round(float(p[2]), 2), bool(p[2] + R < crotch))
        prev = (s,)
    return clear, cross

if __name__ == "__main__":
    front, _ = st.ik("l", 0.34, 0.196); back, _ = st.ik("r", -0.18, -0.273, seed=[0.2, 0.2, 0.1, 0.9, -0.59])
    for S, B in (((0.35, -0.3), (0.15, 0.0)), ((0.3, -0.3), (0.12, 0.02)), ((0.45, -0.28), (0.2, 0.0)), ((0.05, -0.35), (0.1, 0.0))):
        pts, E, td, tu, vh = path(S, B)
        print(S, B, "E", E.round(2), "td", round(td, 3), "tu", round(tu, 3), "vh", vh.round(2), evaluate(front, back, pts))
