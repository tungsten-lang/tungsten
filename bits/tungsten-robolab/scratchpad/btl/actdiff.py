"""First ticks where two param sets' activations differ, and on which muscles."""
import sys, importlib, numpy as np
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks"); sys.path.insert(0, "scratchpad/btl")
from bridge import Sim
from grid import load
task_name, pfile, ctl, over, seed, secs = sys.argv[1:7]
logs = []
for ov in ("", over):
    t = importlib.import_module(f"tasks.{task_name}").TASK(); t.seed = int(seed)
    p = load(pfile); p.update({k: float(v) for k, v in (kv.split("=") for kv in ov.split(",") if kv)})
    sim = Sim(t, params=p, controller=ctl)
    sim.run(float(secs))
    logs.append((np.array([row[2] for row in sim.log]), [row[0] for row in sim.log], sim))
a, b = logs[0][0], logs[1][0]
names = [logs[0][2].m.actuator(i).name for i in range(logs[0][2].m.nu)]
n = min(len(a), len(b))
for k in range(n):
    d = np.abs(a[k] - b[k])
    if d.max() > 0:
        idx = np.argsort(-d)[:6]
        print("tick", k, "t", logs[0][1][k], [(names[i], round(float(a[k][i]), 4), round(float(b[k][i]), 4)) for i in idx if d[i] > 0])
        if k > 3 and d.max() > 1e-3: break
