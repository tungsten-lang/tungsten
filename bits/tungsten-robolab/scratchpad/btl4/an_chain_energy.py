"""Energy inheritance along the chain: the predicted vertical speed at the crossing at each stage's trigger, and the passes' outcomes."""
import pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl4"); sys.path.insert(0, "scratchpad/btl2")
import rlib, fit_v
import oracle_lib as O, oracle_multi as M

rows = []
rp = None
for sd in range(13001, 13341):
    rec = pickle.load(open(f"out/btl4/rec/rec_{sd}.pkl", "rb"))
    if rp is None:
        rp = O.Replay(rec)
    rp.rec = rec; rp.act_ids = rec["act_ids"]
    vz = {}
    for st, (hand, bn) in rlib.STAGES.items():
        ks = M.trigger_tick(rec, rp, bn, lead=rlib.LEAD)
        if ks is None or ks not in rec["snaps"]:
            continue
        pc = fit_v.pred_cross_full(rp, ks)
        if pc is not None:
            vz[st] = pc[3]
    pl = rec["pass_log"]
    rows.append((sd, vz, [bool(e["ok"]) for e in pl[:5]]))
for a, b in ((0, 1), (1, 2), (2, 3), (0, 2)):
    xs = [(r[1][a], r[1][b]) for r in rows if a in r[1] and b in r[1]]
    x = np.array(xs)
    print(f"corr(vz_c stage {a}, vz_c stage {b}) = {np.corrcoef(x[:,0], x[:,1])[0,1]:+.2f}  (n {len(x)}; means {x.mean(0).round(2).tolist()}, sd {x.std(0).round(2).tolist()})")
# stage-1 vz_c tail vs stage 2 vz_c
x = np.array([(r[1][1], r[1][2]) for r in rows if 1 in r[1] and 2 in r[1]])
lo = x[:, 0] < np.quantile(x[:, 0], 0.25)
print("stage-2 vz_c when stage-1 vz_c is in its lowest quartile:", x[lo, 1].mean().round(2), " otherwise", x[~lo, 1].mean().round(2))
# pass outcomes
for k in range(4):
    ok = [r[2][k] for r in rows if len(r[2]) > k]
    print(f"pass {k+1}: ok {np.mean(ok):.2f} (n {len(ok)})")
