"""Touch of stages 3 / 4 against the incoming ball's APEX (the rise from its bounce), c6 = 0 balls: where does the table stop reaching the ball?"""
import os, pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl6")
import chainrep as C, chainobj as Ob
act = pickle.load(open("out/btl6/val_verdicts_G.pkl", "rb"))
rec0 = pickle.load(open("out/btl6/recG/rec_84001.pkl", "rb"))
ch = C.Chain("scratchpad/btl5/params/final_g.txt", rec0)
rows = {3: [], 4: []}
for sd in range(84001, 84841):
    r = act.get(sd)
    if r is None or not (len(r["ok"]) > 1 and r["ok"][0] and r["ok"][1]): continue
    rec = pickle.load(open(f"out/btl6/recG/rec_{sd}.pkl", "rb"))
    st = ch.prep(rec, 2)
    if st is None: continue
    run = ch.run(st)
    if run is None: continue
    for s in (3, 4):
        if s in run["stage"] and (s == 3 or r["v3"] > 0):
            cr = run["stage"][s]["cr"]
            oc = Ob.eval_stage(run, s)
            touch = bool(oc[1].get("touch")) if oc else False
            rows[s].append((cr[4], cr[3], touch))
for s in (3, 4):
    a = np.array(rows[s], float)
    print(f"stage {s}: n {len(a)}; apex of the incoming ball quantiles", np.quantile(a[:, 0], [0.05, 0.25, 0.5, 0.75, 0.95]).round(3))
    edges = [0.0, 0.54, 0.56, 0.58, 0.60, 0.61, 0.62, 0.64, 0.66, 0.70, 0.8, 2]
    for lo, hi in zip(edges[:-1], edges[1:]):
        m = (a[:, 0] >= lo) & (a[:, 0] < hi)
        if m.sum(): print(f"   apex {lo:.2f}-{hi:.2f}: n {m.sum():3d} touch {a[m,2].mean():.2f}")
