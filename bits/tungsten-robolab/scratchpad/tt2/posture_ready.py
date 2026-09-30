"""Ready posture asked (champion params) vs reached at t = 0.28 s (row 27, just before the servo starts at 0.277 s), all serves, by side, per rung (agent T2)."""
import json, os, sys
import numpy as np
np.set_printoptions(precision=3, suppress=True, linewidth=200)
JOINTS = ["elv_angle", "shoulder_elv", "shoulder_rot", "elbow_flexion", "pro_sup", "deviation", "flexion"]
FH = ["elv", "sh_elv", "sh_rot", "elbow", "pro_sup", "dev", "wflex"]
BH = ["bh_elv", "bh_sh_elv", "bh_sh_rot", "bh_elbow", "bh_pro_sup", "bh_dev", "bh_wflex"]
params = {l.split()[0]: float(l.split()[1]) for l in open("params/myo_tt_p2_r10_c3.txt") if l.strip() and not l.startswith("#")}
row = int(sys.argv[1]) if len(sys.argv) > 1 else 27
for tag in sys.argv[2:] or ["0", "1", "2", "3"]:
    name = f"out/tt2/champ_r{tag}_98000.jsonl" if tag in "0123" else f"out/tt2/diag_{tag}_98000.jsonl"
    logs = f"out/tt2/logs_r{tag}" if tag in "0123" else f"out/tt2/logs_diag_{tag}"
    rows = [json.loads(l) for l in open(name)]
    print(f"== {tag}: reached at row {row} (t = {(row + 1) / 100:.2f} s), mean +- sd over all serves of the side; ratio = reached / asked (asked 0 -> n/a)")
    for s, nm, names in ((1, "forehand", FH), (2, "backhand", BH)):
        Q = []
        for r in rows:
            if r.get("side") != s: continue
            f = f"{logs}/{r['seed']}.npz"
            if not os.path.exists(f): continue
            X = np.load(f)["X"]
            if len(X) > row: Q.append(X[row, :7])
        Q = np.array(Q)
        print(f"  {nm} (n {len(Q)}):", "  ".join(f"{j[:6]} {params[p]:+.2f}->{Q[:, i].mean():+.2f}+-{Q[:, i].std():.2f}" for i, (j, p) in enumerate(zip(JOINTS, names))))
