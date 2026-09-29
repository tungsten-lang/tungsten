import json, sys, numpy as np
sys.path.insert(0,"playground")
import tt_impact as ti, tt_aimlaw as al
rows=[json.loads(l) for l in open("out/tt_r10/champ_710000.jsonl")]
rows=[r for r in rows if "error" not in r]
hits=[r for r in rows if r.get("hit") and r.get("aim_normal") and r.get("paddle_vel") and r.get("pad_normal") and r.get("ball_in_exact")]
E,ALPHA,MU=0.95,0.9,0.012
def orient(n):
    n=np.asarray(n,float); return n*np.sign(n[...,0:1]+1e-12)
def run(e_pad,mu_t,pvg,nzb,tag):
    P=dict(al.DEFAULTS); P.update(nz_bias=nzb,e_pad=e_pad,mu_t=mu_t)
    res=[]
    for r in hits[::3]:
        vin=np.array(r["ball_in_exact"]); pos=np.array(r["ball_pos_out"])
        plan=[0.02,pos[1],pos[2],*vin]; xp=pos[0]
        n_cur=orient(r["pad_normal"])
        u=float(np.clip(0.47*(np.linalg.norm(vin)-4.83),0,1.2))
        for name,uu in [("still",0.0),("retreat",u)]:
            vp_aim=np.array([pvg*uu,0,0])
            tx,ty=al.choose_target(plan,n_cur,xp,vp_aim,P)
            n_aim,s=al.aim_normal(plan,tx,ty,xp,vp_aim,P)
            n_aim=orient(n_aim)
            vout=ti.impact(vin,ALPHA*np.array([uu,0,0]),n_aim,E,MU)
            ok=bool(ti.landing_ok(pos,vout))
            xl=None
            res.append((name,ok,np.degrees(np.arcsin(vout[2]/np.linalg.norm(vout))),np.linalg.norm(vout),np.degrees(np.arcsin(n_aim[2])),tx,ty))
    for name in ("still","retreat"):
        v=np.array([x[1:] for x in res if x[0]==name],float)
        print(tag,name,": aim lands %.2f | exit elev %.0f+-%.0f speed %.2f | aim pitch %.1f+-%.1f | target x %.2f y %.2f"%(v[:,0].mean(),v[:,1].mean(),v[:,1].std(),v[:,2].mean(),v[:,3].mean(),v[:,3].std(),v[:,4].mean(),v[:,5].mean()))
run(1.0,0.0,0.9,0.0,"e_pad 1.0 mu 0   nz_bias 0   :")
run(0.95,0.012,0.9,0.0,"e_pad .95 mu .012 nz_bias 0  :")
run(0.95,0.012,1.0,0.0,"e_pad .95 mu .012 pvg 1.0    :")
run(1.0,0.0,0.9,-0.13,"champion trims nz_bias -0.13 :")
