"""1-D scan of one knob of a stage in the chain replay (G records): V (chain from the stage) on the starts whose hinge argument is below vmax.
    scratchpad/btl6/py scratchpad/btl6/scan_knob.py stage knobname v1,v2,... [vsel vk vs vmax]"""
import os, pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl6")
import chainrep as C, chainobj as Ob
from multiprocessing import get_context
_W = {}
def init(stage, vsel, vk, vs, vmax):
    rec0 = pickle.load(open("out/btl6/recG/rec_84001.pkl", "rb"))
    ch = C.Chain("scratchpad/btl5/params/final_g.txt", rec0)
    ch.vk[stage], ch.vs[stage], ch.vsel[stage] = vk, vs, vsel
    z = np.load("scratchpad/btl6/params/valfn4_G.npz"); vf = {k: z[k] for k in ("w", "mu", "sd")}
    sts = []
    for sd in range(84001, 84841):
        rec = pickle.load(open(f"out/btl6/recG/rec_{sd}.pkl", "rb"))
        if not rec["pass_log"] or not rec["pass_log"][0]["ok"]: continue
        st = ch.prep(rec, stage)
        if st is None: continue
        v = ch.vzc0(st)
        if v is None or v >= vmax: continue
        sts.append(st)
    _W.update(ch=ch, vf=vf, sts=sts, stage=stage)
def job(a):
    name, val = a
    ch, vf, sts, stage = _W["ch"], _W["vf"], _W["sts"], _W["stage"]
    kn = {stage: {name: val}} if val != 0 or name == "dkap" else None
    Vs = []
    for st in sts:
        run = ch.run(st, knobs=kn)
        if run is None: continue
        Vs.append(Ob.chain_outcome(run, stage, vf)["V"])
    return val, float(np.mean(Vs)), len(Vs)
if __name__ == "__main__":
    stage, name = int(sys.argv[1]), sys.argv[2]
    vals = [float(x) for x in sys.argv[3].split(",")]
    vsel = int(sys.argv[4]) if len(sys.argv) > 4 else 0
    vk = float(sys.argv[5]) if len(sys.argv) > 5 else 1.1
    vs = float(sys.argv[6]) if len(sys.argv) > 6 else 0.5
    vmax = float(sys.argv[7]) if len(sys.argv) > 7 else 1.3
    with get_context("spawn").Pool(6, initializer=init, initargs=(stage, vsel, vk, vs, vmax)) as p:
        for r in p.map(job, [(name, v) for v in vals], chunksize=1):
            print(f"stage {stage} {name} {r[0]:+.4f}: V {r[1]:.4f} (n {r[2]})")
