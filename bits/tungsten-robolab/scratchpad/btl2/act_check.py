"""Do the arm muscles in the closed loop get exactly the program's table? (launch stage)

    OMP_NUM_THREADS=1 .venv/bin/python scratchpad/btl2/act_check.py seed npz
"""
import sys

import numpy as np

sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
sys.path.insert(0, "scratchpad/btl2")
import oracle_gs as G  # noqa: E402
import oracle_search as S  # noqa: E402
from common import load  # noqa: E402
from bridge import Sim  # noqa: E402
from dribble_btl import DribbleBtlTask  # noqa: E402

seed = int(sys.argv[1])
z = np.load(sys.argv[2])
params = load("scratchpad/btl2/params/pgP0.txt")
t = DribbleBtlTask(); t.body_kind = "v3"; t.seed = seed
sim = Sim(t, params=params, controller="bin/challengers/btl2-b11")
r = sim.run(2.5)
names = [mu.name for mu in sim.muscles]
idx = list(z["idx"])
times = np.array([row[0] for row in sim.log])
acts = np.array([row[2] for row in sim.log])
ks = int(round(1.535 / 0.005))
i0 = int(np.argmin(np.abs(times - (1.535 + 0.005))))   # the log stores the time after the tick
print("log time at tick ks (after step):", times[ks], "index", ks)
# u from the skill's dbg would be better: use the nominal to get u from the replay's value passed in argv[3:5]
u = np.array([float(sys.argv[3]), float(sys.argv[4])])
cfg = {"idx": idx, "kt": z["kt"], "nprog": 80, "gmax": 1.0}
base = acts[ks:ks + 161]
ov = G.program_gs(z["x"], cfg, base, 160, u)
dev = []
for i in range(0, 60):
    exp = np.array([ov[mi][i] for mi in idx])
    got = acts[ks + i][idx]
    dev.append(np.abs(exp - got))
dev = np.array(dev)
print("max |expected - applied| per tick (first 60 ticks):", np.round(dev.max(axis=1), 3).tolist())
worst = np.unravel_index(np.argmax(dev), dev.shape)
print("worst tick", worst[0], "muscle", names[idx[worst[1]]], "expected", ov[idx[worst[1]]][worst[0]], "applied", acts[ks + worst[0]][idx[worst[1]]])
