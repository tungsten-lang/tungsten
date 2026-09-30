"""Side-mean terminal pelvis velocity (joint coordinates qd of pelvis_x, pelvis_y at the contact row) of the champion, from set A's pass-1 logs -> scratchpad/tt3/results/pelvis_vend_A.json (agent T3).
Used by the drift-preserving pelvis oracle o1c: settle at the champion's MEAN terminal velocity instead of at rest (keeps the retreat its aim law is calibrated around, removes its scatter)."""
import json, os
import numpy as np
rows = [json.loads(l) for l in open("out/tt3/o0_A.jsonl")]
acc = {1: [], 2: []}
for r in rows:
    z = np.load(f"out/tt3/logs_o0/{r['seed']}.npz")
    k = int(z["contact"])
    if k < 3 or r.get("side") not in (1, 2): continue
    acc[r["side"]].append(z["X"][k, 22:24])
out = {str(s): np.mean(v, axis=0).round(4).tolist() for s, v in acc.items()}
print("side-mean terminal pelvis qd (x, y):", out, {s: len(v) for s, v in acc.items()}, "sd", {s: np.std(v, axis=0).round(3).tolist() for s, v in acc.items()})
json.dump(out, open("scratchpad/tt3/results/pelvis_vend_A.json", "w"))
