"""Static inverse-dynamics feed-forward table for the myo_relocate arm (and
myo_bimanual's): for every posture of the IK posture table
(myo_relocate_ik.py, saved solve params/myo_ik/<profile>_solve.npz), the arm
muscle activations that hold that posture still against gravity and the
muscles' own passive forces.

Why: the controller's generic feed-forward (Controller#enable_feedforward)
splits the gravity torque over muscles by moment arm x peak force. That
ignores the force-length curve (a muscle far from its optimal length gives
much less than its peak force per unit activation) and every passive force
(stretched muscles pull whether activated or not, and on the myoArm they
load the shoulder and elbow). The reflexes then carry a steady error
c* - c = a / kp to make up the difference, which is where the arm's sag and
the palm's centimetres of offset come from.

For each posture q*: with MuJoCo at q*, zero velocity, the required
generalised force is tau = qfrc_bias - qfrc_passive - qfrc_actuator(act = 0)
(gravity, minus joint springs, minus every muscle's passive pull), and each
arm muscle's contribution per unit activation is its moment arm x its active
force at that length (actuator_force(act = 1) - actuator_force(act = 0)).
Both are folded onto the seven independent arm joints through the shoulder
girdle's joint-equality couplings (d dependent / d independent from the
coupling polynomial). The activations solve

    min |A a - tau|^2 + lam |a|^2,   0 <= a <= 1

(bounded least squares; lam keeps the solution the low-effort one where the
arm is redundant). The table is written as a Tungsten class indexed exactly
like the posture table (same grid, same `at` interpolation):

    .venv-myo/bin/python playground/tasks/myo_relocate_ff.py [--profile relocate|bimanual|relocate_v3|bimanual_v3]
"""

import argparse
import os
import sys

import numpy as np
import mujoco
from scipy.optimize import lsq_linear

HERE = os.path.dirname(os.path.abspath(__file__))
PLAY = os.path.dirname(HERE)
ROOT = os.path.dirname(PLAY)
sys.path.insert(0, PLAY)
sys.path.insert(0, HERE)
from myo_bridge import couple_joints  # noqa: E402
from myo_relocate_ik import JOINTS, PROFILES, arm_muscles, fmt  # noqa: E402

SKILLS = os.path.join(ROOT, "lib", "robolab", "skills")
OUTS = {"relocate": ("MyoRelocateFF", "myo_relocate_ff.w", "MyoRelocatePostures"),
        "bimanual": ("MyoBimanualFF", "myo_bimanual_ff.w", "MyoBimanualPostures"),
        "relocate_v3": ("MyoRelocateFFV3", "myo_relocate_ff_v3.w", "MyoRelocatePosturesV3"),
        "bimanual_v3": ("MyoBimanualFFV3", "myo_bimanual_ff_v3.w", "MyoBimanualPosturesV3"),
        "relocate_v5": ("MyoRelocateFFV5", "myo_relocate_ff_v5.w", "MyoRelocatePosturesV5")}


def coupling_fold(m):
    """dof -> [(dependent dof, polynomial coefficients c1..c4, independent qpos adr, qpos0)]"""
    out = {}
    for i in range(m.neq):
        if m.eq_type[i] == mujoco.mjtEq.mjEQ_JOINT and m.eq_active0[i] and m.eq_obj2id[i] >= 0:
            dep, ind = m.eq_obj1id[i], m.eq_obj2id[i]
            out.setdefault(m.jnt_dofadr[ind], []).append(
                (m.jnt_dofadr[dep], m.eq_data[i][:5].copy(), m.jnt_qposadr[ind], m.qpos0[m.jnt_qposadr[ind]]))
    return out


def fold(v, dofs, follow, qpos):
    """Generalised force v (nv, or nv x k) onto the independent dofs."""
    out = []
    for dof in dofs:
        row = np.array(v[dof], dtype=float)
        for dep, c, adr, q0 in follow.get(dof, []):
            x = qpos[adr] - q0
            k = c[1] + x * (2 * c[2] + x * (3 * c[3] + x * 4 * c[4]))
            row = row + k * v[dep]
            # a dependent that drives others in turn (one more level)
            for dep2, c2, adr2, q02 in follow.get(dep, []):
                x2 = qpos[adr2] - q02
                k2 = c2[1] + x2 * (2 * c2[2] + x2 * (3 * c2[3] + x2 * 4 * c2[4]))
                row = row + k * k2 * v[dep2]
        out.append(row)
    return np.array(out)


