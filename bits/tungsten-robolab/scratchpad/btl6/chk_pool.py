"""Identity check of the chained replay on many recorded G starts (6 workers): event ticks, table activations, ball path.
    scratchpad/btl6/py scratchpad/btl6/chk_pool.py recdir params s0 seed0 seed1 [workers]"""
import os, pickle, sys, time
import numpy as np
sys.path.insert(0, "scratchpad/btl6")
from multiprocessing import get_context

_W = {}

def init(recdir, pfile, s0, seed0):
    import chainrep as C
    rec0 = pickle.load(open(os.path.join(recdir, f"rec_{seed0}.pkl"), "rb"))
    _W["ch"] = C.Chain(pfile, rec0); _W["C"] = C; _W["recdir"] = recdir; _W["s0"] = s0

def one(sd):
    C, ch, s0 = _W["C"], _W["ch"], _W["s0"]
    f = os.path.join(_W["recdir"], f"rec_{sd}.pkl")
    if not os.path.exists(f):
        return sd, None
    rec = pickle.load(open(f, "rb"))
    st = ch.prep(rec, s0)
    if st is None:
        return sd, None
    t1 = time.time(); run = ch.run(st); dt = time.time() - t1
    if run is None:
        return sd, ("fail",)
    trig, rel, n = run["trig"], run["rel"], run["n"]
    ks = st["ks"]; rr = st["rec_rel"]
    ok_trig = all(trig.get(s) == ks.get(s) for s in (3, 4) if s > s0 and ks.get(s) is not None and (s in trig or True))
    # stages the record never triggered must not trigger in the replay either
    ok_trig = ok_trig and all((s in trig) == (s in ks) for s in (3, 4) if s > s0)
    ok_rel = all(rel.get(s) == rr.get(s) for s in (2, 3, 4) if s >= s0)
    amax = 0.0
    for s, ss in run["stage"].items():
        if s == 2: continue
        arm = ch.idx["r" if C.HAND[s] == "r" else "l"]
        for j in range(len(ss["live"])):
            if ss["live"][j] and ss["t0"] + j < len(st["acts"]):
                amax = max(amax, float(np.max(np.abs(st["acts"][ss["t0"] + j][arm] - ss["A"][:, j]))))
    m = min(n, len(st["ball_rec"]))
    bm = float(np.max(np.abs(run["out"]["pos"][:m] - st["ball_rec"][:m])))
    return sd, (ok_trig, ok_rel, amax, bm, dt, n)

if __name__ == "__main__":
    recdir, pfile, s0, a, b = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
    w = int(sys.argv[6]) if len(sys.argv) > 6 else 6
    with get_context("spawn").Pool(w, initializer=init, initargs=(recdir, pfile, s0, a)) as p:
        res = p.map(one, range(a, b), chunksize=8)
    ok = [(sd, r) for sd, r in res if r is not None and r[0] != "fail"]
    print("starts with a chain", len(ok), "of", b - a, "failed", sum(1 for sd, r in res if r is not None and r[0] == "fail"))
    print("triggers equal", sum(1 for sd, r in ok if r[0]), "releases equal", sum(1 for sd, r in ok if r[1]))
    print("table-vs-record max", max(r[2] for sd, r in ok), "ball path max dev", max(r[3] for sd, r in ok), "mean time", np.mean([r[4] for sd, r in ok]).round(3), "mean ticks", np.mean([r[5] for sd, r in ok]).round(0))
    bad = [(sd, r) for sd, r in ok if not (r[0] and r[1]) or r[2] > 1e-6 or r[3] > 1e-6]
    print("deviating starts", len(bad), bad[:10])
