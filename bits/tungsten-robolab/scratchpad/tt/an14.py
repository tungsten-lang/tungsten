import json, sys, numpy as np, time
sys.path.insert(0,"playground")
import tt_impact as ti
rows=[json.loads(l) for l in open(sys.argv[1])]
rows=[r for r in rows if "error" not in r]
hits=[r for r in rows if r.get("hit") and r.get("paddle_vel") and r.get("pad_normal") and r.get("ball_in_exact") and r.get("aim_normal")]
def orient(n):
    n=np.asarray(n,float); return n*np.sign(n[...,0:1]+1e-12)
E,ALPHA,MU=0.95,0.9,0.012
side=np.array([r["side"] for r in hits])
N=np.array([orient(r["pad_normal"]) for r in hits]); A=np.array([orient(r["aim_normal"]) for r in hits])
ph,ya=ti.angles_from_normal(N); pa,yaa=ti.angles_from_normal(A)
print("side pitch actual mean/std (deg):",[(s,np.degrees(ph[side==s].mean()).round(1),np.degrees(ph[side==s].std()).round(1)) for s in (1,2)])
print("side yaw-actual minus yaw-aim mean/std:",[(s,np.degrees((ya-yaa)[side==s].mean()).round(1),np.degrees((ya-yaa)[side==s].std()).round(1)) for s in (1,2)])
# empirical pitch residuals per side (actual pitch - side mean pitch); yaw residuals (actual - aim)
res_p={s:ph[side==s]-ph[side==s].mean() for s in (1,2)}
res_y={s:(ya-yaa)[side==s]-(ya-yaa)[side==s].mean() for s in (1,2)}
mean_p={s:ph[side==s].mean() for s in (1,2)}
vres=np.array([r["paddle_vel"] for r in hits]); print("pad vel components std",vres.std(0).round(2))
rng=np.random.default_rng(5); NS=120
DEL=np.arange(-0.5,2.01,0.125); YW=np.radians(np.arange(-40,41,4.0))
sv=0.35
def P_design(vin,pos,s,pitch_shift=0.0):
    """P over (delta, yaw-aim) with fixed nominal pitch mean_p[s]+shift, empirical residuals."""
    ip=rng.integers(0,len(res_p[s]),NS); iy=rng.integers(0,len(res_y[s]),NS)
    Pp=mean_p[s]+pitch_shift+res_p[s][ip]            # (NS,)
    out=np.zeros((len(DEL),len(YW)))
    vn=sv*rng.standard_normal((NS,3))
    for a,d in enumerate(DEL):
        vp=np.array([d,0,0])[None,:]+vn
        for b,y0 in enumerate(YW):
            Y=y0+res_y[s][iy]
            n=np.stack([np.cos(Pp)*np.cos(Y),np.cos(Pp)*np.sin(Y),np.sin(Pp)],axis=-1)
            v=ti.impact(vin,ALPHA*vp,n,E,MU)
            out[a,b]=ti.landing_ok(pos,v).mean()
    return out
sub=list(range(0,len(hits),4))
t0=time.time()
tot={"as_is":[],"d0":[],"bestd":[],"const":[],"bestboth":[]}
spd=[]
for i in sub:
    r=hits[i]; vin=np.array(r["ball_in_exact"]); pos=np.array(r["ball_pos_out"]); s=r["side"]
    P=P_design(vin,pos,s)
    d0=int(np.argmin(np.abs(DEL)))
    tot["d0"].append(P[d0].max())            # best yaw at delta=0
    tot["bestd"].append(P.max())              # best delta and yaw
    dc=int(np.argmin(np.abs(DEL-0.4))); tot["const"].append(P[dc].max())
    spd.append(np.linalg.norm(vin))
spd=np.array(spd)
print("P(success|hit) with FIXED side pitch, empirical noise, pad-vel noise 0.35: delta=0: %.3f ; delta=0.4 const: %.3f ; best delta per serve (best yaw): %.3f   (%.0fs)"%(np.mean(tot["d0"]),np.mean(tot["const"]),np.mean(tot["bestd"]),time.time()-t0))
for lo,hi in [(0,5.2),(5.2,5.6),(5.6,6.0),(6.0,6.5),(6.5,9)]:
    m=(spd>=lo)&(spd<hi)
    print("  v %.1f-%.1f n=%d: d=0 %.2f, d=0.4 %.2f, best d %.2f"%(lo,hi,m.sum(),np.mean(np.array(tot["d0"])[m]),np.mean(np.array(tot["const"])[m]),np.mean(np.array(tot["bestd"])[m])))

# best delta by speed and side
print("best delta by ball speed (fixed side pitch design):")
bd=[];sp2=[];sd2=[];bp=[]
for i in range(0,len(hits),3):
    r=hits[i]; vin=np.array(r["ball_in_exact"]); pos=np.array(r["ball_pos_out"]); s=r["side"]
    P=P_design(vin,pos,s)
    a,b=np.unravel_index(np.argmax(P),P.shape)
    # use smoothed argmax: mean of deltas within 0.02 of the max
    Pd=P.max(1); ok=Pd>=Pd.max()-0.02
    bd.append(DEL[ok].mean()); sp2.append(np.linalg.norm(vin)); sd2.append(s); bp.append(Pd.max())
bd=np.array(bd);sp2=np.array(sp2);sd2=np.array(sd2);bp=np.array(bp)
for s in (1,2):
    for lo,hi in [(0,5.0),(5.0,5.4),(5.4,5.8),(5.8,6.2),(6.2,6.6),(6.6,9)]:
        m=(sp2>=lo)&(sp2<hi)&(sd2==s)
        if m.sum()>2: print("  side %d v %.1f-%.1f n=%d: best delta mean %.2f (sd %.2f)  P %.2f"%(s,lo,hi,m.sum(),bd[m].mean(),bd[m].std(),bp[m].mean()))
A=np.c_[np.ones(len(bd)),sp2]
c=np.linalg.lstsq(A,bd,rcond=None)[0]; print("linear fit delta* = %.2f + %.2f * v  ->  zero at v=%.2f"%(c[0],c[1],-c[0]/c[1]))
