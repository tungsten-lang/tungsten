"""Single-start ORACLE at stage 3 (replay): how far can a free table go on ONE low-apex start? (is the miss a policy problem or a physical limit?)
    scratchpad/btl6/py scratchpad/btl6/oracle_start.py lo hi nstarts gens      (stage-3 incoming apex in [lo, hi))"""
import os, pickle, sys, math
import numpy as np
sys.path.insert(0, "scratchpad/btl6"); sys.path.insert(0, "scratchpad/btl5")
from multiprocessing import get_context
_W = {}
def init():
    import chainrep as C, chainobj as Ob, fit3 as F, fitchain as FC
    rec0 = pickle.load(open("out/btl6/recG/rec_84001.pkl", "rb"))
    ch = C.Chain("scratchpad/btl5/params/final_g.txt", rec0)   # G's tables (the stage-4 table of G in the loop)
    z = np.load("scratchpad/btl6/params/valfn4_G.npz"); vf = {k: z[k] for k in ("w", "mu", "sd")}
    _W.update(ch=ch, Ob=Ob, F=F, FC=FC, vf=vf)
def one(job):
    sd, gens = job
    ch, Ob, F, FC, vf = _W["ch"], _W["Ob"], _W["F"], _W["FC"], _W["vf"]
    rec = pickle.load(open(f"out/btl6/recG/rec_{sd}.pkl", "rb"))
    st = ch.prep(rec, 3)
    J = 5
    def ev(x):
        c = x.reshape(6, 16, J)
        dB = np.zeros((8, 16, 17)); part = np.tensordot(c, FC.basis(J), axes=(2, 0)); dB[:6] = np.clip(part, -0.5, 0.5)
        run = ch.run(st, over={3: ch.tab[3][0] + dB})
        if run is None: return 5.0, 0.0, None
        oc = Ob.chain_outcome(run, 3, vf, eps=0.15)
        return oc["obj"], oc["V"], oc
    opt = F.SepCMA(np.zeros(6 * 16 * J), 0.08, seed=sd, popsize=24)
    base = ev(np.zeros(6 * 16 * J))
    best = base
    for g in range(gens):
        xs = opt.ask()
        res = [ev(x) for x in xs]
        opt.tell(xs, [-r[0] for r in res])
        b = min(res, key=lambda r: r[0])
        if b[0] < best[0]: best = b
    oc = best[2]
    fl = oc["fl"] if oc else {}
    return sd, base[1], best[1], bool(fl.get(3, {}).get("touch")), bool(fl.get(3, {}).get("gate")), fl.get(3, {}).get("bfl"), oc["v3"] if oc else 0, oc["v4"] if oc else 0
if __name__ == "__main__":
    lo, hi, n, gens = float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    A = pickle.load(open("out/btl6/apex_stage3.pkl", "rb"))
    act = pickle.load(open("out/btl6/val_verdicts_G.pkl", "rb"))
    seeds = [s for s in sorted(A) if lo <= A[s] < hi and s in act and len(act[s]["ok"]) > 1 and act[s]["ok"][0] and act[s]["ok"][1]
             and act[s]["fl"][2]["touch"] and act[s]["fl"][2]["bounced"] and act[s]["fl"][2]["gate"] and act[s]["fl"][2]["bfl"] == 0][:n]
    with get_context("spawn").Pool(6, initializer=init) as p:
        res = p.map(one, [(s, gens) for s in seeds], chunksize=1)
    print(f"apex {lo}-{hi}: {len(res)} starts; G's table: V(3->4) mean {np.mean([r[1] for r in res]):.2f}; single-start oracle: V mean {np.mean([r[2] for r in res]):.2f}; touched {sum(1 for r in res if r[3])}/{len(res)}, v3 {sum(1 for r in res if r[6])}/{len(res)}, v4 {sum(1 for r in res if r[7])}/{len(res)}")
    for r in res[:12]: print("  ", r)
