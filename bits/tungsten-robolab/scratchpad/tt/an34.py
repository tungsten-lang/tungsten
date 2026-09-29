import json, sys, numpy as np, collections
sys.path.insert(0,"playground")
import tt_impact as ti
def binding(p0,v):
    x0,y0,z0=p0; vx,vy,vz=v
    if vx>=-0.3: return "not toward net"
    t1=-x0/vx; zn=z0+vz*t1-0.5*9.81*t1*t1
    disc=vz*vz+2*9.81*(z0-ti.Z_C)
    if disc<=0: return "no landing"
    t2=(vz+np.sqrt(disc))/9.81; xl=x0+vx*t2; yl=y0+vy*t2
    cand={"net":zn-(ti.NET_TOP+ti.R_BALL),"long":xl-ti.X_FAR,"short":-xl,"wide R":ti.Y_HI-yl,"wide L":yl-ti.Y_LO}
    k=min(cand,key=cand.get)
    return k if cand[k]<0 else "ok"
def load(p):
    return {json.loads(l)["seed"]:json.loads(l) for l in open(p)}
A=load(sys.argv[1]); B=load(sys.argv[2])
seeds=sorted(set(A)&set(B))
for name,D in (("base",A),("new",B)):
    c=collections.Counter(); ex=[]; el=[]
    for s in seeds:
        r=D[s]
        if not r.get("hit"):
            c["no hit: "+r.get("landed","") if False else "no hit"]+=1; continue
        if r["solved"]>0: c["solved"]+=1
        else: c[binding(r["ball_pos_out"],r["ball_out_exact"])]+=1
        v=np.array(r["ball_out_exact"]); ex.append(np.linalg.norm(v)); el.append(np.degrees(np.arcsin(v[2]/np.linalg.norm(v))))
    print(name,"n",len(seeds),dict(c.most_common()),"| exit speed mean %.2f sd %.2f, elevation mean %.0f"%(np.mean(ex),np.std(ex),np.mean(el)))
# miss classes
for name,D in (("base",A),("new",B)):
    c=collections.Counter()
    sys.path.insert(0,"playground/tasks")
    from tasks.myo_tt import failure_class
    for s in seeds: c[failure_class(D[s])]+=1
    print(name,dict(c))
