import json, sys, numpy as np
sys.path.insert(0,"playground")
import tt_impact as ti
exec(open("scratchpad/tt/an25.py").read().split("H=[r for r in rows")[0].split("rows=[json")[0])
rows=[json.loads(l) for l in open("out/tt_r10/champ_710000.jsonl")]
rows=[r for r in rows if "error" not in r]
def intercept(p,v,xh):
    px,py,pz=p; vx,vy,vz=v
    c=pz-0.805; disc=vz*vz+2*9.81*c
    tb=(vz+np.sqrt(disc))/9.81
    px=px+vx*tb; py=py+vy*tb; vz=-(vz-9.81*tb)*0.99; vx*=0.996; vy*=0.996; pz=0.805
    th=(xh-px)/vx
    return np.array([tb+th, py+vy*th, pz+vz*th-4.905*th*th, vx, vy, vz-9.81*th])
def feats(r):
    s=r["serve"]; c=intercept(s[0:3],s[3:6],1.75)
    return np.array([1.0,c[0]-0.53,c[1],c[2]-1.25,c[3]-5.2,c[4],c[5]-2.0])
H=[r for r in rows if r.get("hit") and r.get("paddle_vel") and r.get("pad_normal")]
def cv(F,Y,lam=1.0,seed=0):
    idx=np.arange(len(Y)); rng=np.random.default_rng(seed); rng.shuffle(idx); folds=np.array_split(idx,5); pred=np.zeros(len(Y))
    for fo in folds:
        tr=np.setdiff1d(idx,fo); w=np.linalg.solve(F[tr].T@F[tr]+lam*np.eye(F.shape[1]),F[tr].T@Y[tr]); pred[fo]=F[fo]@w
    return 1-((Y-pred)**2).mean()/Y.var(),np.sqrt(((Y-pred)**2).mean())
for side in (1,2):
    D=[r for r in H if r["side"]==side]
    F=np.array([feats(r) for r in D])
    V=np.array([r["paddle_vel"] for r in D])
    n=np.array([r["pad_normal"] for r in D]); n=n*np.sign(n[:,0:1])
    vn=(V*n).sum(1)
    print("side",side,"n",len(D))
    for nm,Y in [("vx",V[:,0]),("vy",V[:,1]),("vz",V[:,2]),("v.n",vn)]:
        r2,res=cv(F,Y)
        print("   pad %s: sd %.2f, CV R2 %.2f, residual sd %.2f"%(nm,Y.std(),r2,res))
    # exit speed etc
    vin=np.array([r["ball_in_exact"] for r in D]); sp=np.linalg.norm(vin,axis=1)
