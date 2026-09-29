import json, sys, numpy as np
sys.path.insert(0,"playground")
import tt_impact as ti
rows=[json.loads(l) for l in open(sys.argv[1])]
rows=[r for r in rows if "error" not in r]
hits=[r for r in rows if r.get("hit") and r.get("paddle_vel") and r.get("pad_normal") and r.get("ball_in_exact")]
def orient(n):
    n=np.asarray(n,float); return n*np.sign(n[...,0:1]+1e-12)
E,ALPHA,MU=0.95,0.9,0.012
PH=np.arange(-60,61,1.0); YW=np.arange(-45,46,1.5)
NG=ti.normals_grid(PH,YW)
DELTAS=np.arange(-0.5,2.01,0.25)
res=[]
for r in hits:
    vin=np.array(r["ball_in_exact"]); vp=np.array(r["paddle_vel"]); pos=np.array(r["ball_pos_out"]); n0=orient(r["pad_normal"])
    nn=-orient(n0)   # points -x: toward the ball's source... retreat direction is +x = along the ball's travel = +orient(n0)?? 
    ret_dir=orient(n0)  # +x-ish: the direction of the ball's travel (retreat = moving along it)
    row=[]
    for d in DELTAS:
        vp2=vp+d*ret_dir - np.dot(vp,ret_dir)*ret_dir*0  # add retreat velocity to the measured pad velocity
        v=ti.impact(vin,ALPHA*vp2,NG.reshape(-1,3),E,MU).reshape(NG.shape)
        M=ti.landing_ok(pos,v)
        # best yaw column: max interval width, and total area
        widths=M.sum(0)
        row.append((widths.max(), M.sum()))
    res.append((np.linalg.norm(vin),row))
sp=np.array([x[0] for x in res]); Wd=np.array([[c[0] for c in x[1]] for x in res]); Ar=np.array([[c[1] for c in x[1]] for x in res])
print("delta retreat added along the ball's travel (m/s)  ->  median over serves of the widest feasible pitch interval (deg) / feasible area (deg^2)")
print("delta:"," ".join("%5.2f"%d for d in DELTAS))
for lo,hi in [(0,5.2),(5.2,5.6),(5.6,6.0),(6.0,6.5),(6.5,9)]:
    m=(sp>=lo)&(sp<hi)
    print("v %.1f-%.1f n=%d width:"%(lo,hi,m.sum())," ".join("%5.0f"%np.median(Wd[m][:,k]) for k in range(len(DELTAS))))
    print("             area :"," ".join("%5.0f"%np.median(Ar[m][:,k]) for k in range(len(DELTAS))))
m=np.ones(len(sp),bool)
print("all width:"," ".join("%5.0f"%np.median(Wd[:,k]) for k in range(len(DELTAS))))
print("all area :"," ".join("%5.0f"%np.median(Ar[:,k]) for k in range(len(DELTAS))))
