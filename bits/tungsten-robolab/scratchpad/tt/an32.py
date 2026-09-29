import json, numpy as np
rows=[json.loads(l) for l in open("out/tt_r10/champ_710000.jsonl")]
rows=[r for r in rows if "error" not in r and r.get("hit") and r.get("aim_height_err") is not None]
for s in (1,2):
    D=[r for r in rows if r["side"]==s]
    eh=np.array([r["aim_height_err"] for r in D]); ph=np.array([r["pose_height_err"] for r in D if r.get("pose_height_err") is not None])
    print("side",s,"n",len(D),"| servo height error at the last aim (m): mean %.3f sd %.3f, quantiles 10/50/90 %s | mean |err| 0.4-0.5 s: %.3f"%(eh.mean(),eh.std(),np.quantile(eh,[.1,.5,.9]).round(3),ph.mean()))
    # relation to solved
    sol=np.array([r["solved"]>0 for r in D])
    for lo,hi in [(-1,-0.08),(-0.08,-0.04),(-0.04,0.0),(0.0,0.04),(0.04,0.08),(0.08,1)]:
        m=(eh>=lo)&(eh<hi)
        if m.sum(): print("   eh %.2f..%.2f: n %d solved %.0f%%"%(lo,hi,m.sum(),100*sol[m].mean()))
