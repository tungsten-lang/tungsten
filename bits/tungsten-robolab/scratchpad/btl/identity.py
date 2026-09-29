"""Bit-identity of two controller binaries: the same task, seed and params,
every tick's activations compared exactly."""
import sys, importlib, numpy as np
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from bridge import Sim
def load(p):
    out = {}
    for line in open(p):
        t = line.split()
        if len(t) >= 2 and not line.startswith("#"): out[t[0]] = float(t[1])
    return out
task_name, pfile, ctl_a, ctl_b, seed, secs = sys.argv[1:7]
params = load(pfile)
logs = []
for ctl in (ctl_a, ctl_b):
    t = importlib.import_module(f"tasks.{task_name}").TASK(); t.seed = int(seed)
    sim = Sim(t, params=params, controller=ctl)
    r = sim.run(float(secs))
    logs.append((np.array([row[2] for row in sim.log]), r))
a, b = logs[0][0], logs[1][0]
same = a.shape == b.shape and np.array_equal(a, b)
print(f"{task_name} seed {seed}: ticks {a.shape[0]} vs {b.shape[0]}, activations bit-identical: {same}",
      "" if same else f"max diff {np.max(np.abs(a[:min(len(a),len(b))] - b[:min(len(a),len(b))])):.3g}")
