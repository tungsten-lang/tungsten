"""Per-group measured contraction speed around the plant and swing of one pitch (where the bat_flow 'pre' dip is).

    .venv/bin/python scratchpad/bat/trace1.py PARAMS CONTROLLER SEED
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
task = BatRepTask()
task.seed = int(sys.argv[3])
sim = Sim(task, params=params, controller=os.path.abspath(sys.argv[2]))
m = sim.run(4.6)
r = m["pitches"][0]
log = sim.log
t = np.array([e[0] for e in log]); c = np.array([e[3] for e in log]); tg = np.array([e[4] for e in log]); labels = [e[1] for e in log]
names = [mu.name for mu in sim.muscles]
groups = {"legs": [i for i, n in enumerate(names) if n.startswith(B.LEG_MUSCLES)],
          "trunk": [i for i, n in enumerate(names) if n.startswith(B.TRUNK_MUSCLES)],
          "arms": [i for i, n in enumerate(names) if n.startswith(B.ARM_MUSCLES)]}
dt = 0.005
sp = {g: np.linalg.norm(np.diff(c[:, idx], axis=0), axis=1) / dt for g, idx in groups.items()}
sp["all"] = np.linalg.norm(np.diff(c, axis=0), axis=1) / dt
w = 5
sm = {g: np.convolve(v, np.ones(w) / w, mode="same") for g, v in sp.items()}
tc = r.get("t_contact", r.get("t_closest"))
print("pitch", r["speed_mph"], "mph x", r["target_x"], "z", r["target_z"], "hit", r["hit"], "bat", r.get("bat_speed"), "flow", r.get("flow"))
print("t_lift %.3f t_release %.3f t_plant %.3f t_swing %.3f t_contact %.3f" % (r["t_lift"], r["t_release"], r["t_plant"], r["t_swing"], tc))
print(r["flow_terms"])
k0 = int(np.searchsorted(t, r["t_lift"] - 0.05)); k1 = int(np.searchsorted(t, tc + 0.4))
print("  t-t_contact(ms)  legs  trunk  arms  all   [labels]")
for k in range(k0, k1, 2):
    print("  %6.0f  %6.1f %6.1f %6.1f %6.1f   %s" % (1000 * (t[k] - tc), sm["legs"][k], sm["trunk"][k], sm["arms"][k], sm["all"][k], labels[k]))