def solve(profile, lam):
    pr = PROFILES[profile]
    from myosuite.utils import gym
    env = gym.make(pr["env"])
    u = env.unwrapped
    u.seed(0)
    env.reset(seed=0)
    m = u.mj_model
    q0 = u.mj_data.qpos.copy()
    d = mujoco.MjData(m)
    adr = [m.jnt_qposadr[m.joint(n).id] for n in JOINTS]
    dofs = [m.jnt_dofadr[m.joint(n).id] for n in JOINTS]
    follow = coupling_fold(m)
    ids = arm_muscles(m)
    table = np.load(os.path.join(ROOT, "params", "myo_ik", f"{profile}_solve.npz"))["table"]
    acts = np.zeros(table.shape[:3] + (len(ids),))
    resid = np.zeros(table.shape[:3])
    need = np.zeros(table.shape[:3])
    moment = np.zeros((m.nu, m.nv))
    for idx in np.ndindex(*table.shape[:3]):
        d.qpos[:] = q0
        d.qpos[adr] = table[idx]
        couple_joints(m, d.qpos)
        d.qvel[:] = 0
        d.act[:] = 0
        mujoco.mj_forward(m, d)
        f0 = d.actuator_force.copy()
        tau = d.qfrc_bias - d.qfrc_passive - d.qfrc_actuator
        mujoco.mju_sparse2dense(moment, d.actuator_moment, d.moment_rownnz, d.moment_rowadr, d.moment_colind)
        d.act[:] = 1.0
        mujoco.mj_fwdActuation(m, d)
        f1 = d.actuator_force.copy()
        per = moment[ids].T * (f1 - f0)[ids]          # nv x n_arm: generalised force per unit activation
        A = fold(per, dofs, follow, d.qpos)
        b = fold(tau, dofs, follow, d.qpos)
        scale = 1.0 / np.maximum(np.abs(A).max(axis=1), 1e-6)   # per-joint rows on a common scale
        As, bs = A * scale[:, None], b * scale
        n = len(ids)
        M = np.vstack([As, np.sqrt(lam) * np.eye(n)])
        r = lsq_linear(M, np.concatenate([bs, np.zeros(n)]), bounds=(0.0, 1.0))
        acts[idx] = r.x
        resid[idx] = np.linalg.norm(A @ r.x - b)
        need[idx] = np.linalg.norm(b)
    names = [m.actuator(i).name for i in ids]
    return acts, names, resid, need


def emit(f, cls, posture_cls, acts, names, lam, resid, need):
    nm = len(names)
    w = f.write
    w(f"# {cls}: static inverse-dynamics feed-forward for the arm muscles at each\n")
    w(f"# posture of {posture_cls} (same grid, same `at`).\n#\n")
    w("# Generated by playground/tasks/myo_relocate_ff.py: at every grid posture, the\n")
    w("# activations (0..1) of the arm muscles that hold it still against gravity and\n")
    w("# the muscles' passive forces (bounded least squares, activation penalty\n")
    w(f"# {lam:g}); residual torque median {np.median(resid):.3f} N m of {np.median(need):.3f} N m needed.\n\n")
    w(f"+ {cls}\n")
    w("  -> .muscles\n")
    w("    [" + ", ".join(f'"{n}"' for n in names) + "]\n\n")
    w(f"  # acts[((ix * ny + iy) * nz + iz) * {nm} + muscle]; interpolate with {posture_cls}.at\n")
    w("  -> .acts\n")
    flat = acts.reshape(-1)
    rows = [", ".join(fmt(v) for v in flat[i:i + nm]) for i in range(0, len(flat), nm)]
    w("    [" + ",\n     ".join(rows) + "]\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", default="relocate", choices=sorted(OUTS))
    ap.add_argument("--lam", type=float, default=1e-3)
    a = ap.parse_args()
    acts, names, resid, need = solve(a.profile, a.lam)
    cls, out, pcls = OUTS[a.profile]
    path = os.path.join(SKILLS, out)
    with open(path, "w") as f:
        emit(f, cls, pcls, acts, names, a.lam, resid, need)
    sys.stderr.write(f"wrote {path}: {len(names)} muscles; mean activation {acts.mean():.3f} "
                     f"(max {acts.max():.2f}); residual torque median {np.median(resid):.3f} / 90% "
                     f"{np.quantile(resid, 0.9):.3f} N m, needed median {np.median(need):.3f} N m\n")


if __name__ == "__main__":
    main()
