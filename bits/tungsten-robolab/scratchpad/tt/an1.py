import json, sys, numpy as np
sys.path.insert(0,"playground")
import tt_impact as ti
rows=[json.loads(l) for l in open(sys.argv[1])]
rows=[r for r in rows if "error" not in r]
print("episodes",len(rows),"solved",sum(r["solved"]>0 for r in rows),"hit",sum(r["hit"]>0 for r in rows))
hits=[r for r in rows if r.get("hit") and r.get("ball_out_exact") and r.get("paddle_vel")]
print("hits with data",len(hits))
vin=np.array([r["ball_in_exact"] for r in hits]); vp=np.array([r["paddle_vel"] for r in hits]); n=np.array([r["pad_normal"] for r in hits]); vout=np.array([r["ball_out_exact"] for r in hits])
p_out=np.array([r["ball_pos_out"] for r in hits])
# model residuals
for e,mu in [(1.0,0.0),(0.97,0.0),(0.97,0.011)]:
    pred=ti.impact(vin,vp,n,e,mu)
    res=vout-pred
    print("e",e,"mu",mu,"resid mean",res.mean(0).round(3),"std",res.std(0).round(3), "speed ratio out/in median", np.median(np.linalg.norm(vout,axis=1)/np.linalg.norm(vin,axis=1)).round(3))
# least squares e, mu, kick
u=vin-vp
un=np.sum(u*n,axis=1,keepdims=True)
# vout - vp = a u - b un n + kick ez
A=[];B=[]
for i in range(len(hits)):
    for c in range(3):
        row=[u[i,c], -un[i,0]*n[i,c], 1.0 if c==2 else 0.0]
        A.append(row); B.append(vout[i,c]-vp[i,c])
A=np.array(A);B=np.array(B)
sol,res,rk,sv=np.linalg.lstsq(A,B,rcond=None)
print("lstsq a,b,kick",sol.round(4), "-> mu",1-sol[0],"e",sol[1]-1+ (1-sol[0]) )
pred=vp+sol[0]*u-sol[1]*un*n+np.array([0,0,sol[2]])
print("fit resid std",(vout-pred).std(0).round(3))
# flight validation
lab=[];okp=0;okn=0
tot=0
for i,r in enumerate(hits):
    l,x,y,t=ti.flight(p_out[i],vout[i])
    lab.append(l)
    act=r.get("landed")
    tot+=1
    if (l=="opp")==(r["solved"]>0): okp+=1
print("flight(actual exit velocity) predicts solved on",okp,"of",tot)
from collections import Counter
print(Counter(zip(lab,[r.get("landed") for r in hits])))
