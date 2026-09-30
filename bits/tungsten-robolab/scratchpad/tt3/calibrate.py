"""Calibrate the ideal arm's per-joint gain G (agent T3): the champion's reached joint increments regressed on its asked increments (q_fit, the commanded posture reconstructed from the emitted muscle targets),
per side, pooled over the serves of set A (record-only run out/tt3/orc_rec) from t = 0 to the contact. G_j = sum(dq_meas dq_fit) / sum(dq_fit^2), clipped to [0, 1.5].
Also prints the reached-vs-asked table (means over serves at 0.27 s and at contact) for the baseline champion."""
import json, sys, glob, os
import numpy as np
np.set_printoptions(precision=3, suppress=True, linewidth=220)
JN = ["elv_angle", "shoulder_elv", "shoulder_rot", "elbow_flexion", "pro_sup", "deviation", "flexion"]
tag = sys.argv[1] if len(sys.argv) > 1 else "rec"
sets = sys.argv[2].split(",") if len(sys.argv) > 2 else ["A"]
out = sys.argv[3] if len(sys.argv) > 3 else "scratchpad/tt3/results/gains_A.json"
rows = []
for s in sets:
    rows += [json.loads(l) for l in open(f"out/tt3/{tag}_{s}.jsonl") if l.strip()]
num = {1: np.zeros(7), 2: np.zeros(7)}; den = {1: np.zeros(7) + 1e-12, 2: np.zeros(7) + 1e-12}
tab = {1: [], 2: []}
for r in rows:
    f = f"out/tt3/orc_{tag}/{r['seed']}.npz"
    if not os.path.exists(f): continue
    z = np.load(f)
    t, qf, q = z["t"][:, 0], z["qfit"], z["q"]
    side = r.get("side")
    if side not in (1, 2): continue
    tc = r.get("t_contact") or 0.5
    m = (t <= tc + 1e-9)
    dq, df = q[m] - q[0], qf[m] - qf[0]
    num[side] += (dq * df).sum(axis=0); den[side] += (df * df).sum(axis=0)
    ic = int(np.argmin(np.abs(t - tc))); i27 = int(np.argmin(np.abs(t - 0.27)))
    tab[side].append(np.r_[qf[i27], q[i27], qf[ic], q[ic], qf[0], q[0]])
G = {}
for side, nm in ((1, "fh"), (2, "bh")):
    g = np.clip(num[side] / den[side], 0.0, 1.5)
    G[f"o2_gain_{nm}"] = [round(float(x), 3) for x in g]
    T = np.array(tab[side])
    print(f"== {nm} (n {len(T)}): G = {g}")
    print("   asked(q_fit) at 0.27:", T[:, 0:7].mean(0), "\n   reached at 0.27:     ", T[:, 7:14].mean(0))
    print("   asked at contact:    ", T[:, 14:21].mean(0), "\n   reached at contact:  ", T[:, 21:28].mean(0), "\n   reached sd at contact", T[:, 21:28].std(0))
    print("   asked increment at contact:", (T[:, 14:21] - T[:, 28:35]).mean(0), " reached increment:", (T[:, 21:28] - T[:, 35:42]).mean(0))
json.dump(G, open(out, "w"))
print(json.dumps(G))
