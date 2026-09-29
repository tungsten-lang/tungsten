import json, sys, numpy as np, time
sys.path.insert(0,"playground")
import tt_impact as ti
rows=[json.loads(l) for l in open("out/tt_r10/champ_710000.jsonl")]
rows=[r for r in rows if "error" not in r]
hits=[r for r in rows if r.get("hit") and r.get("ball_in_exact") and r.get("ball_pos_out") and r["side"]==1]
E,ALPHA,MU=0.95,0.9,0.012
rng=np.random.default_rng(9); NS=96
Z=rng.standard_normal((NS,5))
YW=np.radians(np.arange(-35,36,3.0))
def P_fixed(vin,pos,p0,sp,sy,sv,delta):
    Pp=np.radians(p0)+np.radians(sp)*Z[:,0]
    vp=np.array([delta,0,0])[None,:]+sv*Z[:,2:5]
    best=0
    for y0 in YW:
        Y=y0+np.radians(sy)*Z[:,1]
        n=np.stack([np.cos(Pp)*np.cos(Y),np.cos(Pp)*np.sin(Y),np.sin(Pp)],axis=-1)
        v=ti.impact(vin,ALPHA*vp,n,E,MU)
        best=max(best,ti.landing_ok(pos,v).mean())
    return best
sub=hits[::4]
print("forehand hits",len(sub),"| fixed pad velocity along the ball's travel delta=0.4 (sd 0.5), best yaw per serve; P(land|hit) by fixed pitch")
for (sp,sy,sv) in [(4,2.5,0.5),(6,2.5,0.5),(10,2.5,0.5)]:
    line=[]
    for p0 in [-21,-16,-11,-8,-5,-2,1,4]:
        line.append("%d:%.2f"%(p0,np.mean([P_fixed(np.array(r["ball_in_exact"]),np.array(r["ball_pos_out"]),p0,sp,sy,sv,0.4) for r in sub])))
    print("pitch sd %d: "%sp+"  ".join(line))
