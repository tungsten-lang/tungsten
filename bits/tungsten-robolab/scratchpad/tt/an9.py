import json, sys, numpy as np
sys.path.insert(0,"playground")
import tt_impact as ti
rows=[json.loads(l) for l in open(sys.argv[1])]
rows=[r for r in rows if "error" not in r]
hits=[r for r in rows if r.get("hit") and r.get("aim_normal") and r.get("paddle_vel") and r.get("pad_normal") and r.get("ball_in_exact")]
def orient(n):
    n=np.asarray(n,float); return n*np.sign(n[...,0:1]+1e-12)
E,ALPHA,MU=0.95,0.9,0.012
PH=np.arange(-60,61,1.0); YW=np.arange(-45,46,1.5)
NG=ti.normals_grid(PH,YW)   # (P,Y,3)
def feasible_mask(vin,vp,pos):
    v=ti.impact(vin,ALPHA*vp,NG.reshape(-1,3),E,MU).reshape(NG.shape)
    return ti.landing_ok(pos,v)
out=[]
for r in hits:
    vin=np.array(r["ball_in_exact"]); vp=np.array(r["paddle_vel"]); pos=np.array(r["ball_pos_out"])
    na=orient(r["aim_normal"]); nt=orient(r["pad_normal"])
    pa,ya=ti.angles_from_normal(na); pt,yt=ti.angles_from_normal(nt)
    M=feasible_mask(vin,vp,pos)
    # feasible pitch interval at the actual yaw and at the aim yaw
    def interval(yawdeg):
        j=int(np.argmin(np.abs(YW-yawdeg)))
        col=M[:,j]
        return col
    ja=int(np.argmin(np.abs(YW-np.degrees(ya)))); jt=int(np.argmin(np.abs(YW-np.degrees(yt))))
    col=M[:,ja]
    w=col.sum()
    # center of feasible pitch at aim yaw
    cen=PH[col].mean() if w>0 else np.nan
    out.append(dict(seed=r["seed"],side=r["side"],solved=r["solved"]>0,width=w,center=cen,aim_p=np.degrees(pa),act_p=np.degrees(pt),aim_y=np.degrees(ya),act_y=np.degrees(yt),
                    aim_ok=bool(M[int(np.argmin(np.abs(PH-np.degrees(pa)))),ja]),act_ok=bool(M[int(np.argmin(np.abs(PH-np.degrees(pt)))),jt]),
                    area=M.sum(), spd=np.linalg.norm(vin)))
import collections
W=np.array([o["width"] for o in out]); S=np.array([o["solved"] for o in out]); SD=np.array([o["side"] for o in out]); SP=np.array([o["spd"] for o in out])
print("feasible pitch width at the aim's yaw (deg): quantiles 10/25/50/75/90",np.quantile(W,[.1,.25,.5,.75,.9]))
for lo,hi in [(0,5.2),(5.2,5.6),(5.6,6.0),(6.0,6.5),(6.5,9)]:
    m=(SP>=lo)&(SP<hi)
    print("ball speed %.1f-%.1f n=%d: median feasible pitch width %.0f deg; frac aim in feasible set %.2f; actual in set %.2f; solved %.2f"%(lo,hi,m.sum(),np.median(W[m]),np.mean([o["aim_ok"] for o,mm in zip(out,m) if mm]),np.mean([o["act_ok"] for o,mm in zip(out,m) if mm]),S[m].mean()))
print("model: aim normal would land (with actual pad velocity): %.2f ; actual normal lands: %.2f ; actual solved %.2f"%(np.mean([o["aim_ok"] for o in out]),np.mean([o["act_ok"] for o in out]),S.mean()))
# Ideal aim = center of feasible pitch: expected success under pitch error N(mu, sd)
for side in (1,2):
    m=SD==side
    errs=np.array([o["act_p"]-o["aim_p"] for o in out])[m]
    print("side",side,"pitch err mean %.1f std %.1f"%(errs.mean(),errs.std()))
