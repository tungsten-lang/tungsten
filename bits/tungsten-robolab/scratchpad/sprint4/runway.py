"""runway.py PARAMS CONTROLLER SEED SECONDS [--marks 39,44]: the speed profile along the runway of a standing-start run on the current body
(env from scratchpad/sprint3/env.sh): time, distance and speed (pelvis-subtree COM speed) at the given marks, the mean speed over the last 5 m before each mark,
and the peak so far. For the long-jump question: the speed at the board of a 44 m check mark."""
import argparse, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
import numpy as np
from practice import load_task, read_params
from bridge import Sim

ap = argparse.ArgumentParser()
ap.add_argument("params"); ap.add_argument("controller"); ap.add_argument("seed", type=int); ap.add_argument("seconds", type=float)
ap.add_argument("--marks", default="39,44")
a = ap.parse_args()


class R:
    def __init__(s):
        s.rows = []
    def maybe_capture(s, sim):
        d = sim.d
        pid = sim.m.body("pelvis").id
        s.rows.append((d.time, float(d.subtree_com[pid][0]), float(d.subtree_linvel[pid][0])))


t = load_task("run_v4"); t.seed = a.seed
sim = Sim(t, params=read_params(a.params), controller=a.controller)
r = R()
res = sim.run(a.seconds, recorder=r)
X = np.array(r.rows)
x0 = X[0, 1]
print("fell", res.get("fell"), "t", res.get("time"), "peak", res.get("peak_speed_1s"))
for mk in [float(m) for m in a.marks.split(",")]:
    i = np.searchsorted(X[:, 1] - x0, mk)
    if i >= len(X):
        print(f"mark {mk} m: not reached"); continue
    j = np.searchsorted(X[:, 1] - x0, mk - 5.0)
    print(f"mark {mk:5.1f} m: t {X[i,0]:.2f} s, speed {X[i,2]:.2f} m/s, mean speed over the last 5 m {5.0/(X[i,0]-X[j,0]):.2f} m/s")
for mk in (10, 20, 30, 40, 50, 60):
    i = np.searchsorted(X[:, 1] - x0, mk)
    if i < len(X):
        print(f"  {mk:3d} m: t {X[i,0]:5.2f} s  v {X[i,2]:.2f}")
