"""Which pen-touchdown features predict an EARLY plant touchdown (T < 0.20 s) for a program on captured states? (harness; L4 scratch)
usage: early_feat.py <prog> <names-file> [fmin]"""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj3")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj4")
import numpy as np
import mujoco
import long_jump_limits as L
import long_jump_mine as M
import ljx, ljx_robust, rgprog, ljx_tail

prog_path, names = sys.argv[1], open(sys.argv[2]).read().split(",")
fmin = float(sys.argv[3]) if len(sys.argv) > 3 else None
ljx_tail._init(names, prog_path, fmin)
R = ljx_tail._R
rows = []
for i, nm in enumerate(names):
    cap = R["caps"][i]
    r, prog = ljx_tail.run_state(i, None)
    f = M.features(R["body"], cap)
    body = R["body"]
    m, d = body.m, body.d
    mujoco.mj_setState(m, d, cap["state"], L.SPEC); mujoco.mj_forward(m, d)
    plant = cap["plant"]
    # plant-side (swing) foot height and velocity at the pen touchdown
    toe_z = float(d.site(f"{plant}_toe").xpos[2]); heel_z = float(d.site(f"{plant}_heel").xpos[2])
    knee = body.knee(plant)
    mujoco.mj_subtreeVel(m, d)
    vz = float(d.subtree_linvel[body.pelvis][2])
    sc = ljx.score2(r, cap, ljx_tail.CFG) if r["valid"] else -5
    rows.append((prog.t_touch if prog.t_touch is not None else -1, sc, f["gap"], f["vx"], f["com_z"], f["torso"], f["swing_ahead"], toe_z, heel_z, knee, vz))
A = np.array(rows, float)
ok = A[:, 0] > 0
A = A[ok]
cols = ["gap", "pen_vx", "pen_z", "pen_torso", "swing_ahead", "toe_z", "heel_z", "knee", "com_vz"]
early = A[:, 0] < 0.20
late = A[:, 0] > 0.26
print("%d valid; early %d, late %d" % (len(A), early.sum(), late.sum()))
for j, c in enumerate(cols):
    x = A[:, 2 + j]
    print("  %-12s all mean %7.3f sd %6.3f | early mean %7.3f | late mean %7.3f | corr with T %+.2f" % (c, x.mean(), x.std(), x[early].mean() if early.any() else 0, x[late].mean() if late.any() else 0, np.corrcoef(x, A[:, 0])[0, 1]))
# a tiny linear model of T on the features
X = np.column_stack([np.ones(len(A))] + [A[:, 2 + j] for j in range(len(cols))])
w, *_ = np.linalg.lstsq(X, A[:, 0], rcond=None)
pred = X @ w
print("linear R2 for T: %.2f" % (1 - ((A[:, 0] - pred) ** 2).sum() / ((A[:, 0] - A[:, 0].mean()) ** 2).sum()))
