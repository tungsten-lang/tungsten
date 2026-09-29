import json, numpy as np
rows=[json.loads(l) for l in open("out/tt_r10/champ_710000.jsonl")]
rows=[r for r in rows if "error" not in r and r.get("hit") and r.get("t_contact")]
sp=np.array([np.linalg.norm(r["ball_in_exact"]) for r in rows]); tc=np.array([r["t_contact"] for r in rows]); sol=np.array([r["solved"]>0 for r in rows]); side=np.array([r["side"] for r in rows])
print("hits",len(rows),"corr(speed at contact, t_contact) = %.2f"%np.corrcoef(sp,tc)[0,1])
qs=np.quantile(sp,[0,.25,.5,.75,1])
for i in range(4):
    m=(sp>=qs[i])&(sp<=qs[i+1]); med=np.median(tc[m])
    e=m&(tc<med); l=m&(tc>=med)
    print("speed %.2f-%.2f (n %d): early contact (<%.3f) solved %.0f%% (n %d) | late solved %.0f%% (n %d)"%(qs[i],qs[i+1],m.sum(),med,100*sol[e].mean(),e.sum(),100*sol[l].mean(),l.sum()))
# by side
for s in (1,2):
    m=side==s
    print("side",s,": solved vs t_contact quartiles:",[ "%.0f%%"%(100*sol[m&(tc>=a)&(tc<b)].mean()) for a,b in zip(np.quantile(tc[m],[0,.25,.5,.75]),np.quantile(tc[m],[.25,.5,.75,1.01]))],"t edges",np.quantile(tc[m],[0,.25,.5,.75,1]).round(3))
