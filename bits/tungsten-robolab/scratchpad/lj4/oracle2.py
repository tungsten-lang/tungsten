"""Oracle value of a two-program set in the harness (agent L4): per captured state the score of program A and B (clipped at 0 = the official-like metric), the mean of each, the mean of the per-state
maximum (a perfect selector), and how well a linear rule on the pen-state features can pick the better one.
usage: oracle2.py <progA> <progB> <names-file> [fmin]"""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj3")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj4")
import numpy as np
import long_jump_mine as M
import ljx, ljx_tail
pa, pb, nf = sys.argv[1], sys.argv[2], sys.argv[3]
fmin = float(sys.argv[4]) if len(sys.argv) > 4 else 1.5
names = open(nf).read().split(",")
S = {}
F = None
for tag, p in (("A", pa), ("B", pb)):
    ljx_tail._init(names, p, fmin)
    R = ljx_tail._R
    sc = []
    for i in range(len(names)):
        s, r, prog = ljx_tail.score_state(i, None)
        sc.append(max(s, 0.0))
    S[tag] = np.array(sc)
    if F is None:
        F = np.array([[M.features(R["body"], R["caps"][i])[k] for k in ("gap", "vx", "torso", "com_z", "swing_ahead")] for i in range(len(names))])
A, B = S["A"], S["B"]
print("n %d | mean A %.3f B %.3f | oracle max %.3f | A better in %.0f%%, B better in %.0f%%" % (len(A), A.mean(), B.mean(), np.maximum(A, B).mean(), 100 * (A > B).mean(), 100 * (B > A).mean()))
d = A - B
# a linear selector fit by least squares on the difference, cross-validated 2-fold
X = np.column_stack([np.ones(len(d)), (F - F.mean(0)) / F.std(0)])
idx = np.arange(len(d)); rng = np.random.default_rng(0); rng.shuffle(idx)
h = len(d) // 2
tot = []
for tr, te in ((idx[:h], idx[h:]), (idx[h:], idx[:h])):
    w, *_ = np.linalg.lstsq(X[tr], d[tr], rcond=None)
    pick_A = X[te] @ w > 0
    tot.append(np.where(pick_A, A[te], B[te]))
print("linear selector on (gap, vx, torso, z, swing_ahead), 2-fold CV: mean %.3f" % np.concatenate(tot).mean())
print("corr of A-B with features:", {k: round(float(np.corrcoef(d, F[:, j])[0, 1]), 2) for j, k in enumerate(("gap", "vx", "torso", "com_z", "swing_ahead"))})
