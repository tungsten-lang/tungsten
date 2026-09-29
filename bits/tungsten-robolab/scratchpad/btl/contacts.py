import os, sys, numpy as np, mujoco
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from bridge import Sim
from dribble_btl import DribbleBtlTask
def load(p):
    out = {}
    for line in open(p):
        t = line.split()
        if len(t) >= 2 and not line.startswith("#"): out[t[0]] = float(t[1])
    return out
pfile, seed, lo, hi = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
over = dict(kv.split("=") for kv in sys.argv[5].split(",")) if len(sys.argv) > 5 and sys.argv[5] else {}
t = DribbleBtlTask(); t.body_kind = "v3"; t.seed = seed
params = load(pfile); params.update({k: float(v) for k, v in over.items()})
sim = Sim(t, params=params, controller="bin/robolab_dribble_btl")
orig = t.before_step
f6 = np.zeros(6)
def hook(m, d):
    orig(m, d)
    if lo <= d.time <= hi and int(round(d.time * 1000)) % 3 == 0:
        for i in range(d.ncon):
            c = d.contact[i]
            if t.ball_geom in (c.geom1, c.geom2):
                other = c.geom2 if c.geom1 == t.ball_geom else c.geom1
                if other == t.floor_geom: continue
                mujoco.mj_contactForce(m, d, i, f6)
                n = c.frame[:3] * (1 if c.geom1 == t.ball_geom else -1)  # from ball to other
                print(f"{d.time:.3f} {m.geom(other).name:12s} fn {f6[0]/t.ball_w:6.1f} ft {np.linalg.norm(f6[1:3])/t.ball_w:5.1f} n(ball->hand) {n.round(2)} pos-ball {(c.pos - d.body('ball').xpos).round(3)} bv {d.qvel[t.ball_dof:t.ball_dof+3].round(2)}")
t.before_step = hook
sim.run(hi + 0.01)
