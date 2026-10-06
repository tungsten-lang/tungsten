"""V (chain from stage s) of G's table with ONE feature's units changed (no fit): which features' range limits matter.
    scratchpad/btl6/py scratchpad/btl6/eval_feat_units.py stage "0:2,1:2,2:2,3:2,4:2,3:3,3:4" [workers]"""
import os, pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl6")
import chainrep as C, chainobj as Ob
from multiprocessing import get_context
_W = {}
def init(stage):
    rec0 = pickle.load(open("out/btl6/recG/rec_84001.pkl", "rb"))
    ch = C.Chain("scratchpad/btl5/params/final_g.txt", rec0)
    act = pickle.load(open("out/btl6/val_verdicts_G.pkl", "rb"))
    z = np.load("scratchpad/btl6/params/valfn4_G.npz"); vf = {k: z[k] for k in ("w", "mu", "sd")}
    sts = []
    for sd in range(84001, 84841):
        r = act.get(sd)
        if r is None or not (len(r["ok"]) > 1 and r["ok"][0] and r["ok"][1]): continue
        fl = r["fl"]
        if stage == 3 and not (fl[2]["touch"] and fl[2]["bounced"] and fl[2]["gate"] and fl[2]["bfl"] == 0 and fl[2]["pre"] == 0): continue
        rec = pickle.load(open(f"out/btl6/recG/rec_{sd}.pkl", "rb"))
        st = ch.prep(rec, stage)
        if st is not None: sts.append(st)
    _W.update(ch=ch, vf=vf, sts=sts, stage=stage, base=dict(ch.tab))
def job(spec):
    ch, vf, sts, stage = _W["ch"], _W["vf"], _W["sts"], _W["stage"]
    ch.tab = dict(_W["base"])
    if spec != "base":
        i, m = spec.split(":"); ch.reexpress_feat(stage, int(i), float(m))
    Vs = []
    for st in sts:
        run = ch.run(st)
        if run is None: continue
        Vs.append(Ob.chain_outcome(run, stage, vf)["V"])
    return spec, float(np.mean(Vs)), len(Vs)
if __name__ == "__main__":
    stage = int(sys.argv[1]); specs = ["base"] + sys.argv[2].split(",")
    w = int(sys.argv[3]) if len(sys.argv) > 3 else 6
    with get_context("spawn").Pool(w, initializer=init, initargs=(stage,)) as p:
        for r in p.map(job, specs, chunksize=1): print(f"stage {stage} feature:mult {r[0]}: V {r[1]:.4f} (n {r[2]})")
