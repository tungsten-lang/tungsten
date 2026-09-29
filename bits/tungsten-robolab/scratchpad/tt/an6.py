import json, sys, numpy as np
sys.path.insert(0,"playground")
import tt_impact as ti
from scipy.optimize import least_squares
rows=[json.loads(l) for l in open(sys.argv[1])]
rows=[r for r in rows if "error" not in r]
hits=[r for r in rows if r.get("hit") and r.get("ball_out_exact") and r.get("paddle_vel")]
vin=np.array([r["ball_in_exact"] for r in hits]); vp=np.array([r["paddle_vel"] for r in hits]); n=np.array([r["pad_normal"] for r in hits]); vout=np.array([r["ball_out_exact"] for r in hits])
def model(p, vin, vp, n):
    e, alpha, mu, kz = p
    return ti.impact(vin, alpha*vp, n, e, mu, kz)
def resid(p):
    return (model(p,vin,vp,n)-vout).ravel()
for m0,name in [(np.ones(len(hits),bool),"all")]:
    sol=least_squares(resid,[1.0,1.0,0.0,0.0],loss="soft_l1",f_scale=0.5)
    print(name,"e %.3f alpha %.3f mu %.3f kz %.3f"%tuple(sol.x),"resid rms %.3f (robust)"%np.sqrt(np.mean(resid(sol.x)**2)), "median abs %.3f"%np.median(np.abs(resid(sol.x))))
    sol0=least_squares(lambda p: resid([p[0],1.0,p[1],0.0]),[1.0,0.0],loss="soft_l1",f_scale=0.5)
    print("alpha=1 fixed: e %.3f mu %.3f"%tuple(sol0.x), "median abs %.3f"%np.median(np.abs(resid([sol0.x[0],1.0,sol0.x[1],0.0]))))
# small pad speed subset
sp=np.linalg.norm(vp,axis=1)
m=sp<0.4
print("n small-pad-speed hits",m.sum())
def resid2(p): 
    e,mu,kz=p
    return (ti.impact(vin[m],vp[m],n[m],e,mu,kz)-vout[m]).ravel()
s2=least_squares(resid2,[1.0,0.0,0.0],loss="soft_l1",f_scale=0.3)
print("slow pad: e %.3f mu %.3f kz %.3f median abs resid %.3f rms %.3f"%(*s2.x,np.median(np.abs(resid2(s2.x))),np.sqrt(np.mean(resid2(s2.x)**2))))
r=resid2(s2.x).reshape(-1,3)
print("resid mean",r.mean(0).round(3),"std",r.std(0).round(3))
# ratio of exit speed to incoming for slow pad
print("slow pad exit/in speed", np.median(np.linalg.norm(vout[m],axis=1)/np.linalg.norm(vin[m],axis=1)).round(3))
