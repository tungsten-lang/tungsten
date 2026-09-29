import sys, numpy as np, itertools
sys.path.insert(0, "scratchpad/btl")
import stance as st
from plan import path, evaluate
from scan3 import reach, bounce_for, binding, stances
res = []
for key, (front, back) in stances.items():
    for sx, sy in itertools.product((-0.1, 0.0, 0.1, 0.2, 0.3, 0.4), (-0.3, -0.36, -0.42, -0.48)):
        S, E = (sx, sy), (sx, -sy)
        if reach("r", S) > 0.62: continue
        B = bounce_for(S, E)
        pts, E1, *_ = path(S, B)
        c1, x1 = evaluate(front, back, pts)
        if x1 and x1[2] and 0.15 < x1[0] < 0.85:
            res.append((round(c1, 3), key, S, B.round(2), x1, round(reach("r", S), 2)))
res.sort(key=lambda r: -r[0])
for r in res[:15]: print(r)
