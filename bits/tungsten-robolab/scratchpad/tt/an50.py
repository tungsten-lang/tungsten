"""Round 10: how much of the face-normal error to the aim is a function of the serve (CV ridge on serve features)."""
import json, sys, numpy as np
rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
rows=[r for r in rows if "error" not in r and r.get("hit") and r.get("pad_normal") and r.get("aim_normal_last")]
def feats(r):
    v=r["ball_in_exact"]; p=r["pad_at_contact"]
    return [1.0, r["t_contact"]-0.53, p[1], p[2]-1.2, v[0]-5, v[1], v[2], p[0]-1.8]
def cv(X,y,k=5,lam=1e-2):
    n=len(y); idx=np.arange(n); rng=np.random.default_rng(0); rng.shuffle(idx)
    pred=np.zeros(n)
    for f in range(k):
        te=idx[f::k]; tr=np.setdiff1d(idx,te)
        A=X[tr]; w=np.linalg.solve(A.T@A+lam*np.eye(A.shape[1]),A.T@y[tr]); pred[te]=X[te]@w
    return pred
for side,name in ((1,"forehand"),(2,"backhand")):
    R=[r for r in rows if r["side"]==side]
    X=np.array([feats(r) for r in R])
    def orient(n):
        n=np.array(n); return n if n[0]>0 else -n
    N=np.array([orient(r["pad_normal"]) for r in R]); A=np.array([orient(r["aim_normal_last"]) for r in R])
    ez=np.degrees(np.arcsin(np.clip(N[:,2],-1,1))-np.arcsin(np.clip(A[:,2],-1,1)))
    ey=np.degrees(np.arctan2(N[:,1],N[:,0])-np.arctan2(A[:,1],A[:,0]))
    print(name,"n",len(R))
    for lab,y in (("pitch err (deg)",ez),("yaw err (deg)",ey),("pad pitch itself",np.degrees(np.arcsin(np.clip(N[:,2],-1,1)))),("aim pitch",np.degrees(np.arcsin(np.clip(A[:,2],-1,1))))):
        p=cv(X,y)
        print(f"  {lab:18s} mean {y.mean():6.2f} sd {y.std():5.2f}  CV residual sd {np.std(y-p):5.2f}  CV R2 {1-np.var(y-p)/np.var(y):5.2f}")
