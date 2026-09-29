"""Round 10: face-normal error to the aim as a function of BALL-ONLY features (no pad outcomes), CV ridge."""
import json, sys, numpy as np
rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
rows=[r for r in rows if "error" not in r and r.get("hit") and r.get("pad_normal") and r.get("aim_normal_last")]
def cross(p, v, xh):
    px,py,pz=p; vx,vy,vz=v
    disc=vz*vz+2*9.81*(pz-0.805); tb=(vz+np.sqrt(disc))/9.81
    px+=vx*tb; py+=vy*tb; vz=-(vz-9.81*tb)*0.99; vx*=0.996; vy*=0.996; pz=0.805
    th=(xh-px)/vx
    return th+tb, py+vy*th, pz+vz*th-4.905*th*th, vx, vy, vz-9.81*th
def feats(r, xh=1.8, kind="ball"):
    s=r["serve"]; t,y,z,vx,vy,vz=cross(s[:3],s[3:],xh)
    f=[1.0, t-0.54, y, z-1.27, vx-5, vy, vz+2.0]
    if kind=="ball+t": f.append(r["t_contact"]-0.53)
    return f
def cv(X,y,k=5,lam=1e-2,reps=5):
    n=len(y); best=np.zeros(n)
    for rep in range(reps):
        idx=np.arange(n); rng=np.random.default_rng(rep); rng.shuffle(idx); pred=np.zeros(n)
        for f in range(k):
            te=idx[f::k]; tr=np.setdiff1d(idx,te)
            A=X[tr]; w=np.linalg.solve(A.T@A+lam*np.eye(A.shape[1]),A.T@y[tr]); pred[te]=X[te]@w
        best+=pred/reps
    return best
def quad(X):
    # add squares and pairwise products of the non-constant features
    F=X[:,1:]; cols=[X]
    n=F.shape[1]
    for i in range(n):
        for j in range(i,n): cols.append((F[:,i]*F[:,j])[:,None])
    return np.hstack(cols)
for side,name in ((1,"forehand"),(2,"backhand")):
    R=[r for r in rows if r["side"]==side]
    def orient(n):
        n=np.array(n); return n if n[0]>0 else -n
    N=np.array([orient(r["pad_normal"]) for r in R]); A=np.array([orient(r["aim_normal_last"]) for r in R])
    ez=np.degrees(np.arcsin(np.clip(N[:,2],-1,1))-np.arcsin(np.clip(A[:,2],-1,1)))
    ey=np.degrees(np.arctan2(N[:,1],N[:,0])-np.arctan2(A[:,1],A[:,0]))
    pz=np.degrees(np.arcsin(np.clip(N[:,2],-1,1)))
    print(name,"n",len(R))
    for kind in ("ball","ball+t"):
        X=np.array([feats(r,kind=kind) for r in R])
        for tag,XX in (("lin",X),("quad",quad(X))):
            out=[]
            for lab,y in (("pitch err",ez),("yaw err",ey),("pad pitch",pz)):
                p=cv(XX,y,lam=1e-1 if tag=="quad" else 1e-2)
                out.append(f"{lab}: sd {y.std():5.2f} -> {np.std(y-p):5.2f} (R2 {1-np.var(y-p)/np.var(y):4.2f})")
            print(f"  {kind:7s} {tag:4s} "+" | ".join(out))
