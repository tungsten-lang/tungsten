import json, numpy as np, collections, sys
sys.path.insert(0,"playground"); sys.path.insert(0,"playground/tasks")
from tasks.myo_tt import failure_class
P=json.load(open("out/tt_r10/pools_710000.json"))
Y={int(k):v for k,v in P["y"].items()}
rows=[json.loads(l) for l in open("out/tt_r10/champ_710000.jsonl")]
rows=[r for r in rows if "error" not in r and r["side"]==2]
print("backhand serves",len(rows))
edges=[-2,-1.2,-0.9,-0.7,-0.5,-0.3,-0.1,0.2]
for lo,hi in zip(edges[:-1],edges[1:]):
    D=[r for r in rows if lo<=Y[r["seed"]]<hi]
    if not D: continue
    H=[r for r in D if r.get("hit")]
    c=collections.Counter(failure_class(r) for r in D)
    padz=np.mean([r["pad_at_contact"][2] for r in H]) if H else float('nan')
    dz=np.mean([r["ball_pos_out"][2]-r["pad_at_contact"][2] for r in H]) if H else float('nan')
    print("y %.2f..%.2f n %3d solved %2.0f%% hit %2.0f%% | below %2.0f%% lateral %2.0f%% above %2.0f%% | pad z at contact %.3f ball-pad(exit) %.3f | pad_offset(lat 0.4-0.5s) %.2f"%(lo,hi,len(D),100*c["solved"]/len(D),100*len(H)/len(D),100*c["miss: pad below the ball"]/len(D),100*c["miss: lateral (out of reach)"]/len(D),100*c["miss: pad above the ball"]/len(D),padz,dz,np.mean([r.get("pad_offset",0) for r in D])))
