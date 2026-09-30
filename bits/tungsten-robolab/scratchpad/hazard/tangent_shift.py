"""tangent_shift.py DIR: how the tangent knee angles of the swing leg's five near segments move with the swing hip's posture (offline, from a captured hold state, force-stretch deviation kept)."""
import sys
import mujoco
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/blowup")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/hazard")
import replaylib, wscan2
m, ring = replaylib.load(sys.argv[1]); replaylib.quiet()
d = replaylib.data_at(m, ring, len(ring["t"]) - 1)
q0 = d.qpos.copy(); A = wscan2.AllSegs(m)
knee = m.joint("knee_angle_r").id
eqs = [(int(m.eq_obj1id[e]), int(m.eq_obj2id[e]), m.eq_data[e][:5].copy()) for e in range(m.neq) if int(m.eq_type[e]) == int(mujoco.mjtEq.mjEQ_JOINT)]
poly = lambda c, x: sum(c[i] * x ** i for i in range(5))
fol, changed = [], {knee}
for _ in range(3):
    for a, b, c in eqs:
        if b in changed and a not in changed:
            fol.append((a, b, c)); changed.add(a)
kpark = q0[m.jnt_qposadr[knee]]
dev = {a: q0[m.jnt_qposadr[a]] - poly(c, q0[m.jnt_qposadr[b]]) for a, b, c in fol}
names = {"recfem": "recfem_r_tendon", "vasint": "vasint_r_tendon", "vasmed": "vasmed_r_tendon", "vaslat": "vaslat_r_tendon", "bfsh": "bfsh_r_tendon"}
idx = {k: [i for i, n in enumerate(A.names) if n.startswith(v)][0] for k, v in names.items()}
ks = np.arange(1.15, 1.95, 0.002)

def tangents(hf=0.0, ha=0.0, hr=0.0):
    out = {}
    cols = {k: [] for k in idx}
    for a_ in ks:
        q = q0.copy()
        q[m.jnt_qposadr[m.joint("hip_flexion_r").id]] += hf
        q[m.jnt_qposadr[m.joint("hip_adduction_r").id]] += ha
        q[m.jnt_qposadr[m.joint("hip_rotation_r").id]] += hr
        q[m.jnt_qposadr[knee]] = a_
        for a, b, c in fol:
            q[m.jnt_qposadr[a]] = poly(c, q[m.jnt_qposadr[b]]) + dev[a]
        d.qpos[:] = q; mujoco.mj_fwdPosition(m, d)
        mg = A.margins(d)
        for k, i in idx.items():
            cols[k].append(mg[i])
    for k, col in cols.items():
        col = np.array(col); x = np.nan
        for j in range(len(ks) - 1):
            if np.isfinite(col[j]) and np.isfinite(col[j + 1]) and col[j] * col[j + 1] <= 0 and abs(col[j] - col[j + 1]) < 0.5:
                x = ks[j] + (ks[j + 1] - ks[j]) * col[j] / (col[j] - col[j + 1]); break
        out[k] = x
    return out

print("swing hip offset (rad)            tangent knee angle of: " + "  ".join(f"{k:>7s}" for k in idx))
for label, kw in [("none", {}), ("hip flexion +0.10", {"hf": 0.10}), ("hip flexion -0.10", {"hf": -0.10}), ("hip adduction +0.10", {"ha": 0.10}), ("hip adduction -0.10", {"ha": -0.10}),
                  ("hip rotation +0.10", {"hr": 0.10}), ("hip rotation -0.10", {"hr": -0.10}), ("flexion +0.2 (b_sw_th 0.25 like)", {"hf": 0.2})]:
    t = tangents(**kw)
    print(f"{label:33s}                    " + "  ".join(f"{t[k]:7.4f}" for k in idx))
