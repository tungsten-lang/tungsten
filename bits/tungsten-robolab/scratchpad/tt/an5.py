import json, sys, numpy as np
sys.path.insert(0,"playground")
import tt_impact as ti
rows=[json.loads(l) for l in open(sys.argv[1])]
rows=[r for r in rows if "error" not in r]
print("episodes",len(rows),"solved",sum(r["solved"]>0 for r in rows))
# serve speed classes: initial serve velocity
def cls(r):
    v=np.array(r["serve"][3:6]); return np.linalg.norm(v)
sp=np.array([cls(r) for r in rows])
sol=np.array([r["solved"]>0 for r in rows]); hit=np.array([r["hit"]>0 for r in rows])
side=np.array([r["side"] for r in rows])
print("serve initial speed: mean %.2f std %.2f range %.2f..%.2f"%(sp.mean(),sp.std(),sp.min(),sp.max()))
qs=np.quantile(sp,[0,0.2,0.4,0.6,0.8,1.0])
for i in range(5):
    m=(sp>=qs[i])&(sp<=qs[i+1])
    print("serve speed %.2f-%.2f: n %d hit %.0f%% solved %.0f%%   (fh solved %d/%d, bh %d/%d)"%(qs[i],qs[i+1],m.sum(),100*hit[m].mean(),100*sol[m].mean(), sol[m&(side==1)].sum(),(m&(side==1)).sum(), sol[m&(side==2)].sum(),(m&(side==2)).sum()))
# other serve features
S=np.array([r["serve"] for r in rows])   # x y z vx vy vz
tc=np.array([r.get("t_contact",np.nan) for r in rows])
for name,col in [("x0",0),("y0",1),("z0",2),("vx",3),("vy",4),("vz",5)]:
    x=S[:,col]; qs=np.quantile(x,[0,0.25,0.5,0.75,1.0])
    out=[]
    for i in range(4):
        m=(x>=qs[i])&(x<=qs[i+1]); out.append("%.2f..%.2f: %.0f%%"%(qs[i],qs[i+1],100*sol[m].mean()))
    print(name," | ".join(out))
m=hit
print("contact time quartiles solved:")
qs=np.nanquantile(tc[m],[0,0.25,0.5,0.75,1.0])
for i in range(4):
    mm=m&(tc>=qs[i])&(tc<=qs[i+1]); print("  t %.2f-%.2f: n %d solved %.0f%%"%(qs[i],qs[i+1],mm.sum(),100*sol[mm].mean()))
