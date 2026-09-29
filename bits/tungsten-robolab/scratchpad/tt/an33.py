import json, sys, numpy as np, time
sys.path.insert(0,"playground")
import tt_impact as ti
rows=[json.loads(l) for l in open("out/tt_r10/champ_710000.jsonl")]
rows=[r for r in rows if "error" not in r]
hits=[r for r in rows if r.get("hit") and r.get("ball_in_exact") and r.get("ball_pos_out") and r["side"]==1]
E,ALPHA,MU=0.95,0.9,0.012
rng=np.random.default_rng(7); NS=96
Z=rng.standard_normal((NS,5))
DEL=np.arange(-0.25,1.51,0.125); YW=np.radians(np.arange(-35,36,3.0))
def P_fixed_pitch(vin,pos,p0,sp,sy,sv):
    Pp=np.radians(p0)+np.radians(sp)*Z[:,0]
    vn=sv*Z[:,2:5]
    best=0.0
    out=np.zeros((len(DEL),len(YW)))
    for a,d in enumerate(DEL):
        vp=np.array([d,0,0])[None,:]+vn
        for b,y0 in enumerate(YW):
            Y=y0+np.radians(sy)*Z[:,1]
            n=np.stack([np.cos(Pp)*np.cos(Y),np.cos(Pp)*np.sin(Y),np.sin(Pp)],axis=-1)
            v=ti.impact(vin,ALPHA*vp,n,E,MU)
            out[a,b]=ti.landing_ok(pos,v).mean()
    return out
sub=hits[::4]
print("forehand hits used",len(sub),"of",len(hits))
t0=time.time()
for (sp_,sy_,sv_) in [(4,2.5,0.3),(4,2.5,0.5),(6,2.5,0.35),(10,2.5,0.5)]:
    line=[]
    for p0 in [-30,-25,-21,-16,-11,-6,-1,4]:
        Ps=[]
        for r in sub:
            vin=np.array(r["ball_in_exact"]); pos=np.array(r["ball_pos_out"])
            P=P_fixed_pitch(vin,pos,p0,sp_,sy_,sv_)
            Ps.append(P.max())
        line.append("%d:%.2f"%(p0,np.mean(Ps)))
    print("pitch sd %.0f yaw sd %.1f vel sd %.2f | P(success|hit) with best retreat+yaw at fixed pitch (deg): "%(sp_,sy_,sv_)+"  ".join(line)+"   (%.0fs)"%(time.time()-t0))
