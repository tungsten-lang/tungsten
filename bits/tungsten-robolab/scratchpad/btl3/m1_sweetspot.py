"""Does the next stage's success depend on where / how fast the previous stage's ball arrives?  ok vs fail means of the arrival features."""
import sys, json, glob
import numpy as np
sys.path.insert(0, "scratchpad/btl3")
import m1_analyze as A
d = sys.argv[1]; stage = int(sys.argv[2])
rows = []
for fn in sorted(glob.glob(d + "/live_*.npz")):
    z = np.load(fn)
    ws = A.stage_windows(z)
    if len(ws) <= stage: continue
    side, k0 = ws[stage]
    rec = A.extract(z, side, k0)
    if rec is None: continue
    pl = json.loads(str(z["pass_log"]))
    ok = bool(pl[stage]["ok"]) if stage < len(pl) else False
    gate = bool(pl[stage]["gate"]) if stage < len(pl) else False
    bv = z["ballv"][k0 - 1]
    rows.append((ok, gate, rec["pc"][0], rec["pc"][1], rec["pc"][2], bv[0], bv[1], bv[2], rec["touch"]["t"] if "touch" in rec else np.nan))
R = np.array([[float(x) for x in r] for r in rows])
ok = R[:, 0] > 0.5
names = ["gate", "pc_x", "pc_y", "pc_t", "bv_x", "bv_y", "bv_z", "touch_t"]
print(f"stage {stage}: n {len(R)} ok {ok.sum()}")
print(f"{'':8s}" + "".join(f"{n:>9s}" for n in names))
print(f"{'ok':8s}" + "".join(f"{R[ok, i + 1].mean():9.3f}" for i in range(len(names))))
print(f"{'fail':8s}" + "".join(f"{R[~ok, i + 1].mean():9.3f}" for i in range(len(names))))
print(f"{'sd all':8s}" + "".join(f"{R[:, i + 1].std():9.3f}" for i in range(len(names))))
# binned success rate against each feature (terciles)
for i, n in enumerate(names[1:7], start=2):
    q = np.quantile(R[:, i], [1/3, 2/3])
    b = np.digitize(R[:, i], q)
    print(f"{n:6s} terciles {np.round(q,3)}: ok rate", [f"{ok[b==k].mean():.2f}(n{(b==k).sum()})" for k in range(3)])
# logistic-ish: linear regression of ok on standardized features
X = (R[:, 2:8] - R[:, 2:8].mean(0)) / R[:, 2:8].std(0)
A_ = np.column_stack([np.ones(len(X)), X])
b = np.linalg.solve(A_.T @ A_ + 1.0 * np.eye(A_.shape[1]), A_.T @ ok.astype(float))
print("linear probability coefficients (per sd) on pc_x pc_y pc_t bv_x bv_y bv_z:", np.round(b[1:], 3).tolist())
