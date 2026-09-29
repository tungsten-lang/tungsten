import json, sys, numpy as np, collections
sys.path.insert(0,"playground"); sys.path.insert(0,"playground/tasks")
import tt_impact as ti
from tasks.myo_tt import failure_class
def binding(p0,v):
    x0,y0,z0=p0; vx,vy,vz=v
    if vx>=-0.3: return "not toward net"
    t1=-x0/vx; zn=z0+vz*t1-0.5*9.81*t1*t1
    disc=vz*vz+2*9.81*(z0-ti.Z_C)
    if disc<=0: return "no landing"
    t2=(vz+np.sqrt(disc))/9.81; xl=x0+vx*t2; yl=y0+vy*t2
    cand={"net":zn-(ti.NET_TOP+ti.R_BALL),"long":xl-ti.X_FAR,"short":-xl,"wideR":ti.Y_HI-yl,"wideL":yl-ti.Y_LO}
    k=min(cand,key=cand.get)
    return k if cand[k]<0 else "ok"
def load(p): return {json.loads(l)["seed"]:json.loads(l) for l in open(p)}
for tag in sys.argv[1:]:
    D=load(f"out/tt_r10/{tag}.jsonl"); seeds=[s for s in D if s<710120] if tag.startswith("v") else list(D)
    for side in (2,1):
        c=collections.Counter(); off=[]; 
        for s in seeds:
            r=D[s]
            if r["side"]!=side: continue
            if not r.get("hit"): c["nohit"]+=1; continue
            b=binding(r["ball_pos_out"],r["ball_out_exact"]) if r["solved"]<=0 else "solved"
            c[b]+=1
            n=np.array(r["pad_normal"]); n/=np.linalg.norm(n); o=np.array(r["ball_pos_out"])-np.array(r["pad_at_contact"]); inpl=o-(o@n)*n
            off.append(np.linalg.norm(inpl))
        n=sum(c.values())
        print("%-14s side %d n %d: "%(tag,side,n)+", ".join("%s %d"%(k,v) for k,v in c.most_common())+" | rim>=0.1: %.0f%% of hits"%(100*np.mean(np.array(off)>=0.1)))
