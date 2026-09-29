"""Where the bat_flow command terms come from: the largest command-velocity steps and holds per group, with the chunk there.

    .venv/bin/python scratchpad/bat/trace2.py PARAMS CONTROLLER SEED [k=v,...]
"""
import os, sys
os.environ["BAT_BODY"] = "athlete"
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
from tasks.bat_rep import BatRepTask
from tasks import bat as B
from bridge import Sim


def read_params(path):
    out = {}
    for line in open(path):
        t = line.split()
        if len(t) >= 2 and not line.startswith("#"):
            out[t[0]] = float(t[1])
    return out


params = read_params(sys.argv[1])
for kv in (sys.argv[4] if len(sys.argv) > 4 else "").split(","):
    if kv:
        k, v = kv.split("="); params[k] = float(v)
task = BatRepTask(); task.seed = int(sys.argv[3])
sim = Sim(task, params=params, controller=os.path.abspath(sys.argv[2]))
m = sim.run(4.4)
r = m["pitches"][0]
log = sim.log
t = np.array([e[0] for e in log]); tg = np.array([e[4] for e in log]); labels = [e[1] for e in log]
names = [mu.name for mu in sim.muscles]
groups = {"legs": [i for i, n in enumerate(names) if n.startswith(B.LEG_MUSCLES)],
          "trunk": [i for i, n in enumerate(names) if n.startswith(B.TRUNK_MUSCLES)],
          "arms": [i for i, n in enumerate(names) if n.startswith(B.ARM_MUSCLES)]}
dt = 0.005
tc = r.get("t_contact", r.get("t_closest"))
ka = int(np.searchsorted(t, r["t_lift"]))
kf = int(np.searchsorted(t, tc + 0.45))
print("flow", r["flow"], r["flow_terms"])
for g, idx in groups.items():
    k1 = int(np.searchsorted(t, tc)) if g == "legs" else kf
    v = np.diff(tg[ka - 1:k1][:, idx], axis=0) / dt
    sp = np.linalg.norm(v, axis=1)
    dv = np.linalg.norm(np.diff(v, axis=0), axis=1)
    peak = sp.max()
    top = np.argsort(-dv)[:3]
    print(f"{g}: peak command speed {peak:.2f}/s; top steps (step/peak):")
    for j in top:
        k = ka + j + 1
        print("   t-contact %+5.0f ms  step %.2f  ratio %.3f  [%s]" % (1000 * (t[k] - tc), dv[j], dv[j] / peak, labels[k]))
