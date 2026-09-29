import json, sys, numpy as np
sys.path.insert(0,"playground")
import tt_impact as ti, tt_aimlaw as al
rows=[json.loads(l) for l in open("out/tt_r10/champ_710000.jsonl")]
rows=[r for r in rows if "error" not in r]
hits=[r for r in rows if r.get("hit") and r.get("aim_normal") and r.get("paddle_vel") and r.get("pad_normal") and r.get("ball_in_exact")]
P=dict(al.DEFAULTS); P.update(nz_bias=-0.13002951725581915,land_x=-0.865,land_y=-0.1018,e_pad=1.0,mu_t=0.0)
E,ALPHA,MU=0.95,0.9,0.012
def orient(n):
    n=np.asarray(n,float); return n*np.sign(n[...,0:1]+1e-12)
def sp(v): return np.linalg.norm(v)
import collections
stats=collections.defaultdict(list)
for r in hits[::3]:
    vin=np.array(r["ball_in_exact"]); pos=np.array(r["ball_pos_out"]); side=r["side"]
    plan=[0.02,pos[1],pos[2],*vin]      # state at the plane
    xp=pos[0]
    n_cur=orient(r["pad_normal"])
    for name,u in [("still",0.0),("retreat",float(np.clip(0.47*(sp(vin)-4.83),0,1.2)))]:
        vp=np.array([0.9*u,0,0])
        tx,ty=al.choose_target(plan,n_cur,xp,vp,P)
        n_aim,s=al.aim_normal(plan,tx,ty,xp,vp,P)
        n_aim=orient(n_aim)
        # what this aim normal really does with the pad moving at u (impact model)
        vout=ti.impact(vin,ALPHA*np.array([u,0,0]),n_aim,E,MU)
        ok=bool(ti.landing_ok(pos,vout))
        el=np.degrees(np.arcsin(vout[2]/np.linalg.norm(vout)))
        pitch=np.degrees(np.arcsin(n_aim[2]))
        stats[name].append((ok,el,np.linalg.norm(vout),pitch,tx,ty,u))
for name,v in stats.items():
    v=np.array(v,float)
    print(name,": aimed normal lands (model, exact pad velocity): %.2f ; exit elevation mean %.0f (sd %.0f); exit speed %.2f ; aim pitch %.1f (sd %.1f); target x %.2f y %.2f ; mean u %.2f"%(v[:,0].mean(),v[:,1].mean(),v[:,1].std(),v[:,2].mean(),v[:,3].mean(),v[:,3].std(),v[:,4].mean(),v[:,5].mean(),v[:,6].mean()))
