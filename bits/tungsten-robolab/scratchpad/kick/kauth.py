"""Authority map: how far a torque perturbation on each joint (as muscle drive, minimum-norm over the muscles with the right live arms) moves the kick's contact point.
   kauth.py pack.pkl.gz [tau] [dur]"""
import sys
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
import kprobe as P

path = sys.argv[1]
tau = float(sys.argv[2]) if len(sys.argv) > 2 else 20.0
dur = float(sys.argv[3]) if len(sys.argv) > 3 else 0.08
pack = P.load(path)
tr0 = pack["trace"]
ksw = next(i for i, r in enumerate(tr0) if r["lab"] == "swing")
p = P.Probe()
rb = p.run(pack, ksw)
base = P.contact_summary(rb)
cb = P.cross_summary(rb)
print(path.split("/")[-1], "swing tick", ksw, "base", {k: (np.round(v, 3).tolist() if isinstance(v, (list, np.ndarray)) else v) for k, v in base.items() if k != "vtoe"})
joints = ["hip_rotation_r", "hip_adduction_r", "hip_flexion_r", "knee_angle_r", "ankle_angle_r", "subtalar_angle_r",
          "hip_rotation_l", "hip_adduction_l", "hip_flexion_l", "knee_angle_l", "ankle_angle_l", "axial_rotation", "lat_bending", "flex_extension"]
print(f"tau {tau} N m for {dur}s; columns: onset {{0, 0.08, 0.14}} s after the swing start: d(y cm) d(z cm) d(t ms) d(ball speed) d(launch deg) at the first touch (contact vector toe-ball)")
for j in joints:
    for sg in (+1, -1):
        row = []
        for t0 in (0.0, 0.08, 0.14):
            try:
                r = p.run(pack, ksw, perturb=dict(joint=j, sign=sg, tau=tau, t0=t0, dur=dur))
                c = P.contact_summary(r)
                if c.get("toe") is None:
                    row.append("   no contact                ")
                else:
                    bs = c["ball_speed"] or 0.0
                    row.append(f"{100*(c['toe'][1]-base['toe'][1]):+6.1f} {100*(c['toe'][2]-base['toe'][2]):+6.1f} {1000*(c['touch']-base['touch']):+5.0f} {bs-base['ball_speed']:+6.2f} {(c['launch'] or 0)-(base['launch'] or 0):+6.1f}")
            except Exception as e:
                row.append("err " + str(e)[:20])
        print(f"{j:18s} {'+' if sg>0 else '-'} | " + " | ".join(row), flush=True)
