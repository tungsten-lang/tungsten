"""How well ball_rise predicts where the rising ball crosses a height."""
import sys, numpy as np
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from bridge import Sim
from dribble_btl import DribbleBtlTask
from grid import load
t = DribbleBtlTask(); t.body_kind = "v3"; t.seed = 12
params = load("scratchpad/btl/params/k1.txt"); params["bt_plan"] = 0
sim = Sim(t, params=params, controller="scratchpad/btl/bin/k6")
ZC = 0.66
preds = []; actual = []
orig = t.before_step
state = {"prev_vz": 0, "crossed": False}
def hook(m, d):
    orig(m, d)
    if not hasattr(t, "ball_geom") or t.released_t is None: return
    p = d.body("ball").xpos.copy(); v = d.qvel[t.ball_dof:t.ball_dof + 3].copy()
    if int(round(d.time * 1000)) % 20 == 0:
        spin = d.body("ball").xmat.reshape(3, 3) @ d.qvel[t.ball_dof + 3:t.ball_dof + 6]
        r = t.predict_rise(p, v, spin)
        vz = r[5]
        if vz > 0.5:
            disc = vz * vz - 2 * 9.81 * (ZC - r[2])
            s = (vz - np.sqrt(disc)) / 9.81 if disc > 0 else vz / 9.81
            preds.append((round(d.time, 3), round(d.time + r[6] + s, 3), round(r[0] + r[3] * s, 3), round(r[1] + r[4] * s, 3)))
    if v[2] > 0 and p[2] >= ZC and not state["crossed"]:
        state["crossed"] = True; actual.append((round(d.time, 3), round(float(p[0]), 3), round(float(p[1]), 3)))
    if v[2] < 0: state["crossed"] = False
t.before_step = hook
sim.run(3.5)
print("actual crossings", actual)
for pr in preds: print("pred at", pr[0], "-> t", pr[1], "xy", pr[2:])
