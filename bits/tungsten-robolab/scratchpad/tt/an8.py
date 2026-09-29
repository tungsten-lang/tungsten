import json, sys, numpy as np
sys.path.insert(0,"playground")
import tt_impact as ti
rows=[json.loads(l) for l in open(sys.argv[1])]
rows=[r for r in rows if "error" not in r]
hits=[r for r in rows if r.get("hit") and r.get("aim_normal") and r.get("paddle_vel") and r.get("pad_normal")]
print(len(hits),"hits with aim")
na=np.array([r["aim_normal"] for r in hits]); nt=np.array([r["pad_normal"] for r in hits]); side=np.array([r["side"] for r in hits])
pa,ya=ti.angles_from_normal(na); pt,yt=ti.angles_from_normal(nt)
dp=np.degrees(pt-pa); dy=np.degrees(yt-ya)
for s,nm in [(1,"forehand"),(2,"backhand")]:
    m=side==s
    print(nm,"n",m.sum(),"pitch err (actual-aim) mean %.1f std %.1f  median abs %.1f | yaw err mean %.1f std %.1f median abs %.1f"%(dp[m].mean(),dp[m].std(),np.median(np.abs(dp[m])),dy[m].mean(),dy[m].std(),np.median(np.abs(dy[m]))))
print("pitch err quantiles 10/25/50/75/90:",np.quantile(dp,[.1,.25,.5,.75,.9]).round(1))
print("yaw err quantiles 10/25/50/75/90:",np.quantile(dy,[.1,.25,.5,.75,.9]).round(1))
# angle between aim and actual normals
cosang=np.abs(np.sum(na*nt,axis=1)); ang=np.degrees(np.arccos(np.clip(cosang,0,1)))
print("angle between aim and actual normal: median %.1f, 75%% %.1f, 90%% %.1f"%tuple(np.quantile(ang,[.5,.75,.9])))
