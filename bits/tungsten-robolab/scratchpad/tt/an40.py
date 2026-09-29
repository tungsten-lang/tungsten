import json, sys, numpy as np
sys.path.insert(0,"playground"); sys.path.insert(0,"playground/tasks")
from tasks.myo_tt import failure_class
rows=[json.loads(l) for l in open("out/tt_r10/champ_710000.jsonl")]
rows=[r for r in rows if "error" not in r]
for side in (1,2):
    M=[r for r in rows if r["side"]==side and failure_class(r)=="miss: pad below the ball"]
    v=np.array([r["miss_vec"] for r in M]); d=np.array([r["miss_dist"] for r in M])
    print("side",side,"misses below the ball:",len(M),"| miss distance (m): median %.3f, quantiles 10/50/90 %s"%(np.median(d),np.quantile(d,[.1,.5,.9]).round(3)))
    print("   miss vector (ball - pad) mean",v.mean(0).round(3)," sd",v.std(0).round(3),"; z gap quantiles 10/50/90",np.quantile(v[:,2],[.1,.5,.9]).round(3),"; y gap sd %.3f"%v[:,1].std())
    print("   pad_offset (lateral, 0.4-0.5 s) mean %.2f"%np.mean([r.get("pad_offset",0) for r in M]))
