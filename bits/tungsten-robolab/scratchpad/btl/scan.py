import sys, numpy as np, itertools
sys.path.insert(0, "scratchpad/btl")
import stance as st
from plan import path, evaluate
res = []
for fx, fy, bx, by in itertools.product((0.3, 0.4, 0.5), (0.15, 0.22, 0.3), (-0.15, -0.25, -0.35), (-0.2, -0.28, -0.36)):
    front, e1 = st.ik("l", fx, fy); back, e2 = st.ik("r", bx, by, seed=[0.0, 0.2, 0.1, 0.6, -0.59])
    if e1 > 0.03 or e2 > 0.04:
        continue
    for sx in (0.0, 0.1, 0.2, 0.3):
        for sy in (-0.3, -0.36):
            S = (sx, sy); B = (sx, 0.0)
            pts, E, *_ = path(S, B)
            clear, cross = evaluate(front, back, pts)
            if cross and cross[2] and 0.2 < cross[0] < 0.8:
                res.append((round(clear, 3), (fx, fy, bx, by), S, B, E.round(2), cross))
res.sort(key=lambda r: -r[0])
for r in res[:25]: print(r)
print(len(res))
