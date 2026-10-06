"""V (chain from stage s) of G's table re-expressed in wider feature units (no fit): the extrapolation of the gains beyond the old +-2.5 range."""
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
    _W.update(ch=ch, vf=vf, sts=sts, stage=stage)
def job(mult):
    ch, vf, sts, stage = _W["ch"], _W["vf"], _W["sts"], _W["stage"]
    ch.tab[stage] = None if False else ch.tab[stage]
    import fit3 as F
    B, nom, sc = F.parse_stage("scratchpad/btl5/params/final_g.txt", stage)
    B7 = np.concatenate([B, np.zeros((1, 16, 17))], 0)
    ch.tab[stage] = (B7, nom, sc)
    if mult != 1.0: ch.reexpress(stage, mult)
    Vs = []; clamp = []
    for st in sts:
        run = ch.run(st)
        if run is None: continue
        oc = Ob.chain_outcome(run, stage, vf)
        Vs.append(oc["V"])
    return mult, float(np.mean(Vs)), len(Vs)
if __name__ == "__main__":
    stage = int(sys.argv[1]); mults = [float(x) for x in sys.argv[2].split(",")]
    with get_context("spawn").Pool(min(6, len(mults)), initializer=init, initargs=(stage,)) as p:
        for r in p.map(job, mults): print(f"stage {stage} units x{r[0]}: V {r[1]:.4f} (n {r[2]})")
