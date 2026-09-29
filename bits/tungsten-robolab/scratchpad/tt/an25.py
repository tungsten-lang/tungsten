import json, sys, numpy as np
sys.path.insert(0,"playground")
import tt_impact as ti
np.set_printoptions(precision=3,suppress=True,linewidth=160)
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
H=[r for r in rows if r.get("hit") and r.get("aim_normal") and r.get("pad_normal")]
def orient(n):
    n=np.asarray(n,float); return n*np.sign(n[0]+1e-12)
for side in (1,2):
    D=[r for r in H if r["side"]==side]
    F=np.array([feats(r) for r in D])
    pa,ya=ti.angles_from_normal(np.array([orient(r["aim_normal"]) for r in D]))
    pt,yt=ti.angles_from_normal(np.array([orient(r["pad_normal"]) for r in D]))
    pa=np.degrees(pa);pt=np.degrees(pt);ya=np.degrees(ya);yt=np.degrees(yt)
    # follow ratio: regress actual pitch on aim pitch
    A=np.c_[np.ones(len(D)),pa]
    c=np.linalg.lstsq(A,pt,rcond=None)[0]
    print("side",side,"n",len(D),"| actual pitch = %.1f + %.2f * aim pitch (R2 %.2f), aim pitch sd %.1f, actual sd %.1f"%(c[0],c[1],1-np.var(pt-A@c)/np.var(pt),pa.std(),pt.std()))
    # features only
    for lam in [1.0]:
        for name,Y in [("pitch",pt),("yaw",yt)]:
            Fm=F.copy()
            w=np.linalg.solve(Fm.T@Fm+lam*np.eye(F.shape[1]),Fm.T@Y)
            res=Y-Fm@w
            # 5-fold CV R2
            idx=np.arange(len(D)); rng=np.random.default_rng(0); rng.shuffle(idx); folds=np.array_split(idx,5); pred=np.zeros(len(D))
            for fo in folds:
                tr=np.setdiff1d(idx,fo); ww=np.linalg.solve(Fm[tr].T@Fm[tr]+lam*np.eye(F.shape[1]),Fm[tr].T@Y[tr]); pred[fo]=Fm[fo]@ww
            print("   %s ~ serve features: R2 train %.2f, 5-fold CV %.2f (sd %.1f -> residual %.1f)"%(name,1-res.var()/Y.var(),1-((Y-pred)**2).mean()/Y.var(),Y.std(),np.sqrt(((Y-pred)**2).mean())))
    # actual pitch ~ aim + features
    A2=np.c_[F,pa]
    idx=np.arange(len(D)); rng=np.random.default_rng(1); rng.shuffle(idx); folds=np.array_split(idx,5); pred=np.zeros(len(D))
    for fo in folds:
        tr=np.setdiff1d(idx,fo); ww=np.linalg.solve(A2[tr].T@A2[tr]+1.0*np.eye(A2.shape[1]),A2[tr].T@pt[tr]); pred[fo]=A2[fo]@ww
    print("   pitch ~ features + aim pitch: 5-fold CV R2 %.2f residual sd %.1f"%(1-((pt-pred)**2).mean()/pt.var(),np.sqrt(((pt-pred)**2).mean())))

print("---- forehand coefficient study (standardised features)")
D=[r for r in H if r["side"]==1]
F=np.array([feats(r) for r in D])
names=["1","t_c-0.53","cross y","cross z-1.25","vx-5.2","vy","vz-2"]
pt=np.degrees(ti.angles_from_normal(np.array([orient(r["pad_normal"]) for r in D]))[0])
yt=np.degrees(ti.angles_from_normal(np.array([orient(r["pad_normal"]) for r in D]))[1])
# extra outcome variables
padz=np.array([r["pad_at_contact"][2] for r in D]); pady=np.array([r["pad_at_contact"][1] for r in D]); padx=np.array([r["pad_at_contact"][0] for r in D])
Fz=F[:,1:]; mu=Fz.mean(0); sd=Fz.std(0); Zs=(Fz-mu)/sd
for nm,Y in [("pitch",pt),("yaw",yt),("pad z",padz*100),("pad y",pady*100),("pad x",padx*100)]:
    A=np.c_[np.ones(len(D)),Zs]
    w=np.linalg.lstsq(A,Y,rcond=None)[0]
    res=Y-A@w
    print("%-6s R2 %.2f  sd %.2f | per-1sd coefficients: "%(nm,1-res.var()/Y.var(),Y.std())+"  ".join("%s %+.2f"%(n,c) for n,c in zip(names[1:],w[1:])))
print("feature sds:",dict(zip(names[1:],sd.round(2))))
print("feature corr matrix (1sd):"); print(np.corrcoef(Zs.T).round(2))
