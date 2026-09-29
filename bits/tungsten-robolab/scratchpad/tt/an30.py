import json, sys, numpy as np
sys.path.insert(0,"playground")
import tt_impact as ti
rows=[json.loads(l) for l in open("out/tt_r10/champ_710000.jsonl")]
rows=[r for r in rows if "error" not in r]
def binding(p0,v):
    x0,y0,z0=p0; vx,vy,vz=v
    if vx>=-0.3: return "not toward net"
    t1=-x0/vx; zn=z0+vz*t1-0.5*9.81*t1*t1
    disc=vz*vz+2*9.81*(z0-ti.Z_C)
    if disc<=0: return "no landing"
    t2=(vz+np.sqrt(disc))/9.81; xl=x0+vx*t2; yl=y0+vy*t2
    cand={"net (too low/short)":zn-(ti.NET_TOP+ti.R_BALL),"long (past far edge)":xl-ti.X_FAR,"short (own half)":-xl,"wide right":ti.Y_HI-yl,"wide left":yl-ti.Y_LO}
    k=min(cand,key=cand.get)
    return k if cand[k]<0 else "ok"
import collections
for side in (1,2):
    D=[r for r in rows if r["side"]==side]
    c=collections.Counter()
    for r in D:
        if not r.get("hit"): c["no hit"]+=1; continue
        p=np.array(r["ball_pos_out"]); off=np.array(r["ball_pos_out"])-np.array(r["pad_at_contact"])
        n=np.array(r["pad_normal"]); n=n/np.linalg.norm(n); inpl=off-(off@n)*n; rim=np.linalg.norm(inpl)>=0.1
        b=binding(p,np.array(r["ball_out_exact"]))
        if r["solved"]>0: c["solved"]+=1
        else: c[("RIM " if rim else "")+b]+=1
    print("side",side,"n",len(D))
    for k,v in c.most_common(): print("   %-28s %3d  (%.1f%%)"%(k,v,100*v/len(D)))
