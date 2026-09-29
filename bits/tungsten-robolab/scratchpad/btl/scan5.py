import sys, numpy as np, itertools
sys.path.insert(0, "scratchpad/btl")
import stance as st
from plan import path, evaluate
from check import reach, bounce_for
best = {}
stances = {}
for fx, fy, bx, by in itertools.product((0.25, 0.35, 0.45), (0.12, 0.2, 0.28), (-0.3, -0.4, -0.5), (-0.15, -0.25, -0.35)):
    front, e1 = st.ik("l", fx, fy); back, e2 = st.ik("r", bx, by, seed=[0.0, 0.2, 0.1, 0.6, -0.59])
    if e1 < 0.03 and e2 < 0.045: stances[(fx, fy, bx, by)] = (front, back)
for key, (front, back) in stances.items():
    for S in itertools.product((0.1, 0.2, 0.3, 0.4, 0.5), (-0.3, -0.38, -0.46)):
        if reach("r", S) > 0.62: continue
        for E in itertools.product((-0.2, -0.1, 0.0, 0.1, 0.2, 0.3), (0.3, 0.38, 0.46)):
            if reach("l", E) > 0.62: continue
            B, vh = bounce_for(S, E)
            c1, x1 = evaluate(front, back, path(S, B)[0])
            ok = lambda x: x and x[2] and 0.15 < x[0] < 0.85
            if not ok(x1): continue
            B2, _ = bounce_for(E, S)
            c2, x2 = evaluate(front, back, path(E, B2)[0])
            dx = round(S[0] - E[0], 1)
            k1 = ("oneway", dx); k2 = ("both", dx)
            if k1 not in best or c1 > best[k1][0]: best[k1] = (round(c1, 3), key, S, E, B.round(2), round(float(np.linalg.norm(vh)), 2))
            if ok(x2) and (k2 not in best or min(c1, c2) > best[k2][0]): best[k2] = (round(min(c1, c2), 3), key, S, E, B.round(2), round(float(np.linalg.norm(vh)), 2))
for k in sorted(best): print(k, best[k])
