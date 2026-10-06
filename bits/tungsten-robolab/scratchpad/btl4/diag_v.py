"""Diagnose a fit_v result: per-criterion transitions on the active starts (base replay -> fitted replay), and the closed-loop-ok status of the base.

    OMP_NUM_THREADS=1 .venv/bin/python scratchpad/btl4/diag_v.py fit.npz [scale]
"""
import sys
import numpy as np
sys.path.insert(0, "scratchpad/btl4"); sys.path.insert(0, "scratchpad/btl2")
import rlib, fit_v
from multiprocessing import get_context

fn = sys.argv[1]
mult = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
z = np.load(fn)
stage = int(z["stage"]); knee = float(z["knee"]); scale = float(z["scale"]); x = z["x"] * mult
hand, bn = rlib.STAGES[stage]
cfg = {"hand": hand, "bounce_no": bn, "stage": stage, "gmax": float(z["gmax"]), "arr": {"pos_dz": 0.1, "vel_dz": 0.4, "target": None, "vt": None, "pre": stage > 0, "w_pos": 3.0, "w_vel": 0.5},
       "apex_min": 0.62, "reach": 0.14, "obj": {"w_apex": 5.0, "amin": 0.64, "w_pos": 3.0, "pos_dz": 0.1, "w_vel": 0.5, "vel_dz": 0.4}}

def job(a):
    sd, xx, uv, shift, ks = a
    J, s = fit_v.replay(sd, xx, uv, shift, ks)
    return sd, s

if __name__ == "__main__":
    seeds = [s for s in range(13001, 13841)]
    with get_context("spawn").Pool(6, initializer=fit_v.init_worker, initargs=(cfg,)) as pool:
        base = dict(pool.map(fit_v.base_job, seeds, chunksize=8))
        base = {k: v for k, v in base.items() if v is not None}
        okc = [b for b in base.values() if b["ok"] and b["summ"].get("bounced")]
        cfg["arr"]["target"] = [float(v) for v in np.mean([b["summ"]["arrive"] for b in okc], 0)]
        cfg["arr"]["vt"] = [float(v) for v in np.mean([b["summ"]["va"][:2] for b in okc], 0)]
    with get_context("spawn").Pool(6, initializer=fit_v.init_worker, initargs=(cfg,)) as pool:
        uv = {s: float(np.clip((knee - b["vzc"]) / scale, 0.0, 2.5)) for s, b in base.items()}
        act = [s for s in base if uv[s] > 0]
        shift = {s: rlib.LEAD - 0.0025 - base[s]["pt"] for s in base}
        r0 = dict(pool.map(job, [(s, None, 0.0, 0.0, base[s]["ks"]) for s in act], chunksize=8))
        r1 = dict(pool.map(job, [(s, x, uv[s], shift[s], base[s]["ks"]) for s in act], chunksize=8))
    def crit(sm):
        if not sm.get("bounced"):
            return {"touch": bool(sm.get("touch", False)), "bounced": False}
        tg = np.array(cfg["arr"]["target"])
        return {"touch": True, "bounced": True, "gate": sm.get("gate", 0) > 0, "nobody": sm.get("body", 9) == 0, "apex": sm.get("apex", 0) >= 0.62,
                "arrive": float(np.hypot(*(np.array(sm["arrive"]) - tg))) < 0.14}
    names = ["touch", "bounced", "gate", "nobody", "apex", "arrive"]
    for nm in names:
        c0 = sum(1 for s in act if crit(r0[s]).get(nm, False))
        c1 = sum(1 for s in act if crit(r1[s]).get(nm, False))
        print(f"  {nm:8s} {c0:4d} -> {c1:4d} of {len(act)}")
    ok0 = np.array([fit_v.proxy_ok(r0[s], cfg) for s in act]); ok1 = np.array([fit_v.proxy_ok(r1[s], cfg) for s in act])
    cl = np.array([base[s]["ok"] for s in act])
    print(f"proxy ok {ok0.sum()} -> {ok1.sum()}; of the closed-loop ok ({cl.sum()}): proxy {ok0[cl].sum()} -> {ok1[cl].sum()}; of the closed-loop not ok ({(~cl).sum()}): proxy {ok0[~cl].sum()} -> {ok1[~cl].sum()}")
    uvs = np.array([uv[s] for s in act])
    for lo, hi in ((0, 0.5), (0.5, 1.0), (1.0, 1.7), (1.7, 2.6)):
        m = (uvs > lo) & (uvs <= hi)
        print(f"  uv {lo:.1f}-{hi:.1f}: n {m.sum():3d} proxy ok {ok0[m].sum()} -> {ok1[m].sum()}  closed-loop ok {cl[m].sum()}")
