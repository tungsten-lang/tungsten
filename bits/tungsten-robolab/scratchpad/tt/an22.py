import json, sys, numpy as np, time
sys.argv=["x","out/tt_r10/champ_710000.jsonl"]
src=open("scratchpad/tt/an14.py").read().split("sub=list(range(0,len(hits),4))")[0]
exec(src)
DEL=np.arange(-0.25,1.51,0.125)
import builtins
t0=time.time()
for svv in [0.7,0.5,0.35,0.2,0.1]:
    sv=svv
    out={"d0":[],"best":[],"lin":[]}
    for i in range(0,len(hits),4):
        r=hits[i]; vin=np.array(r["ball_in_exact"]); pos=np.array(r["ball_pos_out"]); s=r["side"]
        P=P_design(vin,pos,s)
        d0=int(np.argmin(np.abs(DEL)))
        out["d0"].append(P[d0].max()); out["best"].append(P.max())
        u=np.clip(0.47*(np.linalg.norm(vin)-4.83),0,1.2)
        out["lin"].append(P[int(np.argmin(np.abs(DEL-u)))].max())
    print("pad-velocity noise sd %.2f: P(success|hit): still %.3f | linear retreat law %.3f | oracle best delta %.3f  (%.0fs)"%(svv,np.mean(out["d0"]),np.mean(out["lin"]),np.mean(out["best"]),time.time()-t0))
