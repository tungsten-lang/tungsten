import json, sys, numpy as np
sys.path.insert(0,"playground")
import tt_impact as ti
rows=[json.loads(l) for l in open(sys.argv[1])]
rows=[r for r in rows if "error" not in r]
hits=[r for r in rows if r.get("hit") and r.get("ball_out_exact") and r.get("paddle_vel")]
vin=np.array([r["ball_in_exact"] for r in hits]); vp=np.array([r["paddle_vel"] for r in hits]); n=np.array([r["pad_normal"] for r in hits]); vout=np.array([r["ball_out_exact"] for r in hits])
pos=np.array([r["ball_pos_out"] for r in hits]); sol=np.array([r["solved"]>0 for r in hits]); side=np.array([r["side"] for r in hits])
E,ALPHA,MU,KZ=0.95,0.9,0.012,-0.0
pred=ti.impact(vin,ALPHA*vp,n,E,MU,KZ)
res=np.linalg.norm(vout-pred,axis=1)
print("n hits",len(hits),"|resid| quantiles 25/50/75/90:",np.quantile(res,[.25,.5,.75,.9]).round(2))
inl=res<0.7
print("inliers (<0.7 m/s):",inl.sum(),"of",len(hits),"; solved among inliers %.0f%%, outliers %.0f%%"%(100*sol[inl].mean(),100*sol[~inl].mean()))
# check flight-of-prediction agreement on inliers
lab=[ti.flight(pos[i],pred[i])[0] for i in range(len(hits))]
agree=np.mean([(lab[i]=="opp")==sol[i] for i in range(len(hits))])
print("predicted-solved vs actual agreement, all hits %.2f, inliers %.2f"%(agree,np.mean([(lab[i]=="opp")==sol[i] for i in range(len(hits)) if inl[i]])))
print("predicted solved fraction (model, actual pad state): %.2f  actual %.2f"%(np.mean([l=="opp" for l in lab]),sol.mean()))
# counterfactual: extra retreat delta along the (toward-ball) normal
sg=np.sign(np.sum(vin*n,axis=1)); nn=n*(-sg)[:,None]
print("delta retreat (m/s) -> predicted solved fraction of hits (all / fh / bh)")
for d in [-0.5,-0.25,0,0.25,0.5,0.75,1.0,1.25,1.5,2.0]:
    vp2=vp-d*nn         # retreating = along the ball's travel = -nn
    p2=ti.impact(vin,ALPHA*vp2,n,E,MU,KZ)
    ok=np.array([ti.flight(pos[i],p2[i])[0]=="opp" for i in range(len(hits))])
    print("  delta %.2f: all %.2f  fh %.2f  bh %.2f"%(d,ok.mean(),ok[side==1].mean(),ok[side==2].mean()))
# best per-serve delta as function of incoming speed: which delta values solve
best=[]
grid=np.arange(-0.5,2.51,0.25)
ok=np.zeros((len(hits),len(grid)),bool)
for k,d in enumerate(grid):
    vp2=vp-d*nn
    p2=ti.impact(vin,ALPHA*vp2,n,E,MU,KZ)
    ok[:,k]=[ti.flight(pos[i],p2[i])[0]=="opp" for i in range(len(hits))]
sp_in=np.linalg.norm(vin,axis=1)
print("fraction of hits solvable by SOME delta:",ok.any(1).mean().round(3))
for lo,hi in [(0,5.2),(5.2,5.6),(5.6,6.0),(6.0,6.5),(6.5,9)]:
    m=(sp_in>=lo)&(sp_in<hi)
    if m.sum()==0: continue
    frac=ok[m].mean(0)
    kbest=int(np.argmax(frac))
    print("ball speed %.1f-%.1f n=%d: solved by delta: "%(lo,hi,m.sum())+" ".join("%.2f:%.0f%%"%(grid[k],100*frac[k]) for k in range(0,len(grid),2))+"   best %.2f (%.0f%%) ; some-delta %.0f%%"%(grid[kbest],100*frac[kbest],100*ok[m].any(1).mean()))
