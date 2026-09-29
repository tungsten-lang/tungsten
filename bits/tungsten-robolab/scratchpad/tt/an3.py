import json, sys, numpy as np
sys.path.insert(0,"playground")
import tt_impact as ti
rows=[json.loads(l) for l in open(sys.argv[1])]
rows=[r for r in rows if "error" not in r]
hits=[r for r in rows if r.get("hit") and r.get("ball_out_exact")]
print(len(rows),"episodes",len(hits),"hits")
print("seed side solved | exit speed elev(deg) azim(deg) | landed | pos_out z | vin speed")
out=[]
for r in hits:
    v=np.array(r["ball_out_exact"]); p=np.array(r["ball_pos_out"])
    sp=np.linalg.norm(v); el=np.degrees(np.arcsin(v[2]/sp)); az=np.degrees(np.arctan2(v[1],-v[0]))
    out.append((r["side"],r["solved"],sp,el,az,r.get("landed"),p[2],np.linalg.norm(r["ball_in_exact"]),p[0],p[1]))
out=np.array([(o[0],o[1],o[2],o[3],o[4],o[6],o[7],o[8],o[9]) for o in out])
np.set_printoptions(precision=2,suppress=True,linewidth=150)
S=out[:,1]>0
print("solved exit speed mean/std",out[S,2].mean().round(2),out[S,2].std().round(2),"elev",out[S,3].mean().round(1),out[S,3].std().round(1),"azim",out[S,4].mean().round(1),out[S,4].std().round(1))
print("unsolved exit speed mean/std",out[~S,2].mean().round(2),out[~S,2].std().round(2),"elev",out[~S,3].mean().round(1),out[~S,3].std().round(1),"azim",out[~S,4].mean().round(1),out[~S,4].std().round(1))
print("exit x,z of the ball (pad plane): x mean",out[:,7].mean().round(2),"std",out[:,7].std().round(2),"z mean",out[:,5].mean().round(2),"std",out[:,5].std().round(2))
# bins of exit speed
for lo,hi in [(0,4),(4,4.75),(4.75,5.25),(5.25,5.75),(5.75,6.25),(6.25,7),(7,20)]:
    m=(out[:,2]>=lo)&(out[:,2]<hi)
    if m.any(): print("exit speed %.2f-%.2f: n %d solved %d"%(lo,hi,m.sum(),(out[m,1]>0).sum()))
for lo,hi in [(-90,-10),(-10,0),(0,10),(10,20),(20,30),(30,40),(40,60),(60,90)]:
    m=(out[:,3]>=lo)&(out[:,3]<hi)
    if m.any(): print("exit elev %d..%d: n %d solved %d"%(lo,hi,m.sum(),(out[m,1]>0).sum()))
for lo,hi in [(-90,-30),(-30,-15),(-15,-5),(-5,5),(5,15),(15,30),(30,90)]:
    m=(out[:,4]>=lo)&(out[:,4]<hi)
    if m.any(): print("exit azim %d..%d: n %d solved %d"%(lo,hi,m.sum(),(out[m,1]>0).sum()))
# landing prediction: which region of (speed, elev) is feasible for the exit position
print("solved elevations vs speed:")
for o in out[S][:40]: print("  side %d speed %.2f elev %.1f azim %.1f z %.2f"%(o[0],o[2],o[3],o[4],o[5]))
