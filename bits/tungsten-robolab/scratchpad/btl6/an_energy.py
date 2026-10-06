"""P(v2), P(v3 | v2) as a function of the incoming ball's vertical speed at the crossing (vzc0) at the stage-2 trigger, on the G records."""
import os, pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl6")
import chainrep as C
act = pickle.load(open("out/btl6/val_verdicts_G.pkl", "rb"))
rec0 = pickle.load(open("out/btl6/recG/rec_84001.pkl", "rb"))
ch = C.Chain("scratchpad/btl5/params/final_g.txt", rec0)
rows = []
for sd, r in sorted(act.items()):
    if not r["ok"][0]: continue
    rec = pickle.load(open(f"out/btl6/recG/rec_{sd}.pkl", "rb"))
    st = ch.prep(rec, 2)
    if st is None: continue
    v = ch.vzc0(st)
    if v is None: continue
    fl = r["fl"]
    rows.append((v, r["v2"], r["v3"], r["v4"], fl[2]["touch"], fl[2]["bounced"], fl[2]["pre"], r["ok"][1] if len(r["ok"]) > 1 else False))
a = np.array(rows, float)
print("n", len(a))
edges = [0, 0.3, 0.6, 0.9, 1.1, 1.3, 1.5, 1.7, 2.0, 5]
print("vzc0 bin | n | touch2 | v2 | pass2 ok (real) | v3 | v4")
for lo, hi in zip(edges[:-1], edges[1:]):
    m = (a[:, 0] >= lo) & (a[:, 0] < hi)
    if m.sum() == 0: continue
    print(f"{lo:.1f}-{hi:.1f} | {m.sum():3d} | {a[m,4].mean():.2f} | {a[m,1].mean():.2f} | {a[m,7].mean():.2f} | {a[m,2].mean():.2f} | {a[m,3].mean():.2f}")
print("quantiles of vzc0:", np.quantile(a[:, 0], [0.05, 0.1, 0.25, 0.5, 0.75, 0.9]).round(2))
