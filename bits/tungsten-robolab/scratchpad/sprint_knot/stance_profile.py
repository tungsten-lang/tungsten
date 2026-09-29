"""Average right-leg stance of a robolab rollout's steady tail, resampled every 10 ms from touchdown:
thigh (world), hip, knee, ankle, their velocities, and the MuJoCo activation of the 11 stance muscles.
usage: stance_profile.py TASK PARAMS CONTROLLER [--seconds 16] [--t0 8] [--seed N] [--npz out.npz]"""
import argparse, math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
from practice import load_task, read_params
from bridge import Sim
import numpy as np
MUS = ["r_hip_flex_pos", "r_hip_flex_neg", "r_knee_pos", "r_knee_neg", "r_ankle_pos", "r_ankle_neg", "r_toe_pos", "r_toe_neg", "r_rf", "r_ham", "r_gas"]
J = ["r_hip_flex", "r_knee", "r_ankle"]
class R:
    def __init__(s): s.rows = []
    def maybe_capture(s, sim):
        m, d = sim.m, sim.d
        if not hasattr(s, "ids"):
            s.ids = [m.actuator(n).id for n in MUS]
            s.qa = [m.joint(j).qposadr[0] for j in J]; s.va = [m.joint(j).dofadr[0] for j in J]
        h = d.body("r_thigh").xpos; k = d.body("r_shin").xpos
        s.rows.append((d.time, sim.contacts()["r_foot"], math.atan2(k[0] - h[0], h[2] - k[2]),
                       *[d.qpos[a] for a in s.qa], *[d.qvel[a] for a in s.va],
                       *[d.act[m.actuator_actadr[i]] for i in s.ids], float(d.subtree_linvel[m.body("pelvis").id][0])))
ap = argparse.ArgumentParser()
ap.add_argument("task"); ap.add_argument("params"); ap.add_argument("controller")
ap.add_argument("--seconds", type=float, default=16); ap.add_argument("--t0", type=float, default=8); ap.add_argument("--seed", type=int)
ap.add_argument("--npz")
a = ap.parse_args()
task = load_task(a.task); task.seed = a.seed
sim = Sim(task, params=read_params(a.params), controller=None if a.controller == "-" else a.controller)
r = R(); res = sim.run(a.seconds, recorder=r)
A = np.array(r.rows); t = A[:, 0]; on = A[:, 1] > 0.05
runs, s0 = [], None
for k in range(1, len(A)):
    if on[k] and s0 is None:
        s0 = k
    elif not on[k] and s0 is not None:
        if runs and t[s0] - t[runs[-1][1]] < 0.02:
            runs[-1] = (runs[-1][0], k)
        else:
            runs.append((s0, k))
        s0 = None
runs = [(x, y) for x, y in runs if t[x] > a.t0 and t[y] - t[x] >= 0.03]
tc = float(np.mean([t[y] - t[x] for x, y in runs]))
grid = np.arange(-0.01, tc + 0.011, 0.01)
prof = []
for g in grid:
    vals = [np.array([np.interp(t[x] + g, t, A[:, c]) for c in range(2, A.shape[1])]) for x, y in runs]
    prof.append(np.mean(vals, axis=0))
P = np.array(prof)
print(f"{a.task}: speed {np.mean(A[t > a.t0, -1]):.2f} m/s, fell {res['fell']}, contact {tc:.3f} s over {len(runs)} stances")
print(" t(ms)  thigh  hip   knee  ankle  | hipv  kneev  anklev | " + " ".join(n[2:9] for n in MUS))
for g, p in zip(grid, P):
    print(f"{1000 * g:6.0f} {p[0]:6.2f} {p[1]:5.2f} {p[2]:5.2f} {p[3]:6.2f} | {p[4]:5.1f} {p[5]:6.1f} {p[6]:6.1f} | " + " ".join(f"{x:7.2f}" for x in p[7:18]))
if a.npz:
    np.savez_compressed(a.npz, grid=grid, prof=P, tc=tc)
