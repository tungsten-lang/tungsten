import json, sys, numpy as np
sys.path.insert(0,"playground")
import tt_impact as ti
from scipy.optimize import least_squares
def load(p):
    return [json.loads(l) for l in open(p)]
def prep(rows):
    H=[r for r in rows if "error" not in r and r.get("hit") and r.get("ball_out_exact") and r.get("paddle_vel")]
    return (np.array([r["ball_in_exact"] for r in H]),np.array([r["paddle_vel"] for r in H]),np.array([r["pad_normal"] for r in H]),np.array([r["ball_out_exact"] for r in H]),np.array([r["ball_pos_out"] for r in H]),np.array([r["solved"]>0 for r in H]))
for name in sys.argv[1:]:
    vin,vp,n,vout,pos,sol=prep(load(name))
    def resid(p): 
        e,alpha,mu=p
        return (ti.impact(vin,alpha*vp,n,e,mu)-vout).ravel()
    s=least_squares(resid,[0.95,0.9,0.01],loss="soft_l1",f_scale=0.5)
    r=resid(s.x).reshape(-1,3)
    print(name.split("/")[-1],"n",len(vin),"e %.3f alpha %.3f mu %.3f"%tuple(s.x),"median|res| %.3f"%np.median(np.abs(r)),"| fraction of |res|<0.7: %.2f"%np.mean(np.linalg.norm(r,axis=1)<0.7))
