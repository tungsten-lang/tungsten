"""Where is the wrap tangent of the right rectus femoris in the swing leg's posture space?  usage: knee_map.py DIR
From the parked posture of a capture, sweep knee_angle_r (its coupled patella / translation joints follow through the model's joint equalities)
and report the margin of recfem_r's KnExt wrap, its zero crossing, and how far the parked knee angle is from it."""
import sys
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/blowup")
import numpy as np, mujoco, replaylib, wrapscan

D = sys.argv[1]
m, ring = replaylib.load(D)
replaylib.quiet()
d = replaylib.data_at(m, ring, len(ring["t"]) - 1)
q0 = d.qpos.copy()
segs = [s for s in wrapscan.segments(m) if s[1] == "recfem_r_tendon"]
seg = segs[0]
J = mujoco.mjtObj.mjOBJ_JOINT
knee = m.joint("knee_angle_r").id
# joint equalities: q_dep = poly(q_leader)
eqs = []
for e in range(m.neq):
    if int(m.eq_type[e]) == int(mujoco.mjtEq.mjEQ_JOINT):
        eqs.append((int(m.eq_obj1id[e]), int(m.eq_obj2id[e]), m.eq_data[e][:5].copy()))
print("joint equalities:", len(eqs), " followers of knee_angle_r:", [mujoco.mj_id2name(m, J, a) for a, b, c in eqs if b == knee])


def set_knee(q, angle):
    q = q.copy()
    q[m.jnt_qposadr[knee]] = angle
    changed = {knee}
    for _ in range(3):
        for a, b, c in eqs:
            if b in changed:
                x = q[m.jnt_qposadr[b]]
                q[m.jnt_qposadr[a]] = sum(c[i] * x ** i for i in range(5))
                changed.add(a)
    return q


def margin(q):
    d.qpos[:] = q
    mujoco.mj_fwdPosition(m, d)
    return wrapscan.probe(m, d, seg, exact_below=0.0)[0]


kpark = q0[m.jnt_qposadr[knee]]
print(f"parked knee_angle_r {kpark:.6f}; margin at the parked pose with the model's own coupling: {margin(q0):+.3e}; with set_knee(parked): {margin(set_knee(q0, kpark)):+.3e}")
ks = np.arange(1.30, 2.10, 0.002)
mg = np.array([margin(set_knee(q0, k)) if margin(set_knee(q0, k)) is not None else np.nan for k in ks])
cross = [(ks[i], ks[i + 1]) for i in range(len(ks) - 1) if np.isfinite(mg[i]) and np.isfinite(mg[i + 1]) and mg[i] * mg[i + 1] <= 0]
print("margin vs knee angle (every 0.05 rad):")
for k, v in zip(ks[::25], mg[::25]):
    print(f"  knee {k:.3f}: margin {v:+.3e}")
print("zero crossings (knee angle brackets):", cross)
for a, b in cross:
    lo, hi = a, b
    for _ in range(60):
        mid = 0.5 * (lo + hi)
        if margin(set_knee(q0, lo)) * margin(set_knee(q0, mid)) <= 0:
            hi = mid
        else:
            lo = mid
    print(f"  tangent at knee_angle_r = {0.5 * (lo + hi):.6f} rad (parked {kpark:.6f}; difference {kpark - 0.5 * (lo + hi):+.2e} rad; dmargin/dknee ~ {(margin(set_knee(q0, hi + 1e-4)) - margin(set_knee(q0, hi - 1e-4))) / 2e-4:+.3f} per rad)")
