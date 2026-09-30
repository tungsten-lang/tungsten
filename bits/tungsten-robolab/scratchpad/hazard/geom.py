"""geom.py DIR [k]: margin of recfem_r's KnExt wrap at a captured hold state and its sensitivity to every qpos coordinate of the right leg.

DIR = a capture directory (model.mjb + ring.npz, scratchpad/blowup/capture.py); k = the ring state (default: the last one).
Finite differences on the raw qpos (no constraint projection: the coupled follower coordinates of the knee are perturbed one at a
time, so this shows WHICH coordinate carries the margin), then the same for the leader joints with the followers moved along the
model's own joint equalities (polynomials), which is what a change of the commanded knee does in the simulation up to the equality's softness.
"""
import sys

import mujoco
import numpy as np

sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/blowup")
import replaylib  # noqa: E402
import wrapscan  # noqa: E402

D = sys.argv[1]
m, ring = replaylib.load(D)
replaylib.quiet()
k = int(sys.argv[2]) if len(sys.argv) > 2 else len(ring["t"]) - 1
d = replaylib.data_at(m, ring, k)
q0 = d.qpos.copy()
seg = [s for s in wrapscan.segments(m) if s[1] == "recfem_r_tendon"][0]
J = mujoco.mjtObj.mjOBJ_JOINT


def margin(q):
    d.qpos[:] = q
    mujoco.mj_fwdPosition(m, d)
    r = wrapscan.probe(m, d, seg, exact_below=0.0)
    return np.nan if r is None or r[0] is None else r[0]


print(f"state {k} (t = {ring['t'][k]:.3f}): margin {margin(q0):+.4e}")
names = []
for j in range(m.njnt):
    n = mujoco.mj_id2name(m, J, j)
    if n and n.endswith("_r") or (n and "_r_" in n) or (n and "knee_angle_r" in n):
        names.append((j, n))
print("raw-coordinate sensitivities dmargin/dq (per rad or per m), joints whose name ends in _r or has _r_:")
rows = []
for j, n in names:
    a = m.jnt_qposadr[j]
    if m.jnt_type[j] not in (mujoco.mjtJoint.mjJNT_HINGE, mujoco.mjtJoint.mjJNT_SLIDE):
        continue
    h = 1e-5
    qp, qm = q0.copy(), q0.copy()
    qp[a] += h
    qm[a] -= h
    s = (margin(qp) - margin(qm)) / (2 * h)
    if np.isfinite(s) and abs(s) > 1e-6:
        rows.append((abs(s), n, s, q0[a]))
for _, n, s, q in sorted(rows, reverse=True):
    print(f"  {n:34s} q {q:+.5f}  dm/dq {s:+.4f}")

# leader joints with the followers moved along the joint equalities
eqs = []
for e in range(m.neq):
    if int(m.eq_type[e]) == int(mujoco.mjtEq.mjEQ_JOINT):
        eqs.append((int(m.eq_obj1id[e]), int(m.eq_obj2id[e]), m.eq_data[e][:5].copy()))


def move(q, leader, delta):
    q = q.copy()
    q[m.jnt_qposadr[leader]] += delta
    changed = {leader}
    for _ in range(3):
        for a, b, c in eqs:
            if b in changed:
                x = q[m.jnt_qposadr[b]]
                q[m.jnt_qposadr[a]] = sum(c[i] * x ** i for i in range(5))
                changed.add(a)
    return q


print("leader joints, followers moved along the equalities (their polynomial value replaces the state's):")
for nm in ("hip_flexion_r", "hip_adduction_r", "hip_rotation_r", "knee_angle_r", "ankle_angle_r", "subtalar_angle_r", "hip_flexion_l", "hip_adduction_l", "knee_angle_l", "lat_bending", "flex_extension"):
    try:
        j = m.joint(nm).id
    except KeyError:
        continue
    h = 1e-4
    s = (margin(move(q0, j, h)) - margin(move(q0, j, -h))) / (2 * h)
    print(f"  {nm:20s} dm/dq {s:+.4f}")
print("margin with the followers re-set to their polynomial values at zero delta:", f"{margin(move(q0, m.joint('knee_angle_r').id, 0.0)):+.4e}")
