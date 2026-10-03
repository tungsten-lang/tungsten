"""Harness score of a take-off program by plant side (and by touchdown regime) over captured states (L4 scratch). usage: sidestat.py <prog> <names-file> [fmin]"""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj3")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj4")
import numpy as np
import ljx, ljx_tail
prog_path, names = sys.argv[1], open(sys.argv[2]).read().split(",")
fmin = float(sys.argv[3]) if len(sys.argv) > 3 else 1.5
ljx_tail._init(names, prog_path, fmin)
R = ljx_tail._R
rows = []
for i, nm in enumerate(names):
    cap = R["caps"][i]
    r, prog = ljx_tail.run_state(i, None)
    sc = ljx.score2(r, cap, ljx_tail.CFG) if r["valid"] else -5.0
    rows.append((cap["plant"], sc, prog.t_touch if prog.t_touch is not None else -1, r.get("vz", 0) if r["valid"] else 0, r.get("vx", 0) if r["valid"] else 0))
for side in ("l", "r"):
    S = np.array([x[1] for x in rows if x[0] == side])
    T = np.array([x[2] for x in rows if x[0] == side])
    V = np.array([x[3] for x in rows if x[0] == side and x[2] > 0.2 and x[2] < 0.26])
    print("plant %s: n %d mean %.3f legal %.1f%% | early %.1f%% late %.1f%% | normal-regime vz %.2f" % (side, len(S), S.mean(), 100 * (S > 0).mean(), 100 * ((T > 0) & (T < 0.2)).mean(), 100 * (T > 0.26).mean(), V.mean() if len(V) else 0))
