"""Which body parts does the ball touch, by pass index (the pass whose flight it is): re-runs seeds, logs non-hand non-floor ball contacts.

    OMP_NUM_THREADS=1 .venv/bin/python scratchpad/btl4/body_by_pass.py ctl params s0 s1 secs workers
"""
import sys, collections
import mujoco
import numpy as np
sys.path.insert(0, "scratchpad/btl2"); sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from multiprocessing import Pool


def job(a):
    ctl, pfile, seed, secs = a
    from common import load
    import oracle_lib as O
    params = load(pfile)
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
                    if gname == "floor" or "hand" in gname or "finger" in gname: continue
                    hits.append((round(d.time, 3), bname, np.round(d.xpos[m.body("ball").id], 2).tolist()))
    finally:
        sim.stop_controller()
    met = t.metrics(m, d, [])
    pl = met.get("pass_log", [])
    ts = [e["t"] for e in pl]
    ep = []
    for h in hits:
        if not ep or ep[-1][1] != h[1] or h[0] - ep[-1][0] > 0.05:
            ep.append(h)
    out = []
    for h in ep:
        k = sum(1 for x in ts if x <= h[0]) - 1
        out.append((k + 1, h[1], h[2], h[0]))
    return seed, out, [bool(e["ok"]) for e in pl]


if __name__ == "__main__":
    ctl, pfile, s0, s1, secs, workers = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5]), int(sys.argv[6])
    with Pool(workers) as p:
        res = p.map(job, [(ctl, pfile, s, secs) for s in range(s0, s1)])
    C = collections.defaultdict(collections.Counter)
    first = collections.defaultdict(collections.Counter)
    for seed, out, oks in res:
        seen = set()
        for k, b, pos, t in out:
            C[k][b] += 1
            if k not in seen:
                first[k][b] += 1
                seen.add(k)
    for k in sorted(C):
        print(f"pass {k}: contacts {dict(C[k])}  first-per-start {dict(first[k])}")
