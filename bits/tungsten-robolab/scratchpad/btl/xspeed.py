"""Ball speed where the hand changes (the receiving hand's first touch): v3 crossover vs BTL.
python xspeed.py task params ctl seed secs"""
import sys, numpy as np, mujoco, importlib
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks"); sys.path.insert(0, "scratchpad/btl")
from bridge import Sim
from grid import load
task, pfile, ctl, seed, secs = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), float(sys.argv[5])
if task == "dribble_v3":
    from dribble_v3 import DribbleV3Task as T
    t = T()
elif task == "dribble":
    from dribble import DribbleTask as T
    t = T()
else:
    from dribble_btl import DribbleBtlTask as T
    t = T(); t.body_kind = "v3"
t.seed = seed
sim = Sim(t, params=load(pfile), controller=ctl)
orig = t.before_step
state = {"last": None, "prev_touch": set()}
out = []
def hook(m, d):
    orig(m, d)
    bid = m.body("ball").id
    touching = set()
    for i in range(d.ncon):
        c = d.contact[i]
        b1, b2 = m.geom_bodyid[c.geom1], m.geom_bodyid[c.geom2]
        if bid not in (b1, b2): continue
        o = b2 if b1 == bid else b1
        nm = m.body(o).name
        state.setdefault("names", set()).add(nm)
        if nm.startswith("l_") and ("hand" in nm or "finger" in nm or "palm" in nm): touching.add("l")
        if nm.startswith("r_") and ("hand" in nm or "finger" in nm or "palm" in nm): touching.add("r")
    for s in touching - state["prev_touch"]:
        if state["last"] is not None and s != state["last"]:
            v = d.qvel[t.ball_dof:t.ball_dof + 3] if hasattr(t, "ball_dof") else d.body("ball").cvel[3:]
            out.append((round(d.time, 2), s, round(float(np.hypot(v[0], v[1])), 2), round(float(v[2]), 2), round(float(d.body("ball").xpos[2]), 2)))
        state["last"] = s
    state["prev_touch"] = touching
t.before_step = hook
sim.run(secs)
print(task, seed, "hand changes (t, hand, vh, vz, z):", out)
print(sorted(state.get("names", [])))
print("mean vh", round(float(np.mean([o[2] for o in out])), 2) if out else None)
