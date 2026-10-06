"""Emulated pass verdicts of the chained replay vs the closed loop's pass log on recorded G starts (pool of 6).
    scratchpad/btl6/py scratchpad/btl6/val_verdicts.py recdir params s0 seed0 seed1 out.pkl"""
import os, pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl6")
from multiprocessing import get_context
_W = {}

def init(recdir, pfile, s0, seed0):
    import chainrep as C, chainobj as Ob
    rec0 = pickle.load(open(os.path.join(recdir, f"rec_{seed0}.pkl"), "rb"))
    _W.update(ch=C.Chain(pfile, rec0), C=C, Ob=Ob, recdir=recdir, s0=s0)

def one(sd):
    ch, Ob, s0 = _W["ch"], _W["Ob"], _W["s0"]
    f = os.path.join(_W["recdir"], f"rec_{sd}.pkl")
    if not os.path.exists(f): return sd, None
    rec = pickle.load(open(f, "rb"))
    st = ch.prep(rec, s0)
    if st is None: return sd, None
    run = ch.run(st)
    if run is None: return sd, None
    oc = Ob.chain_outcome(run, s0, None)
    ok = [bool(p["ok"]) for p in rec["pass_log"]]
    fl = {s: {k: v for k, v in d.items() if k != "sm"} for s, d in oc["fl"].items()}
    sm4 = oc["fl"].get(4, {}).get("sm")
    return sd, {"ok": ok, "v2": oc["v2"], "v3": oc["v3"], "v4": oc["v4"], "fl": fl, "sm4": ({k: (np.array(v) if hasattr(v, "__len__") else v) for k, v in sm4.items() if k in ("apex", "arrive", "va", "touch", "bounced", "gate", "body")} if sm4 else None),
                "J": {s: d["J"] for s, d in oc["fl"].items()}, "streak": rec["streak"], "outcomes": [p["outcome"] for p in rec["pass_log"]], "p_ok_why": None}

if __name__ == "__main__":
    recdir, pfile, s0, a, b, outf = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), sys.argv[6]
    with get_context("spawn").Pool(6, initializer=init, initargs=(recdir, pfile, s0, a)) as p:
        res = p.map(one, range(a, b), chunksize=8)
    res = {sd: r for sd, r in res if r is not None}
    pickle.dump(res, open(outf, "wb"))
    def conf(name, pred, truth, cond):
        n = [(pred(r), truth(r)) for r in res.values() if cond(r)]
        tp = sum(1 for p_, t in n if p_ and t); fp = sum(1 for p_, t in n if p_ and not t); fn = sum(1 for p_, t in n if not p_ and t); tn = sum(1 for p_, t in n if not p_ and not t)
        print(f"{name}: n {len(n)} emulated-ok & real-ok {tp}, emulated-ok & real-fail {fp}, emulated-fail & real-ok {fn}, both fail {tn}")
    c = lambda k, r: len(r["ok"]) > k          # noqa: E731
    conf("pass 2 (v2)", lambda r: r["v2"] > 0, lambda r: r["ok"][1], lambda r: c(1, r) and r["ok"][0])
    conf("pass 3 (v3)", lambda r: r["v3"] > 0, lambda r: r["ok"][2], lambda r: c(2, r) and r["ok"][0] and r["ok"][1])
    conf("pass 4 (v4)", lambda r: r["v4"] > 0, lambda r: r["ok"][3], lambda r: c(3, r) and all(r["ok"][:3]))
