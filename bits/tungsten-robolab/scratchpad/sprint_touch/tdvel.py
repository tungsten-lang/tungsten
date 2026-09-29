import sys, os
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
from practice import load_task
from bridge import Sim
import numpy as np
task = load_task(sys.argv[1]); sim = Sim(task, params={})
m = sim.m
z = np.load(os.path.join(ROOT, "playground", "cache", f"sprint_touch_{sys.argv[2]}.npz"))
for j in ("r_hip_flex", "r_knee", "r_ankle", "l_hip_flex", "l_knee", "l_ankle"):
    a = m.joint(j).dofadr[0]; q = m.joint(j).qposadr[0]
    print(f"{j:12s} q {np.degrees(np.mean(z['qpos'][:, q])):6.1f} deg  w {np.mean(z['qvel'][:, a]):6.2f} +- {np.std(z['qvel'][:, a]):.2f} rad/s")
