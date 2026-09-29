"""Palm / ball trace around the passes: python scratchpad/btl2/palm.py ctl params seed t0 t1 [overrides] [every_ms]

Prints, every `every_ms` (default 10) of sim time in [t0, t1], the ball's position and velocity, each
palm's position and velocity (world frame), the chunk labels of the hand tracks and whether each hand
touches the ball.  Run from bits/tungsten-robolab.
"""
import os
import sys

import mujoco
import numpy as np

sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
sys.path.insert(0, "scratchpad/btl2")
from bridge import Sim  # noqa: E402
from dribble_btl import DribbleBtlTask  # noqa: E402
from common import load, parse_over  # noqa: E402


def main():
    ctl, pfile, seed, t0, t1 = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
    over = sys.argv[6] if len(sys.argv) > 6 else ""
    every = int(sys.argv[7]) if len(sys.argv) > 7 else 10
    params = load(pfile)
    params.update(parse_over(over))
    t = DribbleBtlTask()
    t.body_kind = "v3"
    t.seed = seed
    sim = Sim(t, params=params, controller=ctl)
    orig = t.before_step
    vel = np.zeros(6)

    def hook(m, d):
        orig(m, d)
        k = int(round(d.time * 1000))
        if k % every or not (t0 <= d.time <= t1) or not hasattr(t, "ball_geom"):
            return
        p = d.body("ball").xpos
        v = d.qvel[t.ball_dof:t.ball_dof + 3]
        row = [f"{d.time:6.3f}", f"ball {p[0]:+.2f} {p[1]:+.2f} {p[2]:.2f} v {v[0]:+.2f} {v[1]:+.2f} {v[2]:+.2f}"]
        f = t.ball_forces(m, d)
        for s in "lr":
            sid = m.site(s + "_palm").id
            mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_SITE, sid, vel, 0)
            pp = d.site(s + "_palm").xpos
            hb = d.body(s + "_hand")
            nrm = -hb.xmat.reshape(3, 3)[:, 0]
            rel = p - (hb.xpos + hb.xmat.reshape(3, 3) @ np.array([-0.018, 0.0, -0.12]))
            row.append(f"{s}palm {pp[0]:+.2f} {pp[1]:+.2f} {pp[2]:.2f} v {vel[3]:+.2f} {vel[4]:+.2f} {vel[5]:+.2f} n {nrm[0]:+.2f} {nrm[1]:+.2f} {nrm[2]:+.2f} rel {rel[0]:+.2f} {rel[1]:+.2f} {rel[2]:+.2f}"
                       + (" T" if f[s] > 0.3 * t.ball_w else "  "))
        lab = [x for x in sim.label.split("|") if x.startswith("left") or x.startswith("right")]
        row.append(" ".join(lab))
        print(" | ".join(row))

    t.before_step = hook
    r = sim.run(t1 + 0.01)
    print({k: r.get(k) for k in ("btl_ok", "btl_tried", "btl_streak", "lost")})
    print([(e["t"], e["k"], e["why"]) for e in r["btl_log"]])


if __name__ == "__main__":
    main()
