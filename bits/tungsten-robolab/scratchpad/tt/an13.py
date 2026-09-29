import json, sys, numpy as np, time
sys.path.insert(0,"playground")
import tt_impact as ti
rows=[json.loads(l) for l in open(sys.argv[1])]
rows=[r for r in rows if "error" not in r]
hits=[r for r in rows if r.get("hit") and r.get("paddle_vel") and r.get("pad_normal") and r.get("ball_in_exact")]
def orient(n):
    n=np.asarray(n,float); return n*np.sign(n[...,0:1]+1e-12)
E,ALPHA,MU=0.95,0.9,0.012
rng=np.random.default_rng(3); NS=200
Z=rng.standard_normal((NS,5))
DEL=np.arange(-0.5,2.01,0.125)
def P_fixed_normal(vin,pos,n0,sp,sy,sv):
    # pad normal = n0 rotated by pitch/yaw noise ; velocity = delta*x + noise
    ph0,ya0=ti.angles_from_normal(n0)
    P=ph0+np.radians(sp*Z[:,0]); Y=ya0+np.radians(sy*Z[:,1])
    n=np.stack([np.cos(P)*np.cos(Y),np.cos(P)*np.sin(Y),np.sin(P)],axis=-1)
    out=[]
    for d in DEL:
        vp=np.array([d,0,0])[None,:]+sv*Z[:,2:5]
        v=ti.impact(vin,ALPHA*vp,n,E,MU)
        out.append(ti.landing_ok(pos,v).mean())
    return np.array(out)
sub=hits[::2]
for name,(sp,sy,sv) in {"noise 10/2.5/0.5":(10,2.5,0.5),"noise 5/2.5/0.3":(5,2.5,0.3)}.items():
    Pa=[];best=[];Pd0=[];bd=[];spd=[]
    for r in sub:
        vin=np.array(r["ball_in_exact"]); pos=np.array(r["ball_pos_out"]); n0=orient(r["pad_normal"])
        P=P_fixed_normal(vin,pos,n0,sp,sy,sv)
        # 'as is': delta = measured retreat along x
        vpx=r["paddle_vel"][0]
        Pa.append(np.interp(vpx,DEL,P)); best.append(P.max()); Pd0.append(P[np.argmin(np.abs(DEL))]); bd.append(DEL[np.argmax(P)]); spd.append(np.linalg.norm(vin))
    Pa=np.array(Pa);best=np.array(best);Pd0=np.array(Pd0);bd=np.array(bd);spd=np.array(spd)
    print(name,"| P(success|hit) champion-like (actual pad vx):",Pa.mean().round(3),"| delta=0:",Pd0.mean().round(3),"| best delta per serve:",best.mean().round(3))
    for lo,hi in [(0,5.2),(5.2,5.6),(5.6,6.0),(6.0,6.5),(6.5,9)]:
        m=(spd>=lo)&(spd<hi)
        print("   v %.1f-%.1f n=%d: as-is %.2f, d=0 %.2f, best %.2f, median best delta %.2f (IQR %.2f..%.2f)"%(lo,hi,m.sum(),Pa[m].mean(),Pd0[m].mean(),best[m].mean(),np.median(bd[m]),*np.quantile(bd[m],[.25,.75])))
