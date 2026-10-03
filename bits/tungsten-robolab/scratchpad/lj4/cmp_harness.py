"""Harness vs full rollout of a take-off program with regime tails (agent L4): for the captured states <prefix>_s<seed> of the given seeds, the harness's take-off (vx, vz, contact, regime)
and, from a long_jump_eval json of the same seeds, the rollout's take-off numbers.
usage: cmp_harness.py <prog.txt> <tails_npz[,npz]> <t1> <t2> <eval.json> <seed,seed,...> [fmin]"""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj3")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj4")
import numpy as np
import ljx, rgprog, ljx_tail
prog, tails, t1, t2, evj, seeds = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), sys.argv[5], [int(x) for x in sys.argv[6].split(",")]
fmin = float(sys.argv[7]) if len(sys.argv) > 7 else 1.5
names = [f"y2_s{s}" for s in seeds]
ljx_tail._init(names, prog, fmin)
R = ljx_tail._R
n = len(R["body"].muscles)
nd = len(rgprog.TAU_KNOTS)
de, dc = {}, {}
for pth in tails.split(","):
    z = np.load(pth)
    d1, c1 = ljx_tail.decode(z["x"], [int(z["regime"])], nd, n)
    de.update(d1); dc.update(c1)
rg = {"t1": t1, "t2": t2, "knots": rgprog.TAU_KNOTS, "de": de, "dc": dc}
j = json.load(open(evj))
byseed = {s: m for s, m in zip(j["seeds"], j["rows"])}
print("%-6s %-7s %7s | harness vx vz contact | rollout vx vz contact | regime" % ("seed", "side", "T"))
for i, s in enumerate(seeds):
    sc, r, p = ljx_tail.score_state(i, rg)
    m = byseed.get(s, {})
    print("%-6d %-7s %7.3f | %6.3f %6.3f %6.3f | %6.3f %6.3f %6.3f | %d (D_board %.2f, rollout ballistic %s)" % (
        s, R["caps"][i]["plant"], p.t_touch if p.t_touch is not None else -1, r.get("vx", 0), r.get("vz", 0), r.get("contact_s", 0),
        m.get("takeoff_vx") or 0, m.get("takeoff_vz") or 0, m.get("contact_time_s") or 0, p.regime, (r["D"] - (R["caps"][i]["board_x"] - r["toe_max"])) if r["valid"] else 0, m.get("ballistic_m")))
