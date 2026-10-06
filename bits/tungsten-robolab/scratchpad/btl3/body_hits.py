"""Which body part does a failing pass's ball hit?  Re-runs seeds and logs the ball's contacts with anything but the floor and the passing hand.

    .venv/bin/python scratchpad/btl3/body_hits.py ctl params seeds_csv secs
"""
import sys, collections
import mujoco
import numpy as np
sys.path.insert(0, "scratchpad/btl2"); sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from common import load
import oracle_lib as O

ctl, pfile, seeds, secs = sys.argv[1], sys.argv[2], [int(s) for s in sys.argv[3].split(",")], float(sys.argv[4])
params = load(pfile)
C = collections.Counter()
for seed in seeds:
    t, sim = O.build_sim(seed, params, ctl)
    m, d = sim.m, sim.d
    t.reset(m, d); mujoco.mj_forward(m, d); sim.start_controller()
    bg = m.geom("ball").id
    hits = []
    try:
        while d.time < secs:
            sim.tick()
            for _ in range(5):
                t.before_step(m, d); mujoco.mj_step(m, d)
                for i in range(d.ncon):
                    g1, g2 = d.contact.geom1[i], d.contact.geom2[i]
                    if bg not in (g1, g2): continue
                    o = g2 if g1 == bg else g1
                    gname = mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_GEOM, o) or "?"
                    bname = mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_BODY, m.geom_bodyid[o]) or "?"
                    if gname == "floor": continue
                    hits.append((round(d.time, 3), bname, gname, np.round(d.xpos[m.body("ball").id], 2).tolist()))
    finally:
        sim.stop_controller()
    # collapse to first contact per (body) episode
    ep = []
    for h in hits:
        if not ep or ep[-1][1] != h[1] or h[0] - ep[-1][0] > 0.05:
            ep.append(h)
    nonhand = [e for e in ep if not (e[1].endswith("hand") or "finger" in e[2] or "hand" in e[2])]
    for e in nonhand: C[e[1] + ":" + e[2]] += 1
    print(seed, "non-hand contacts:", nonhand[:6])
print("counts:", C.most_common())
