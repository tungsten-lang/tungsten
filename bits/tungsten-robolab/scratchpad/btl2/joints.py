"""Joint angles (and limits) of one arm through a window: python joints.py ctl params seed side t0 t1 [overrides] [every_ms]"""
import sys
import numpy as np
sys.path.insert(0, "scratchpad/btl2")
from common import load, parse_over
from bridge import Sim
from dribble_btl import DribbleBtlTask
ctl, pfile, seed, side, t0, t1 = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], float(sys.argv[5]), float(sys.argv[6])
over = sys.argv[7] if len(sys.argv) > 7 else ""
every = int(sys.argv[8]) if len(sys.argv) > 8 else 20
params = load(pfile); params.update(parse_over(over))
t = DribbleBtlTask(); t.body_kind = "v3"; t.seed = seed
sim = Sim(t, params=params, controller=ctl)
names = ["shoulder_flex", "shoulder_abd", "shoulder_rot", "elbow", "wrist_flex", "wrist_dev", "finger_mcp", "finger_pip"]
m = sim.m
lims = {n: m.jnt_range[m.joint(f"{side}_{n}").id] for n in names}
print("limits", {n: [round(float(x), 2) for x in lims[n]] for n in names})
print("trunk joints:", {n: [round(float(x), 2) for x in m.jnt_range[m.joint(n).id]] for n in ("spine_flex", "spine_rot", "spine_lat")})
orig = t.before_step
def hook(mm, d):
    orig(mm, d)
    k = int(round(d.time * 1000))
    if k % every or not (t0 <= d.time <= t1): return
    q = [float(d.qpos[mm.jnt_qposadr[mm.joint(f"{side}_{n}").id]]) for n in names]
    qd = [float(d.qvel[mm.jnt_dofadr[mm.joint(f"{side}_{n}").id]]) for n in names]
    sp = [float(d.qpos[mm.jnt_qposadr[mm.joint(n).id]]) for n in ("spine_flex", "spine_rot")]
    print(f"{d.time:.3f} q " + " ".join(f"{x:+.2f}" for x in q) + " | qd " + " ".join(f"{x:+.1f}" for x in qd) + f" | spine {sp[0]:+.2f} {sp[1]:+.2f}")
t.before_step = hook
sim.run(t1 + 0.01)
