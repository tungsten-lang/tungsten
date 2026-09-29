import os, sys, json, numpy as np
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from bridge import Sim
from dribble_btl import DribbleBtlTask
def load(p):
    out = {}
    for line in open(p):
        t = line.split()
        if len(t) >= 2 and not line.startswith("#"): out[t[0]] = float(t[1])
    return out
pfile, seed, secs = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
over = dict(kv.split("=") for kv in sys.argv[4].split(",")) if len(sys.argv) > 4 and sys.argv[4] else {}
lo, hi = (float(sys.argv[5]), float(sys.argv[6])) if len(sys.argv) > 6 else (0, 99)
ctl = sys.argv[7] if len(sys.argv) > 7 else "bin/robolab_dribble_btl"
t = DribbleBtlTask(); t.body_kind = "v3"; t.seed = seed
params = load(pfile); params.update({k: float(v) for k, v in over.items()})
sim = Sim(t, params=params, controller=ctl)
rows = []
orig_tick = sim.tick
def tick():
    out = orig_tick()
    d = sim.d
    if lo <= d.time <= hi:
        p = d.body("ball").xpos; v = d.qvel[t.ball_dof:t.ball_dof + 3]
        f = t.ball_forces(sim.m, d) if hasattr(t, "ball_geom") else {"r": 0, "l": 0}
        rp = d.site("r_palm").xpos; lp = d.site("l_palm").xpos
        rn = -d.body("r_hand").xmat.reshape(3, 3)[:, 0]
        print(f"{d.time:5.3f} {sim.label[:60]:60s} ball {p.round(2)} v {v.round(2)} R {rp.round(2)} n {rn.round(2)} L {lp.round(2)} fR {f['r']/t.ball_w if hasattr(t,'ball_w') else 0:5.1f} fL {f['l']/t.ball_w if hasattr(t,'ball_w') else 0:5.1f}")
    return out
sim.tick = tick
r = sim.run(secs)
print({k: r.get(k) for k in ("btl_rate", "btl_ok", "btl_opportunities", "lost", "gate_passes")})
print(r["btl_log"])
