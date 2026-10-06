"""Pass success vs the incoming ball state at each stage's trigger, from the 240 training records (closed loop, btl3-e + final_e)."""
import sys
import numpy as np
sys.path.insert(0, "scratchpad/btl4")
import rlib
from multiprocessing import Pool

def job(sd):
    d = rlib.StartData(sd, f"out/btl4/rec/rec_{sd}.pkl")
    pl = d.rec["pass_log"]
    rows = {}
    for st in (0, 1, 2, 3):
        if st not in d.ks:
            continue
        ks = d.ks[st]
        bp, bv = d.rec["ball"][ks - 1], d.rec["ballv"][ks - 1]
        f, pt = d.stage_features(st)
        # pass index of the stage's pass: stage 0 = pass 0 (pl[0] is the launch pass BR), ... (pl[st])
        ok = bool(pl[st]["ok"]) if st < len(pl) else False
        released = st < len(pl)
        apex_in = None
        rows[st] = dict(ok=ok, vin=bv.copy(), pin=bp.copy(), cross=f[:2].copy(), pt=pt, wr=f[2 + 4], f=f)
    return sd, rows

if __name__ == "__main__":
    with Pool(6) as p:
        res = dict(p.map(job, range(13001, 13241)))
    for st in (1, 2, 3):
        R = [r[st] for r in res.values() if st in r]
        ok = np.array([r["ok"] for r in R])
        print(f"=== stage {st}: n {len(R)} ok {ok.sum()} ({100*ok.mean():.0f} %)")
        feats = {"cross_x": [r["cross"][0] for r in R], "cross_y": [r["cross"][1] for r in R], "vin_x": [r["vin"][0] for r in R], "vin_y": [r["vin"][1] for r in R], "vin_z": [r["vin"][2] for r in R],
                 "pin_z": [r["pin"][2] for r in R], "wrist_proxy": [r["wr"] for r in R]}
        for nm, v in feats.items():
            v = np.array(v)
            qs = np.quantile(v, [0.2, 0.4, 0.6, 0.8])
            b = np.digitize(v, qs)
            print(f"  {nm:12s} corr {np.corrcoef(v, ok)[0,1]:+.2f}  ok by quintile: " + " ".join(f"{ok[b==i].mean()*100:3.0f}%" for i in range(5)) + f"   (edges {np.round(qs,3).tolist()})")
