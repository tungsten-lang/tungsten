"""Release states of the passes: the ball's velocity and position as each pass leaves its hand.

    .venv/bin/python scratchpad/btl2/ret.py ctl params s0 s1 secs [overrides] [workers]

For every rollout, every hand-to-hand pass (from the task's move log) gets the ball state at the last
instant of the pushing hand's contact before the next floor bounce, and the bounce point. Prints per-seed
rows (pass k: release z, velocity (vx vy vz), bounce xy, outcome) and means by pass index.
"""
import sys

import mujoco
import numpy as np

sys.path.insert(0, "scratchpad/btl2")
from multiprocessing import Pool  # noqa: E402

from common import load, parse_over  # noqa: E402


def run(job):
    ctl, params, seed, secs = job
    from bridge import Sim
    from dribble_btl import DribbleBtlTask
    t = DribbleBtlTask()
    t.body_kind = "v3"
    t.seed = seed
    sim = Sim(t, params=params, controller=ctl)
    orig = t.before_step
    st = {"last": {"r": None, "l": None}, "in": {"r": False, "l": False}, "rel": []}

    def hook(m, d):
        orig(m, d)
        if not hasattr(t, "ball_geom") or t.released_t is None:
            return
        f = t.ball_forces(m, d)
        p = d.body("ball").xpos.copy()
        v = d.qvel[t.ball_dof:t.ball_dof + 3].copy()
        for s in "rl":
            on = f[s] > 0.3 * t.ball_w
            if on:
                st["last"][s] = (d.time, p, v)
            st["in"][s] = on
        if t.events and t.events[-1][1] == "floor" and abs(t.events[-1][0] - d.time) < 1e-9:
            # a bounce: the release state is the later of the two hands' last contacts
            cands = [x for x in st["last"].values() if x is not None]
            if cands:
                last = max(cands, key=lambda x: x[0])
                side = "r" if st["last"]["r"] is last else "l"
                st["rel"].append((side, last[0], last[1], last[2], (float(p[0]), float(p[1])), d.time))
            st["last"] = {"r": None, "l": None}

    t.before_step = hook
    r = sim.run(secs)
    return seed, r, st["rel"]


def main():
    ctl, pfile, s0, s1, secs = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5])
    over = sys.argv[6] if len(sys.argv) > 6 else ""
    workers = int(sys.argv[7]) if len(sys.argv) > 7 else 2
    params = load(pfile)
    params.update(parse_over(over))
    with Pool(workers) as pool:
        res = pool.map(run, [(ctl, params, s, secs) for s in range(s0, s1)])
    agg = {}
    for seed, r, rel in res:
        rows = []
        for k, (side, tl, p, v, b, tb) in enumerate(rel[:4]):
            ok = r["pass_log"][k]["ok"] if k < len(r["pass_log"]) else None
            rows.append(f"{side}: z {p[2]:.2f} v ({v[0]:+.2f} {v[1]:+.2f} {v[2]:+.2f}) |vh| {np.hypot(v[0], v[1]):.2f} bounce ({b[0]:+.2f} {b[1]:+.2f}) {'OK' if ok else '--'}")
            agg.setdefault(k, []).append((p[2], v[0], v[1], v[2], np.hypot(v[0], v[1]), 1.0 if ok else 0.0))
        print(seed, " | ".join(rows))
    for k in sorted(agg):
        a = np.array(agg[k])
        print(f"release {k + 1}: n {len(a)} z {a[:, 0].mean():.2f} vz {a[:, 3].mean():+.2f} (sd {a[:, 3].std():.2f}) vh {a[:, 4].mean():.2f} (sd {a[:, 4].std():.2f}) ok {int(a[:, 5].sum())}")


if __name__ == "__main__":
    main()
