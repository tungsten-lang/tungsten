import sys, numpy as np, itertools
sys.path.insert(0, "scratchpad/btl")
import stance as st
from plan import path, evaluate
G, R, COR, KR = 9.81, 0.12, 0.77, 0.17
SH = {"r": np.array([0.18, -0.19, 1.28]), "l": np.array([0.18, 0.19, 1.28])}
def reach(side, xy, zc=0.9): return np.linalg.norm(np.array([xy[0], xy[1], zc + 0.12]) - SH[side])
def bounce_for(S, E, zs=0.78, vz0=-3.5, zc=0.75):
    vi = np.sqrt(vz0 ** 2 + 2 * G * (zs - R)); td = (vi + vz0) / G; vo = COR * vi
    tu = (vo - np.sqrt(max(vo ** 2 - 2 * G * (zc - R), 0))) / G
    S, E = np.array(S), np.array(E); vh = (E - S) / (td + (1 - KR) * tu); return S + vh * td, vh
res = []
for fx, fy, bx, by in itertools.product((0.25, 0.35, 0.45), (0.12, 0.17, 0.22), (-0.3, -0.4, -0.5), (-0.15, -0.22, -0.3)):
    front, e1 = st.ik("l", fx, fy); back, e2 = st.ik("r", bx, by, seed=[0.0, 0.2, 0.1, 0.6, -0.59])
    if e1 > 0.03 or e2 > 0.045: continue
    S = (0.5, -0.28)
    for E in itertools.product((-0.25, -0.15, -0.05, 0.05), (0.3, 0.38, 0.46)):
        if reach("l", E) > 0.62: continue
        B, vh = bounce_for(S, E)
        c1, x1 = evaluate(front, back, path(S, B)[0])
        B2, _ = bounce_for(E, S)
        c2, x2 = evaluate(front, back, path(E, B2)[0])
        ok = lambda x: x and x[2] and 0.15 < x[0] < 0.85
        if ok(x1) and ok(x2):
            res.append((round(min(c1, c2), 3), (fx, fy, bx, by), E, B.round(2), vh.round(2), x1, x2))
res.sort(key=lambda r: -r[0])
for r in res[:12]: print(r)
