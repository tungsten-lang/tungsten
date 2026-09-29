"""tcn_stats2: as tcn_stats.py, for a flying-start rollout (gear runs): the TCN's raw input features over a run's steady part, and the fixed random hidden layers.
usage: env... tcn_stats2.py TASK PARAMS CONTROLLER OUT SECONDS [SEED]"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
from practice import load_task, read_params
from bridge import Sim
import numpy as np
task_name, par, ctl, out, secs = sys.argv[1:6]
seed = int(sys.argv[6]) if len(sys.argv) > 6 else 0
task = load_task(task_name); task.seed = seed
if os.environ.get("RUN_NATURAL_START") == "flying":
    task.fly_touch = 2.0
xs = []
orig = task.on_command
def oc(m, d, cmd):
    if cmd.startswith("tcnx:"):
        if d.time > 3.0:
            xs.append([float(v) for v in cmd[5:].split(",")])
        return
    return orig(m, d, cmd)
task.on_command = oc
p = read_params(par); p.update({"tcn": 1.0, "tcn_xtrace": 1.0})
res = Sim(task, params=p, controller=ctl).run(float(secs))
X = np.array(xs); mu = X.mean(0); sd = X.std(0) + 1e-3
nin = X.shape[1]; h, k, nl = 8, 3, 3
rng = np.random.default_rng(7)
w = []
fan = nin
for l in range(nl):
    w += list(rng.normal(0, 1.0 / np.sqrt(fan * k), size=h * fan * k)) + [0.0] * h
    fan = h
with open(out, "w") as f:
    f.write(f"# TCN normalisation from {par} ({len(X)} ticks after 3 s) and fixed random hidden layers (seed 7)\n")
    f.write("tcn 1.0\n")
    for i in range(nin):
        f.write(f"tcn_mu{i} {float(mu[i])!r}\ntcn_sd{i} {float(sd[i])!r}\n")
    for i, v in enumerate(w):
        f.write(f"tcn_w{i} {float(v)!r}\n")
print(res["time"], res["fell"], res.get("peak_speed_1s"), "features", nin, "hidden weights", len(w))
