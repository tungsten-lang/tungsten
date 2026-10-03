"""Filter captured states for the landing search (agent L4): keep the states whose take-off program (harness) is valid, legal (foot behind the line - margin) and not a collapse
(D_board >= dmin), so the landing table's worst-start term is not spent on take-offs that cannot be saved.
usage: filter_caps.py <prog.txt> <names-file> <out-file> [dmin=4.0] [fmin=1.5] [tails.npz,..  t1 t2]"""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj3")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj4")
import numpy as np
import ljx, rgprog, ljx_tail
prog, names_file, out = sys.argv[1], sys.argv[2], sys.argv[3]
dmin = float(sys.argv[4]) if len(sys.argv) > 4 else 4.0
fmin = float(sys.argv[5]) if len(sys.argv) > 5 else 1.5
names = open(names_file).read().split(",")
ljx_tail._init(names, prog, fmin)
R = ljx_tail._R
rg = None
if len(sys.argv) > 8:
    n = len(R["body"].muscles); nd = len(rgprog.TAU_KNOTS)
    de, dc = {}, {}
    for pth in sys.argv[6].split(","):
        z = np.load(pth)
        d1, c1 = ljx_tail.decode(z["x"], [int(z["regime"])], nd, n)
        de.update(d1); dc.update(c1)
    rg = {"t1": float(sys.argv[7]), "t2": float(sys.argv[8]), "knots": rgprog.TAU_KNOTS, "de": de, "dc": dc}
keep = []
for i, nm in enumerate(names):
    sc, r, p = ljx_tail.score_state(i, rg)
    if r["valid"] and sc > 0 and (r["D"] - (R["caps"][i]["board_x"] - r["toe_max"])) >= dmin:
        keep.append(nm)
open(out, "w").write(",".join(keep))
print("kept %d of %d states (valid, legal, D_board >= %.1f)" % (len(keep), len(names), dmin))
