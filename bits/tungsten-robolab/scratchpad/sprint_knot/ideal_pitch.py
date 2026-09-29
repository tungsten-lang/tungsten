"""DIAGNOSTIC: the ideal stance's pelvis-pitch stabiliser torque (N m) through the stance, next to the
stance hip's muscle torque, at one speed of a sprint_limits run file."""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
import numpy as np
import sprint_limits as SL
prof, runs, v = sys.argv[1], sys.argv[2], float(sys.argv[3])
run = None
for name in runs.split(","):
    for r in json.load(open(os.path.join(ROOT, "out", "sprint_limits", name + ".json")))["runs"]:
        if abs(r["v"] - v) < 1e-6:
            run = r
rig = SL.Rig(prof if prof != "none" else None, None)
m = rig.m
e_p = m.equality("lock_root_pitch").id
hip = m.joint("r_hip_flex").dofadr[0]
rows = []
orig = SL.mujoco.mj_step
def rec(mm, d):
    orig(mm, d)
    rows.append((d.time, rig._stabiliser(d, e_p), float(d.qfrc_actuator[hip])))
SL.mujoco.mj_step = rec
st = rig.stance(run["x_stance"], v, record=True)
SL.mujoco.mj_step = orig
R = np.array(rows); tr = np.array(st["grf_trace"])
td = R[len(R) - len(tr), 0] - tr[0, 0]
t = R[:, 0] - td
w = (t >= 0) & (t <= st["tc"])
dt = m.opt.timestep
print(f"v {v}: tc {st['tc']:.3f} s, stabiliser torque over the stance: min {R[w,1].min():.0f}, max {R[w,1].max():.0f}, "
      f"mean |.| {np.abs(R[w,1]).mean():.0f} N m, net impulse {R[w,1].sum()*dt:+.2f} N m s; stance-hip muscle torque range "
      f"{R[w,2].min():.0f} .. {R[w,2].max():.0f} N m; body weight x leg length {rig.mass*9.81*rig.leg_length:.0f} N m")
for k in np.nonzero(w)[0][::10]:
    print(f"  {1000*t[k]:5.0f} ms  stabiliser {R[k,1]:7.1f}  hip muscles {R[k,2]:7.1f}")
