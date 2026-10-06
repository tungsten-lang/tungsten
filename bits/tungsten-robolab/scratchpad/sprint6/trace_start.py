"""trace_start.py PARAMS CONTROLLER SEED SECONDS [t0 t1] [--every 0.05] [--set k=v,...]: the stand / lean phase of one standing start in detail
(labelled beyond-human body): chunk label, COM - feet, COM speed, torso and pelvis pitch, joint angles (deg) of ankle, knee, hip, spine, foot contact
forces, and the centre of pressure relative to the feet midpoint. For the early backward collapse (agent S6)."""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
os.environ["ROBOLAB_CALIB"] = "v4"
os.environ["ROBOLAB_PROFILE"] = "beyond"
os.environ["ROBOLAB_PROFILE_PARTS"] = "strength,speed,tendon,activation"
sys.path.insert(0, os.path.join(ROOT, "playground"))
import mujoco  # noqa: E402
from practice import load_task, read_params  # noqa: E402
from bridge import Sim  # noqa: E402

args = [a for a in sys.argv[1:] if not a.startswith("--")]
opts = {a.split("=")[0]: (a.split("=", 1)[1] if "=" in a else "1") for a in sys.argv[1:] if a.startswith("--")}
params_path, ctl, seed, secs = args[0], args[1], int(args[2]), float(args[3])
t0 = float(args[4]) if len(args) > 4 else 0.0
t1 = float(args[5]) if len(args) > 5 else secs
every = float(opts.get("--every", 0.05))
params = read_params(params_path) if params_path != "-" else {}
for kv in opts.get("--set", "").split(","):
    if kv:
        k, v = kv.split("=")
        params[k] = float(v)


class R:
    def __init__(s):
        s.nx = 0.0
        s.rows = []

    def maybe_capture(s, sim):
        d, m = sim.d, sim.m
        if d.time < s.nx:
            return
        s.nx = d.time + every
        pid = m.body("pelvis").id
        tid = m.body("torso").id
        tu = d.xmat[tid].reshape(3, 3)[:, 2]
        pu = d.xmat[pid].reshape(3, 3)[:, 2]
        fx = 0.5 * (float(d.body("l_foot").xpos[0]) + float(d.body("r_foot").xpos[0]))
        com = float(d.subtree_com[pid][0])

        def q(j):
            return math.degrees(float(d.qpos[m.joint(j).qposadr[0]]))
        # centre of pressure from the contact forces on the feet (x)
        num = den = 0.0
        force = [0.0] * 6
        import numpy as np
        f6 = np.zeros(6)
        for i in range(d.ncon):
            c = d.contact[i]
            g = (c.geom1, c.geom2)
            fl = m.geom("floor").id
            if fl in g:
                other = g[0] if g[1] == fl else g[1]
                mujoco.mj_contactForce(m, d, i, f6)
                fn = abs(f6[0])
                num += fn * float(c.pos[0])
                den += fn
        cop = (num / den - fx) if den > 1e-6 else float("nan")
        s.rows.append((d.time, sim.label, com - fx, float(d.subtree_linvel[pid][0]), math.atan2(tu[0], tu[2]), math.atan2(pu[0], pu[2]),
                       q("l_ankle"), q("r_ankle"), q("l_knee"), q("l_hip_flex"), q("spine_flex"), den / sim.weight, cop,
                       float(d.xpos[pid][2])))


from practice import load_task  # noqa: E402,F811
t = load_task(opts.get("--task", "run_v4"))
t.seed = seed
sim = Sim(t, params=params, controller=os.path.abspath(ctl))
r = R()
res = sim.run(secs, recorder=r)
print("fell", res.get("fell"), "time", res.get("time"), "peak", res.get("peak_speed_1s"))
print(" time  chunk       com-feet   v     torsoP pelvP | l_ank r_ank l_knee l_hip spine | Fz/BW  CoP-feet pelvis_z")
for (tm, lab, cx, v, p, pp, la, ra, lk, lh, sp, fz, cop, z) in r.rows:
    if t0 <= tm <= t1:
        print("%5.2f %-10s %+.3f %+.2f  %+.2f %+.2f | %+6.1f %+6.1f %+6.1f %+6.1f %+6.1f | %.2f %+.3f %.2f" % (tm, lab, cx, v, p, pp, la, ra, lk, lh, sp, fz, cop, z))
