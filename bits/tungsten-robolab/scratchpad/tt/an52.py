"""Round 10: how predictable from the serve alone (ball-only features) are the contact offset, pad velocity and pad pose?"""
import json, sys, numpy as np
sys.path.insert(0,"scratchpad/tt")
from ttfeat import cross, cv, quad, features
rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
rows=[r for r in rows if "error" not in r and r.get("hit") and r.get("pad_normal") and r.get("ball_pos_out") and r.get("paddle_vel")]
feats=features
for side,name in ((1,"forehand"),(2,"backhand")):
    R=[r for r in rows if r["side"]==side]
    X=np.array([feats(r) for r in R])
    pad=np.array([r["pad_at_contact"] for r in R]); bo=np.array([r["ball_pos_out"] for r in R]); pv=np.array([r["paddle_vel"] for r in R])
    off=bo-pad
    tgt={"contact time":np.array([r["t_contact"] for r in R]),"offset y (ball-pad)":off[:,1]*100,"offset z (ball-pad, cm)":off[:,2]*100,
         "pad x (cm)":pad[:,0]*100,"pad z (cm)":pad[:,2]*100,"pad vel x":pv[:,0],"pad vel y":pv[:,1],"pad vel z":pv[:,2]}
    print(name,"n",len(R))
    for lab,y in tgt.items():
        out=[]
        for tag,XX,lam in (("lin",X,1e-2),("quad",quad(X),1e-1)):
            p=cv(XX,y,lam=lam); out.append(f"{tag}: {np.std(y-p):7.3f} (R2 {1-np.var(y-p)/np.var(y):4.2f})")
        print(f"  {lab:24s} sd {y.std():7.3f} -> "+" | ".join(out))
