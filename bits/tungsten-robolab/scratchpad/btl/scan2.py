import sys, numpy as np, itertools
sys.path.insert(0, "scratchpad/btl")
import stance as st
from plan import path, evaluate, seg_dist, R

def binding(lq, rq, pts):
    caps = st.legs(lq, rq)
    best = (9, None, None)
    for p in pts:
        for (n, a, b, r) in caps:
            c = seg_dist(p, a, b) - R - r
            if c < best[0]: best = (round(c, 3), n, p.round(2))
    return best

stances = {}
for fx, fy, bx, by in itertools.product((0.3, 0.4, 0.5), (0.15, 0.22), (-0.25, -0.35, -0.45), (-0.25, -0.36)):
    front, e1 = st.ik("l", fx, fy); back, e2 = st.ik("r", bx, by, seed=[0.0, 0.2, 0.1, 0.6, -0.59])
    if e1 < 0.03 and e2 < 0.04: stances[(fx, fy, bx, by)] = (front, back)
print(len(stances), "stances")
res = []
for key, (front, back) in stances.items():
    for sx, sy, bxx, byy in itertools.product((0.1, 0.2, 0.3, 0.4, 0.5), (-0.25, -0.33, -0.4), (0.0, 0.1, 0.2, 0.3), (-0.05, 0.05)):
        pts, E, *_ = path((sx, sy), (bxx, byy))
        clear, cross = evaluate(front, back, pts)
        if not (cross and cross[2] and 0.2 < cross[0] < 0.8):
            continue
        # return path (fixed stance): from E back through the same bounce to S
        pts2, E2, *_ = path(tuple(E), (bxx, byy))
        clear2, cross2 = evaluate(front, back, pts2)
        ok2 = cross2 and cross2[2] and 0.2 < cross2[0] < 0.8
        res.append((round(min(clear, clear2 if ok2 else -1), 3), round(clear, 3), key, (sx, sy), (bxx, byy), E.round(2), cross, E2.round(2), cross2))
res.sort(key=lambda r: -r[1])
print("best one-way (scissor candidates first by one-way clearance)")
for r in res[:12]: print(r)
res.sort(key=lambda r: -r[0])
print("best both ways (fixed stance)")
for r in res[:12]: print(r)
k = res[0]
front, back = stances[k[2]]
print(binding(front, back, path(k[3], k[4])[0]))
