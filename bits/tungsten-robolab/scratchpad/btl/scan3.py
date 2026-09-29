import sys, numpy as np, itertools
sys.path.insert(0, "scratchpad/btl")
import stance as st
from plan import path, evaluate, seg_dist, R, G, COR, KR

SH = {"r": np.array([0.18, -0.19, 1.28]), "l": np.array([0.18, 0.19, 1.28])}
def reach(side, xy, zc=0.9):
    return np.linalg.norm(np.array([xy[0], xy[1], zc + 0.12]) - SH[side])

def binding(lq, rq, pts):
    caps = st.legs(lq, rq); best = (9, None)
    for p in pts:
        for (n, a, b, r) in caps:
            c = seg_dist(p, a, b) - R - r
            if c < best[0]: best = (round(c, 3), n)
    return best

def bounce_for(S, E, zs=0.78, vz0=-3.5, zc=0.75):
    vi = np.sqrt(vz0 ** 2 + 2 * G * (zs - R)); td = (vi + vz0) / G; vo = COR * vi
    tu = (vo - np.sqrt(max(vo ** 2 - 2 * G * (zc - R), 0))) / G
    S, E = np.array(S), np.array(E)
    # E = B + (1-KR) vh tu, B = S + vh td
    vh = (E - S) / (td + (1 - KR) * tu)
    return S + vh * td

stances = {}
for fx, fy, bx, by in itertools.product((0.25, 0.35, 0.45), (0.15, 0.22, 0.3), (-0.2, -0.3, -0.4, -0.5), (-0.2, -0.28, -0.36)):
    front, e1 = st.ik("l", fx, fy); back, e2 = st.ik("r", bx, by, seed=[0.0, 0.2, 0.1, 0.6, -0.59])
    if e1 < 0.03 and e2 < 0.045: stances[(fx, fy, bx, by)] = (front, back)
print(len(stances), "stances")
res = []
for key, (front, back) in stances.items():
    for S in itertools.product((0.25, 0.35, 0.45, 0.55), (-0.25, -0.33, -0.41)):
        if reach("r", S) > 0.62: continue
        for E in itertools.product((-0.2, -0.1, 0.0, 0.1), (0.3, 0.38, 0.46)):
            if reach("l", E) > 0.62: continue
            B = bounce_for(S, E)
            pts, E1, *_ = path(S, B)
            c1, x1 = evaluate(front, back, pts)
            if not (x1 and x1[2] and 0.15 < x1[0] < 0.85): continue
            B2 = bounce_for(E, S)
            pts2, E2, *_ = path(E, B2)
            c2, x2 = evaluate(front, back, pts2)
            if not (x2 and x2[2] and 0.15 < x2[0] < 0.85): continue
            res.append((round(min(c1, c2), 3), round(c1, 3), round(c2, 3), key, S, E, B.round(2), x1, x2))
res.sort(key=lambda r: -r[0])
for r in res[:20]: print(r)
if res:
    k = res[0]; front, back = stances[k[3]]
    print("front", front.round(3), "back", back.round(3))
    print(binding(front, back, path(k[4], bounce_for(k[4], k[5]))[0]), binding(front, back, path(k[5], bounce_for(k[5], k[4]))[0]))
