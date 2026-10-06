"""Chain objective of G under random perturbations of one stage table (replay only): the sharpness of G's optimum and the noise floor of V.
    scratchpad/btl6/py scratchpad/btl6/landscape.py stage seed0 seed1 amp1,amp2,.. ndir"""
import os, pickle, sys, time
import numpy as np
sys.path.insert(0, "scratchpad/btl6")
from multiprocessing import get_context
_W = {}

def init(stage, seed0, seed1):
    import chainrep as C, chainobj as Ob, fit3 as F
    G = "scratchpad/btl5/params/final_g.txt"
    rec0 = pickle.load(open("out/btl6/recG/rec_%d.pkl" % seed0, "rb"))
    ch = C.Chain(G, rec0)
    sts = []
    for sd in range(seed0, seed1):
        rec = pickle.load(open("out/btl6/recG/rec_%d.pkl" % sd, "rb"))
        st = ch.prep(rec, stage)
        if st is None or not all(p["ok"] for p in rec["pass_log"][:2]) or len(rec["pass_log"]) < 2:
            continue
        sts.append(st)
    _W.update(ch=ch, Ob=Ob, F=F, sts=sts, stage=stage)

def job(a):
    amp, k = a
    ch, Ob, F, sts, stage = _W["ch"], _W["Ob"], _W["F"], _W["sts"], _W["stage"]
    B = ch.tab[stage][0]
    if amp > 0:
        rng = np.random.default_rng(1000 + k)
        B2 = B.copy(); B2[0] += rng.normal(0, amp, B[0].shape)
        for i in range(1, 6): B2[i] += rng.normal(0, amp / 2, B[i].shape)
        over = {stage: B2}
    else:
        over = None
    Vs, objs = [], []
    for st in sts:
        run = ch.run(st, over=over)
        if run is None: continue
        oc = Ob.chain_outcome(run, stage, None)
        Vs.append(oc["V"]); objs.append(oc["obj"])
    return amp, k, float(np.mean(Vs)), float(np.mean(objs)), len(Vs)

if __name__ == "__main__":
    stage, a, b = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
    amps = [float(x) for x in sys.argv[4].split(",")]; nd = int(sys.argv[5])
    jobs = [(0.0, 0)] + [(amp, k) for amp in amps for k in range(nd)]
    t1 = time.time()
    with get_context("spawn").Pool(6, initializer=init, initargs=(stage, a, b)) as p:
        res = p.map(job, jobs, chunksize=1)
    base = res[0]
    print("G: V %.4f obj %.4f (n starts %d)" % (base[2], base[3], base[4]))
    for amp in amps:
        v = np.array([r[2] for r in res if r[0] == amp]); o = np.array([r[3] for r in res if r[0] == amp])
        print(f"amp {amp}: V mean {v.mean():.4f} sd {v.std():.4f} min {v.min():.4f} max {v.max():.4f} | obj mean {o.mean():.4f} sd {o.std():.4f}")
    print("time", round(time.time() - t1))
