"""Stance diagnostics of a rollout's steady tail vs the ideal-control stance (sprint_limits):
thigh angle from vertical (world) at touchdown / lift-off, knee at TD, contact time and length, mean and peak
vertical GRF (body weights) over contact, vz at lift-off and touchdown."""
import math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
from practice import load_task, read_params
from bridge import Sim
import numpy as np
task_name, par, ctl = sys.argv[1:4]
secs = float(os.environ.get("SECS", "16")); t0 = float(os.environ.get("T0", "8"))
class R:
    def __init__(s): s.rows = []
    def maybe_capture(s, sim):
        m, d = sim.m, sim.d; ct = sim.contacts(); pid = m.body("pelvis").id
        def th(side):
            h = d.body(side + "_thigh").xpos; k = d.body(side + "_shin").xpos
            return math.atan2(k[0] - h[0], h[2] - k[2])
        s.rows.append((d.time, ct["r_foot"], ct["l_foot"] if False else 0, th("r"), d.qpos[m.joint("r_knee").qposadr[0]],
                       d.subtree_linvel[pid][2], d.subtree_com[pid][0], d.subtree_linvel[pid][0]))
task = load_task(task_name); task.seed = None
sim = Sim(task, params=read_params(par), controller=ctl); r = R(); res = sim.run(secs, recorder=r)
A = np.array(r.rows); t = A[:, 0]; on = A[:, 1] > 0.05
runs, a = [], None
for k in range(1, len(A)):
    if on[k] and a is None:
        a = k
    elif not on[k] and a is not None:
        if runs and t[a] - t[runs[-1][1]] < 0.02:
            runs[-1] = (runs[-1][0], k)
        else:
            runs.append((a, k))
        a = None
pairs = [(a, b) for a, b in runs if t[a] > t0 and t[b] - t[a] >= 0.03]
tc = [t[b] - t[a] for a, b in pairs]; Lc = [A[b, 6] - A[a, 6] for a, b in pairs]
fz = [np.mean(A[a:b, 1]) for a, b in pairs]; pk = [np.max(A[a:b, 1]) for a, b in pairs]
print(f"{task_name}: speed {np.mean(A[t > t0, 7]):.2f} m/s  fell {res['fell']}")
print(f"  contact {np.mean(tc):.3f} s   contact length {np.mean(Lc):.3f} m   mean vGRF {np.mean(fz):.2f} BW   peak {np.mean(pk):.2f} BW")
print(f"  thigh at TD {np.mean([A[a, 3] for a, b in pairs]):+.3f} rad   at LO {np.mean([A[b, 3] for a, b in pairs]):+.3f} rad   knee at TD {np.mean([A[a, 4] for a, b in pairs]):.3f} rad")
print(f"  vz at TD {np.mean([A[a, 5] for a, b in pairs]):+.2f}   at LO {np.mean([A[b, 5] for a, b in pairs]):+.2f} m/s   steps {len(pairs)}")
