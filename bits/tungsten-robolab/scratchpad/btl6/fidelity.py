"""Fidelity of the chained replay for a CHANGED stage table: predict (replay from the G records with the table replaced) vs truth (a new closed-loop record with
the table in the params, replayed with its own tables = identity).
    scratchpad/btl6/py scratchpad/btl6/fidelity.py stage a0 a1 noise_seed seed0 seed1 tag
"""
import os, pickle, subprocess, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl6")
import chainrep as C, chainobj as Ob, tabio
import fit3 as F

stage, a0, a1, nseed, s0_, s1_, tag = int(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6]), sys.argv[7]
G = "scratchpad/btl5/params/final_g.txt"
B, nom, sc = F.parse_stage(G, stage)
rng = np.random.default_rng(nseed)
B2 = B.copy()
B2[0] += rng.normal(0, a0, B[0].shape)
for i in range(1, 6):
    B2[i] += rng.normal(0, a1, B[i].shape)
pf = f"out/btl6/fid_{tag}.txt"
tabio.write_table(G, pf, stage, B2, f"fidelity test {tag}: stage {stage} table + noise {a0}/{a1} seed {nseed}", nom, sc)
rdir = f"out/btl6/rec_fid_{tag}"
os.makedirs(rdir, exist_ok=True)
r = subprocess.run(["scratchpad/btl6/py", "scratchpad/btl6/rec6.py", "bin/challengers/btl5-a", pf, str(s0_), str(s1_), rdir, "6", "6.0"], capture_output=True, text=True)
rec0 = pickle.load(open("out/btl6/recG/rec_%d.pkl" % s0_, "rb"))
chG = C.Chain(G, rec0)           # predictor: G's tables + the replacement
chT = C.Chain(pf, rec0)          # truth: identity replay of the new record
rows = []
for sd in range(s0_, s1_):
    recG = pickle.load(open(f"out/btl6/recG/rec_{sd}.pkl", "rb"))
    recN = pickle.load(open(f"{rdir}/rec_{sd}.pkl", "rb"))
    stG = chG.prep(recG, stage)
    stN = chT.prep(recN, stage)
    if stG is None or stN is None:
        continue
    runP = chG.run(stG, over={stage: B2})
    runT = chT.run(stN)
    if runP is None or runT is None:
        continue
    oP = Ob.chain_outcome(runP, stage, None)
    oT = Ob.chain_outcome(runT, stage, None)
    rows.append((sd, runP["trig"], runT["trig"], runP["rel"], runT["rel"], oP, oT, [bool(p["ok"]) for p in recN["pass_log"]], [bool(p["ok"]) for p in recG["pass_log"]]))
n = len(rows)
print(f"tag {tag}: stage {stage} noise {a0}/{a1}: starts {n}")
def eq(a, b, keys): return all(a.get(k) == b.get(k) for k in keys)
print("trigger ticks equal (stage 3, 4):", sum(1 for r in rows if r[1].get(3) == r[2].get(3)), sum(1 for r in rows if r[1].get(4) == r[2].get(4)))
print("release ticks equal (2, 3, 4):", [sum(1 for r in rows if r[3].get(s) == r[4].get(s)) for s in (2, 3, 4)])
for nm in ("v2", "v3", "v4"):
    ag = sum(1 for r in rows if r[5][nm] == r[6][nm]); print(f"{nm} flag agreement predicted vs truth: {ag}/{n}; mean predicted {np.mean([r[5][nm] for r in rows]):.3f} truth {np.mean([r[6][nm] for r in rows]):.3f}")
Vp = np.array([r[5]["V"] for r in rows]); Vt = np.array([r[6]["V"] for r in rows])
print(f"V mean predicted {Vp.mean():.3f} truth {Vt.mean():.3f}; correlation {np.corrcoef(Vp, Vt)[0,1]:.3f}; start with identical V {np.mean(Vp == Vt):.2f}")
# the G baseline V for the same starts (the unchanged table)
Vg = []
for sd in range(s0_, s1_):
    recG = pickle.load(open(f"out/btl6/recG/rec_{sd}.pkl", "rb"))
    stG = chG.prep(recG, stage)
    if stG is None: continue
    runG = chG.run(stG)
    if runG is not None: Vg.append(Ob.chain_outcome(runG, stage, None)["V"])
print(f"V of G on the same starts {np.mean(Vg):.3f}; predicted change {Vp.mean() - np.mean(Vg):+.3f}, true change {Vt.mean() - np.mean(Vg):+.3f}")
# per start predicted vs true change relative to G (sign agreement among changed starts)
print("real closed-loop streak (6 s) G %.3f new %.3f" % (np.mean([pickle.load(open(f"out/btl6/recG/rec_{r[0]}.pkl","rb"))["streak"] for r in rows]), np.mean([pickle.load(open(f"{rdir}/rec_{r[0]}.pkl","rb"))["streak"] for r in rows])))
