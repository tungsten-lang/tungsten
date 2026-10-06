"""Per-start streak of a variant against G, binned by the stage-3 incoming ball's vertical speed at the crossing (from the G chain replay).
    scratchpad/btl6/py scratchpad/btl6/an_gate.py variant.streaks [stage]"""
import os, pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl6")
import chainrep as C
stage = int(sys.argv[2]) if len(sys.argv) > 2 else 3
cache = f"out/btl6/vzc_stage{stage}.pkl"
if os.path.exists(cache):
    V = pickle.load(open(cache, "rb"))
else:
    rec0 = pickle.load(open("out/btl6/recG/rec_84001.pkl", "rb"))
    ch = C.Chain("scratchpad/btl5/params/final_g.txt", rec0)
    V = {}
    for sd in range(84001, 84841):
        rec = pickle.load(open(f"out/btl6/recG/rec_{sd}.pkl", "rb"))
        st = ch.prep(rec, stage)
        if st is None: continue
        v = ch.vzc0(st)
        if v is not None: V[sd] = v
    pickle.dump(V, open(cache, "wb"))
def load(f): return {int(a): int(b) for a, b in (l.split() for l in open(f) if l.strip())}
g = load("out/btl6/recG.streaks"); c = load(sys.argv[1])
ks = sorted(set(V) & set(g) & set(c))
x = np.array([V[k] for k in ks]); d = np.array([c[k] - g[k] for k in ks], float); gg = np.array([g[k] for k in ks], float); cc = np.array([c[k] for k in ks], float)
print("stage", stage, "starts", len(ks), "overall diff", d.mean().round(3))
for lo, hi in [(-1, 0.2), (0.2, 0.5), (0.5, 0.8), (0.8, 1.1), (1.1, 1.4), (1.4, 1.7), (1.7, 5)]:
    m = (x >= lo) & (x < hi)
    if m.sum(): print(f"vzc {lo:.1f}-{hi:.1f}: n {m.sum():3d} G {gg[m].mean():.2f} variant {cc[m].mean():.2f} diff {d[m].mean():+.2f} (se {d[m].std(ddof=1)/np.sqrt(m.sum()):.2f})")
