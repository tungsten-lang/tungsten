import json, sys, numpy as np, time
sys.path.insert(0,"playground")
import tt_impact as ti
rows=[json.loads(l) for l in open(sys.argv[1])]
rows=[r for r in rows if "error" not in r]
hits=[r for r in rows if r.get("hit") and r.get("paddle_vel") and r.get("pad_normal") and r.get("ball_in_exact")]
def orient(n):
    n=np.asarray(n,float); return n*np.sign(n[...,0:1]+1e-12)
E,ALPHA,MU=0.95,0.9,0.012
rng=np.random.default_rng(1)
NS=64
Z=rng.standard_normal((NS,5))   # common random numbers: pitch, yaw, vx,vy,vz
PHA=np.arange(-30,51,3.0); YWA=np.arange(-20,21,4.0); DEL=np.arange(-0.25,1.51,0.25)
def design_P(vin,pos,sig_p,sig_y,sig_v,bias_p=0.0):
    """P(success) over the grid of designs (delta, aim pitch, aim yaw): array (D,P,Y)."""
    out=np.zeros((len(DEL),len(PHA),len(YWA)))
    ret=np.array([1.0,0.0,0.0])
    for a,d in enumerate(DEL):
        vp_plan=d*ret
        vp=vp_plan[None,:]+sig_v*Z[:,2:5]             # (NS,3)
        # normals: (P,Y,NS,3)
        P=np.radians(PHA[:,None,None]+bias_p+sig_p*Z[None,None,:,0])
        Y=np.radians(YWA[None,:,None]+sig_y*Z[None,None,:,1])
        n=np.stack([np.cos(P)*np.cos(Y),np.cos(P)*np.sin(Y),np.sin(P)+0*Y],axis=-1)
        n=n/np.linalg.norm(n,axis=-1,keepdims=True)
        v=ti.impact(vin,ALPHA*vp[None,None,:,:],n,E,MU)
        ok=ti.landing_ok(pos,v)
        out[a]=ok.mean(axis=-1)
    return out
res={}
t0=time.time()
configs={"champion-like noise (pitch 10, yaw 2.5, vel 0.5)":(10,2.5,0.5),"half noise (5,1.5,0.25)":(5,1.5,0.25),"low noise (2.5,1,0.12)":(2.5,1.0,0.12),"pitch 5 only":(5,2.5,0.5)}
sub=hits[::3]   # every third hit for speed
print("using",len(sub),"hits of",len(hits))
for name,(sp,sy,sv) in configs.items():
    Pbest=[];Pfix=[];Pd0=[];Pbyspd={}
    for r in sub:
        vin=np.array(r["ball_in_exact"]); pos=np.array(r["ball_pos_out"])
        P=design_P(vin,pos,sp,sy,sv)
        Pbest.append(P.max())
        Pd0.append(P[1].max())          # delta=0 (index of 0.0 is 1), best aim
        spd=np.linalg.norm(vin)
        Pbyspd.setdefault(int(np.clip((spd-5.0)//0.5,0,4)),[]).append((P.max(),P[1].max()))
    print("%-52s mean over hits of best-design P: %.2f ; with delta=0 (pad still) best aim: %.2f"%(name,np.mean(Pbest),np.mean(Pd0)),"(%.0fs)"%(time.time()-t0))
    print("     by ball speed bins (5.0-5.5,...): best-design P / delta0:", " | ".join("%.2f/%.2f (n%d)"%(np.mean([a for a,b in v]),np.mean([b for a,b in v]),len(v)) for k,v in sorted(Pbyspd.items())))
