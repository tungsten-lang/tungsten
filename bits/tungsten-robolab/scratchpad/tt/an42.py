import json, numpy as np
rows=[json.loads(l) for l in open("out/tt_r10/champ_710000.jsonl")]
rows=[r for r in rows if "error" not in r]
def at_height(p,v,zt):
    px,pz=p[0],p[2]; vx,vz=v[0],v[2]
    disc=vz*vz+2*9.81*(pz-0.805); tb=(vz+np.sqrt(disc))/9.81
    px=px+vx*tb; vz=-(vz-9.81*tb)*0.99; vx=vx*0.996; pz=0.805
    d=vz*vz-2*9.81*(zt-pz); t=vz/9.81
    if d>0: t=(vz-np.sqrt(d))/9.81
    t=max(t,0.0)
    return px+vx*t, vx, vz
def zat(p,v,x):
    px,pz=p[0],p[2]; vx,vz=v[0],v[2]
    disc=vz*vz+2*9.81*(pz-0.805); tb=(vz+np.sqrt(disc))/9.81
    px=px+vx*tb; vz=-(vz-9.81*tb)*0.99; vx=vx*0.996; pz=0.805
    th=(x-px)/vx
    return pz+vz*th-4.905*th*th, tb+th
XH=[];ZL=[];ZH=[]
for r in rows:
    s=r["serve"]; xh,vx,vz=at_height(s[0:3],s[3:6],1.25)
    XH.append(xh); ZL.append(zat(s[0:3],s[3:6],1.45)[0]); ZH.append(zat(s[0:3],s[3:6],2.0)[0])
XH=np.array(XH); ZL=np.array(ZL); ZH=np.array(ZH)
print("x where the ball rises through z_hit 1.25: quantiles 5/25/50/75/95:",np.quantile(XH,[.05,.25,.5,.75,.95]).round(2))
print("fraction with xh > 2.0 (clamped at x_hi): %.2f ; xh < 1.45 (clamped at x_lo): %.2f"%((XH>2.0).mean(),(XH<1.45).mean()))
print("ball height at the clamped plane: at x=2.0 for xh>2.0: mean %.3f (target 1.25)"%ZH[XH>2.0].mean() if (XH>2.0).any() else "")
print("ball height at x=1.45 for xh<1.45: mean %.3f"%ZL[XH<1.45].mean() if (XH<1.45).any() else "")
# effective crossing-height sd given clamp
zc=np.where(XH>2.0,ZH,np.where(XH<1.45,ZL,1.25))
print("crossing height at the (clamped) plane: mean %.3f sd %.3f ; with x_hi 2.4: "%(zc.mean(),zc.std()), end="")
zc2=np.where(XH>2.4,[zat(r["serve"][0:3],r["serve"][3:6],2.4)[0] for r in rows],np.where(XH<1.45,ZL,1.25))
print("mean %.3f sd %.3f"%(zc2.mean(),zc2.std()))
succ=np.array([r["solved"]>0 for r in rows])
for lo,hi in [(0,1.45),(1.45,1.6),(1.6,1.75),(1.75,1.9),(1.9,2.0),(2.0,2.2),(2.2,9)]:
    m=(XH>=lo)&(XH<hi)
    if m.sum(): print("  xh %.2f-%.2f: n %3d solved %.0f%% hit %.0f%%"%(lo,hi,m.sum(),100*succ[m].mean(),100*np.mean([rows[i]["hit"]>0 for i in np.nonzero(m)[0]])))
