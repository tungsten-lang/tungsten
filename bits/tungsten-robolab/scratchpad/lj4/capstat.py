"""Harness statistics of a take-off program on a set of captured penultimate-touchdown states (agent L4): n, gap, pen trunk pitch, early / late plant touchdown, score.
usage: capstat.py <prog> <prefix> <first_seed> <last_seed> [fmin]   (the captures <prefix>_s<seed>)"""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj3")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj4")
import numpy as np
import long_jump_limits as L
import long_jump_mine as M
import ljx, rgprog, ljx_tail

prog_path, prefix, a, b = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
fmin = float(sys.argv[5]) if len(sys.argv) > 5 else 1.5
names = [f"{prefix}_s{s}" for s in range(a, b + 1) if os.path.exists(os.path.join(L.OUT, f"{prefix}_s{s}_capture.npz"))]
ljx_tail._init(names, prog_path, fmin)
R = ljx_tail._R
rows = []
for i, nm in enumerate(names):
    cap = R["caps"][i]
    r, prog = ljx_tail.run_state(i, None)
    f = M.features(R["body"], cap)
    sc = ljx.score2(r, cap, ljx_tail.CFG) if r["valid"] else -5.0
    T = prog.t_touch if prog.t_touch is not None else -1.0
    rows.append((f["gap"], f["torso"], f["vx"], T, sc, 1.0 if r["valid"] else 0.0))
A = np.array(rows, float)
v = A[:, 5] > 0
early = v & (A[:, 3] > 0) & (A[:, 3] < 0.20)
late = v & (A[:, 3] > 0.26)
print("%s %d-%d: n %d | gap %.3f +- %.3f | pen torso %.3f +- %.3f | pen vx %.3f +- %.3f | early %d (%.1f%%) late %d (%.1f%%) | invalid %d | mean score %.3f legal %d (%.1f%%)" % (
    prefix, a, b, len(A), A[:, 0].mean(), A[:, 0].std(), A[:, 1].mean(), A[:, 1].std(), A[:, 2].mean(), A[:, 2].std(),
    early.sum(), 100.0 * early.mean(), late.sum(), 100.0 * late.mean(), int((~v).sum()), A[:, 4].mean(), int((A[:, 4] > 0).sum()), 100.0 * (A[:, 4] > 0).mean()))
