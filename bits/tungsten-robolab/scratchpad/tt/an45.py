import json, sys, numpy as np
sys.path.insert(0,"playground")
import tt_impact as ti
rows=[json.loads(l) for l in open("out/tt_r10/champ_710000.jsonl")]
rows=[r for r in rows if "error" not in r and r.get("hit") and r.get("ball_out_exact") and r.get("ball_pos_out")]
ELEV=np.arange(-10,85,1.0)
def window(speed,pos,az_deg):
    a=np.radians(az_deg); res=[]
    for th in ELEV:
        t=np.radians(th)
        v=np.array([-speed*np.cos(t)*np.cos(a), speed*np.cos(t)*np.sin(a), speed*np.sin(t)])
        res.append(bool(ti.landing_ok(pos,v)))
    res=np.array(res)
    if not res.any(): return None
    # intervals
    idx=np.nonzero(res)[0]; ivs=[]; s=idx[0]; p=idx[0]
    for i in idx[1:]:
        if i!=p+1: ivs.append((ELEV[s],ELEV[p])); s=i
        p=i
    ivs.append((ELEV[s],ELEV[p])); return ivs
out=[]
for r in rows:
    v=np.array(r["ball_out_exact"]); sp=np.linalg.norm(v); el=np.degrees(np.arcsin(v[2]/sp)); az=np.degrees(np.arctan2(v[1],-v[0]))
    iv=window(sp,np.array(r["ball_pos_out"]),az)
    if iv is None: out.append((r["side"],sp,el,az,np.nan,np.nan,r["solved"]>0,0)); continue
    # the interval nearest to the actual elevation
    best=min(iv,key=lambda w: 0 if w[0]<=el<=w[1] else min(abs(el-w[0]),abs(el-w[1])))
    c=0.5*(best[0]+best[1]); width=best[1]-best[0]
    out.append((r["side"],sp,el,az,c,width,r["solved"]>0,len(iv)))
O=np.array(out,float)
for side in (1,2):
    m=(O[:,0]==side)&~np.isnan(O[:,4])
    d=O[m,2]-O[m,4]
    print("side",side,"n",m.sum(),"| exit elevation minus the window centre (deg): mean %.1f sd %.1f | window width median %.0f | inside window %.0f%% ; solved %.0f%%"%(d.mean(),d.std(),np.median(O[m,5]),100*np.mean(np.abs(d)<=O[m,5]/2),100*O[m,6].mean()))
    for lo,hi in [(-90,-30),(-30,-15),(-15,-5),(-5,5),(5,15),(15,30),(30,90)]:
        mm=m&((O[:,2]-O[:,4])>=lo)&((O[:,2]-O[:,4])<hi)
        if mm.sum(): print("     offset %d..%d: n %d solved %.0f%%"%(lo,hi,mm.sum(),100*O[mm,6].mean()))
# how many hits have no feasible window at all (speed too high/low)
print("hits with NO feasible elevation at their exit speed/azimuth: %.0f%%"%(100*np.mean(np.isnan(O[:,4]))))

print("--- the hits with no feasible elevation: why")
nw=[(r,o) for r,o in zip(rows,O) if np.isnan(o[4])]
sp=np.array([o[1] for r,o in nw]); az=np.array([o[3] for r,o in nw]); el=np.array([o[2] for r,o in nw]); z=np.array([r["ball_pos_out"][2] for r,o in nw]); sd=np.array([o[0] for r,o in nw])
print("n",len(nw),"| exit speed quantiles 10/50/90:",np.quantile(sp,[.1,.5,.9]).round(1),"| azimuth:",np.quantile(az,[.1,.5,.9]).round(0),"| elevation:",np.quantile(el,[.1,.5,.9]).round(0),"| contact z:",np.quantile(z,[.1,.5,.9]).round(2))
print("by speed: <4: %d, 4-5: %d, 5-6: %d, 6-7: %d, 7-8: %d, >8: %d"%tuple(int(((sp>=a)&(sp<b)).sum()) for a,b in [(0,4),(4,5),(5,6),(6,7),(7,8),(8,99)]))
print("|azimuth| > 25 deg: %d of %d"%(int((np.abs(az)>25).sum()),len(nw)))
print("by side:",{s:int((sd==s).sum()) for s in (1,2)})
