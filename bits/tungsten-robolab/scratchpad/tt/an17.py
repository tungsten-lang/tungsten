import json, sys, numpy as np, time
sys.argv=["x","out/tt_r10/champ_710000.jsonl"]
exec(open("scratchpad/tt/an14.py").read().split("sub=list(range(0,len(hits),4))")[0])
DEL=np.arange(-0.25,1.51,0.125)
t0=time.time()
for shift in [-20,-15,-10,-5,0,5,10,15,20]:
    out={1:[],2:[]}
    for i in range(0,len(hits),4):
        r=hits[i]; vin=np.array(r["ball_in_exact"]); pos=np.array(r["ball_pos_out"]); s=r["side"]
        P=P_design(vin,pos,s,pitch_shift=np.radians(shift))
        out[s].append(P.max())
    print("nominal pitch shift %+3d deg: P(success|hit) with best delta+yaw: forehand %.3f (n%d) backhand %.3f (n%d)  (%.0fs)"%(shift,np.mean(out[1]),len(out[1]),np.mean(out[2]),len(out[2]),time.time()-t0))
