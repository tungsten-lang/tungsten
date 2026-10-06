"""Non-hand contacts of the ball in the flight AFTER a stage's release, for the failing 'body' passes of a stage.
    .venv/bin/python scratchpad/btl3/body_hits2.py ctl params livedir stage secs [max_seeds]"""
import sys, glob, collections
import mujoco
import numpy as np
sys.path.insert(0, "scratchpad/btl2"); sys.path.insert(0, "scratchpad/btl3"); sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from common import load
import oracle_lib as O
import dlib

ctl, pfile, livedir, stage, secs = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), float(sys.argv[5])
mx = int(sys.argv[6]) if len(sys.argv) > 6 else 99
params = load(pfile)
todo = []
for fn in sorted(glob.glob(livedir + "/live_*.npz")):
    z = np.load(fn)
    r = dlib.stage_run(z, stage)
    if r is not None and r["body"] > 0:
        todo.append((int(fn.split("_")[-1].split(".")[0]), float(z["t"][r["kr"]])))
C = collections.Counter()
for seed, trel in todo[:mx]:
    t, sim = O.build_sim(seed, params, ctl)
    m, d = sim.m, sim.d
    t.reset(m, d); mujoco.mj_forward(m, d); sim.start_controller()
    bg = m.geom("ball").id
    ep = []
    try:
        while d.time < secs:
            sim.tick()
            for _ in range(5):
                t.before_step(m, d); mujoco.mj_step(m, d)
                if d.time < trel + 0.005: continue
                for i in range(d.ncon):
                    g1, g2 = d.contact.geom1[i], d.contact.geom2[i]
                    if bg not in (g1, g2): continue
                    o = g2 if g1 == bg else g1
                    gname = mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_GEOM, o) or "?"
                    if gname == "floor" or "hand" in gname or "finger" in gname: continue
                    if not ep or ep[-1][1] != gname or d.time - ep[-1][3] > 0.05:
                        ep.append([round(d.time, 3), gname, np.round(d.xpos[m.body("ball").id], 2).tolist(), d.time])
                    else:
                        ep[-1][3] = d.time
    finally:
        sim.stop_controller()
    first = ep[:1]
    for e in first: C[e[1]] += 1
    print(seed, "release", round(trel, 3), "first non-hand contact after:", [(e[0], e[1], e[2]) for e in first], " n episodes", len(ep))
print(f"stage {stage}:", len(todo), "body failures; first contact counts:", C.most_common())
