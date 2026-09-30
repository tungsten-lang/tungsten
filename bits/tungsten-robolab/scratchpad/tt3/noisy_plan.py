"""Add execution noise to a kinematic-paddle plan (agent T3): the pad's pitch and yaw (deg), its velocity (m/s per world axis) and its in-plane position (m per in-plane axis)
are perturbed per serve (Gaussian, fixed RNG from the serve's seed and --nseed); the ball's contact point p_hit (= P + 0.04 n_out) stays where the ball is, so a position error moves the
pad centre away from the ball IN THE FACE PLANE (a hit near the rim, or a miss past it).

    .venv-myo/bin/python scratchpad/tt3/noisy_plan.py IN.json OUT.json --sp 11 --sy 3.5 --sv 0.5 --spos 0.043 [--nseed 1]
"""
import argparse, json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(HERE, "playground"))
import tt_impact as ti

ap = argparse.ArgumentParser()
ap.add_argument("inp"); ap.add_argument("out")
ap.add_argument("--sp", type=float, default=0.0); ap.add_argument("--sy", type=float, default=0.0)
ap.add_argument("--sv", type=float, default=0.0); ap.add_argument("--spos", type=float, default=0.0)
ap.add_argument("--nseed", type=int, default=1)
a = ap.parse_args()
plans = json.load(open(a.inp))
out = {}
for sd, p in plans.items():
    rng = np.random.default_rng([int(sd), a.nseed, 7])
    n_out = np.array(p["n_out"]); P = np.array(p["P"]); v = np.array(p["v"])
    p_hit = P + 0.04 * n_out
    n_pos = -n_out
    pit, yaw = ti.angles_from_normal(n_pos[None, :]); pit, yaw = float(pit[0]), float(yaw[0])
    z = rng.standard_normal(7)
    n_new = -ti.normal_from_angles(pit + np.radians(a.sp) * z[0], yaw + np.radians(a.sy) * z[1])
    # in-plane basis of the new face
    e1 = np.cross(n_new, [0.0, 0.0, 1.0]); e1 /= np.linalg.norm(e1); e2 = np.cross(n_new, e1)
    delta = a.spos * (z[2] * e1 + z[3] * e2)
    q = dict(p)
    q["n_out"] = n_new.tolist()
    q["P"] = (p_hit - 0.04 * n_new + delta).tolist()
    q["v"] = (v + a.sv * z[4:7]).tolist()
    out[sd] = q
json.dump(out, open(a.out, "w"))
print(f"{a.out}: {len(out)} plans, noise pitch {a.sp} yaw {a.sy} deg, velocity {a.sv} m/s, position {a.spos} m (nseed {a.nseed})")
