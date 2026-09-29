"""Is there a precursor of the blow-up? Bit-exact replay of the last N control steps before it, every substep: the candidate indicators of the task text
(contact count, constraint count, solver iterations and its final gradient, largest constraint force, the swing-shank / stance-thigh contact force,
number of active joint limits, largest |qacc|, muscle forces) and their largest single-substep jump, against the jump at the failing substep.
usage: precursor_scan.py DIR [seconds=3]"""
import sys
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/blowup")
import numpy as np, mujoco, replaylib

D = sys.argv[1]
secs = float(sys.argv[2]) if len(sys.argv) > 2 else 3.0
m, ring = replaylib.load(D)
spec = int(ring["spec"])
T = np.array(ring["t"])
k0 = max(0, len(T) - 1 - int(secs * 100))
catcher = replaylib.WarnCatcher()
mujoco.set_mju_user_warning(catcher)
g_tib, g_fem = m.geom("r_tibia1_col").id, m.geom("l_femur2_col").id
LIM = int(mujoco.mjtConstraint.mjCNSTR_LIMIT_JOINT)
names = ["ncon", "nefc", "niter", "max|efc_force|", "leg contact N", "joint limits active", "max|qacc|", "max|actuator_force|", "sum|qfrc_constraint|", "max|ten_length-ref|"]
rec = []
d = replaylib.data_at(m, ring, k0)
f6 = np.zeros(6)
rows_t = []


def sample(d):
    leg = 0.0
    for i in range(d.ncon):
        c = d.contact[i]
        if {c.geom1, c.geom2} == {g_tib, g_fem}:
            mujoco.mj_contactForce(m, d, i, f6)
            leg += abs(f6[0])
    nlim = int((d.efc_type[:d.nefc] == LIM).sum()) if d.nefc else 0
    return [d.ncon, d.nefc, int(d.solver_niter[0]), float(np.abs(d.efc_force[:d.nefc]).max()) if d.nefc else 0.0, leg, nlim,
            float(np.abs(d.qacc).max()), float(np.abs(d.actuator_force).max()), float(np.abs(d.qfrc_constraint).sum()), float(np.abs(d.ten_length).max())]


for i in range(k0 + 1, len(T) + 1):
    ctrl = ring["ctrl_fail"] if i == len(T) else replaylib.ctrl_of(m, ring, i)
    d.ctrl[:] = ctrl
    for s in range(10):
        n0 = len(catcher.events)
        t0 = float(d.time)
        mujoco.mj_step(m, d)
        if len(catcher.events) > n0:
            fail_t = t0
            break
        rec.append(sample(d)); rows_t.append(t0)
    else:
        continue
    break
R = np.array(rec)
print(f"{len(R)} substeps replayed exactly before the warning at t = {fail_t:.3f} s (window {rows_t[0]:.2f} .. {rows_t[-1]:.3f} s)")
print(f"{'indicator':24s} {'min':>12s} {'max':>12s} {'last 3 substeps':>40s} {'largest jump in window':>24s} {'jump into the last substep':>28s}")
for j, nm in enumerate(names):
    x = R[:, j]
    dx = np.abs(np.diff(x))
    print(f"{nm:24s} {x.min():12.5g} {x.max():12.5g} {str(np.round(x[-3:], 4)):>40s} {dx[:-1].max():24.5g} {dx[-1]:28.5g}")
