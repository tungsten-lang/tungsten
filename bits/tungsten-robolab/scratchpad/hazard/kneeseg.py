"""kneeseg.py DIR [k]: margins of EVERY wrapped segment of the right (swing) leg as the knee angle is swept, from a captured hold state.

The knee leader joint is swept with its follower coordinates (patella etc.) moved along the model's joint equalities (polynomials); variant B keeps the
state's deviation of every follower from its polynomial value (the soft-equality stretch the quadriceps force leaves) added on top. For every segment
the zero crossings of the margin (the knee angles at which the tendon line grazes its wrap: MuJoCo 3.6.0's length_circle NaN hazard) and the slope there.
Prints the crossings in [0.9, 2.1] rad and, for the parked knee angle, the distance to the nearest crossing of each segment.
"""
import sys

import mujoco
import numpy as np

sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/blowup")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/hazard")
import replaylib  # noqa: E402
import wscan2  # noqa: E402

D = sys.argv[1]
m, ring = replaylib.load(D)
replaylib.quiet()
k = int(sys.argv[2]) if len(sys.argv) > 2 else len(ring["t"]) - 1
d = replaylib.data_at(m, ring, k)
q0 = d.qpos.copy()
A = wscan2.AllSegs(m)
J = mujoco.mjtObj.mjOBJ_JOINT
knee = m.joint("knee_angle_r").id
eqs = [(int(m.eq_obj1id[e]), int(m.eq_obj2id[e]), m.eq_data[e][:5].copy()) for e in range(m.neq) if int(m.eq_type[e]) == int(mujoco.mjtEq.mjEQ_JOINT)]
poly = lambda c, x: sum(c[i] * x ** i for i in range(5))


def followers_of(leader):
    out, changed = [], {leader}
    for _ in range(3):
        for a, b, c in eqs:
            if b in changed and a not in changed:
                out.append((a, b, c))
                changed.add(a)
    return out


fol = followers_of(knee)
kpark = q0[m.jnt_qposadr[knee]]
dev = {a: q0[m.jnt_qposadr[a]] - poly(c, q0[m.jnt_qposadr[b]]) for a, b, c in fol}


def set_knee(angle, keep_dev):
    q = q0.copy()
    q[m.jnt_qposadr[knee]] = angle
    for a, b, c in fol:
        q[m.jnt_qposadr[a]] = poly(c, q[m.jnt_qposadr[b]]) + (dev[a] if keep_dev else 0.0)
    return q


def margins(q):
    d.qpos[:] = q
    mujoco.mj_fwdPosition(m, d)
    return A.margins(d)


ks = np.arange(0.9, 2.1001, 0.005)
sel = [i for i, n in enumerate(A.names) if n.split("@")[0].endswith("_r_tendon") and not n.startswith(("IL_", "LT", "rect"))]
print(f"state {k} t={ring['t'][k]:.2f}: parked knee_angle_r {kpark:.4f}; follower deviations from their polynomials (m or rad):",
      {mujoco.mj_id2name(m, J, a): float(f"{v:.2e}") for a, v in dev.items()})
for keep in (False, True):
    M = np.array([margins(set_knee(a, keep)) for a in ks])
    print(f"\n== followers {'polynomial + the state deviation (force stretch kept)' if keep else 'pure polynomial'}: tangent knee angles per right-leg segment")
    for i in sel:
        col = M[:, i]
        cr = []
        for j in range(len(ks) - 1):
            if np.isfinite(col[j]) and np.isfinite(col[j + 1]) and col[j] * col[j + 1] <= 0 and abs(col[j] - col[j + 1]) < 0.5:
                x = ks[j] + (ks[j + 1] - ks[j]) * col[j] / (col[j] - col[j + 1])
                sl = (col[j + 1] - col[j]) / (ks[j + 1] - ks[j])
                cr.append((round(float(x), 4), round(float(sl), 2)))
        near = min((abs(x - kpark) for x, _ in cr), default=None)
        print(f"  {A.names[i]:44s} crossings (knee, slope/rad): {cr}   nearest to parked: {'-' if near is None else f'{near:.3f} rad'}")
