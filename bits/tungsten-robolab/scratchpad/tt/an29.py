import json, sys, numpy as np
np.set_printoptions(precision=3,suppress=True,linewidth=160)
rows=[json.loads(l) for l in open("out/tt_r10/champ_710000.jsonl")]
rows=[r for r in rows if "error" not in r]
H=[r for r in rows if r.get("hit") and r.get("ball_pos_out") and r.get("pad_at_contact")]
for side in (1,2):
    D=[r for r in H if r["side"]==side]
    off=np.array([np.array(r["ball_pos_out"])-np.array(r["pad_at_contact"]) for r in D])
    sol=np.array([r["solved"]>0 for r in D])
    # offset in the pad plane: remove the component along the pad normal
    n=np.array([r["pad_normal"] for r in D]); n=n/np.linalg.norm(n,axis=1,keepdims=True)
    inpl=off-(off*n).sum(1,keepdims=True)*n
    d=np.linalg.norm(inpl,axis=1)
    print("side",side,"n",len(D),"| ball-pad offset (world) mean",off.mean(0),"sd",off.std(0))
    print("   in-plane distance: median %.3f, quantiles 25/75/90: %s"%(np.median(d),np.quantile(d,[.25,.75,.9])))
    for lo,hi in [(0,0.03),(0.03,0.06),(0.06,0.085),(0.085,0.1),(0.1,1)]:
        m=(d>=lo)&(d<hi)
        if m.sum(): print("   offset %.3f-%.3f: n %d solved %.0f%%"%(lo,hi,m.sum(),100*sol[m].mean()))
    # vertical offset (world z) distribution
    print("   z offset (ball - pad centre) quantiles 10/25/50/75/90:",np.quantile(off[:,2],[.1,.25,.5,.75,.9]))
