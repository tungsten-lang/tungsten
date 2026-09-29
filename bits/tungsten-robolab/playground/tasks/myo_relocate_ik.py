"""Offline posture table for the myo_relocate skill (and myo_bimanual's arm).

Solves inverse kinematics on the myoArm model (forward kinematics only: a
private MjData, the environment is never touched) for a grid of palm-site
targets covering the relocate workspace, holding the hand in the grasp
orientation designed for the pinch (palm pronated, facing down). Each grid
point gets the seven arm joints [elv_angle, shoulder_elv, shoulder_rot,
elbow_flexion, pro_sup, deviation, flexion]; the shoulder-girdle joints
follow shoulder_elv / elv_angle through the model's equality couplings.

For every grid posture it also records the true contraction of each arm
muscle (the 31 muscles of the shoulder, elbow, forearm and wrist that cross
no finger joint), from the model's muscle lengths: the controller's additive
length model (body.w Geometry) is exact only near its reference posture and
is off by 0.1-0.5 of a length range for the deltoids, biceps and supinator
across this workspace. The result is written as a Tungsten class
(MyoRelocatePostures) holding the grid, both tables and a trilinear
interpolator, so the skill turns any palm target into a midpoint posture and
a midpoint contraction vector:

    .venv-myo/bin/python playground/tasks/myo_relocate_ik.py [--npz solve.npz] [--from-npz solve.npz]

writes lib/robolab/skills/myo_relocate_postures.w (MyoSuite prints a banner on
stdout, so the table is written to the file, never to stdout).
"""

import os
import sys

import numpy as np
import mujoco
from scipy.optimize import minimize

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from myo_bridge import couple_joints  # noqa: E402

JOINTS = ["elv_angle", "shoulder_elv", "shoulder_rot", "elbow_flexion", "pro_sup", "deviation", "flexion"]
FINGER_MUSCLES = ("FDS", "FDP", "EDC", "EDM", "EIP", "EPL", "EPB", "FPL", "APL", "OP", "RI", "LU_", "UI_")
# grid of palm-site targets (m): object ranges of P2 and P2eval, the box, and heights up to the carry
XS = np.linspace(-0.46, 0.06, 9)
YS = np.linspace(-0.46, -0.06, 7)
ZS = np.linspace(0.94, 1.30, 10)  # 4 cm levels: the posture changes fast near the table
# designed grasp wrist (see myo_relocate.w): pronated, flexed, ulnar-deviated
GRASP_WRIST = {"pro_sup": 1.57, "flexion": 0.397, "deviation": -0.17}


def rotvec(R):
    """Rotation vector of a 3x3 rotation matrix."""
    c = np.clip((np.trace(R) - 1) / 2, -1.0, 1.0)
    ang = np.arccos(c)
    if ang < 1e-8:
        return np.zeros(3)
    w = np.array([R[2, 1] - R[1, 2], R[0, 2] - R[2, 0], R[1, 0] - R[0, 1]]) / (2 * np.sin(ang))
    return w * ang


SKILLS = os.path.join(os.path.dirname(os.path.dirname(HERE)), "lib", "robolab", "skills")
OUT = os.path.join(SKILLS, "myo_relocate_postures.w")
CLASS = "MyoRelocatePostures"
ENV = "myoChallengeRelocateP2-v0"
# profiles: the environment, grid and output for each skill that uses a table
PROFILES = {
    "relocate": dict(env="myoChallengeRelocateP2-v0", cls="MyoRelocatePostures", out="myo_relocate_postures.w",
                     xs=(-0.46, 0.06, 9), ys=(-0.46, -0.06, 7), zs=(0.94, 1.30, 10)),
    # bimanual: the start pillar (x -0.4 +-0.055, top at z 1.09) to the handover
    # region in front of the body, carry heights up to 1.4 m
    "bimanual": dict(env="myoChallengeBimanual-v0", cls="MyoBimanualPostures", out="myo_bimanual_postures.w",
                     xs=(-0.56, 0.08, 9), ys=(-0.46, -0.06, 7), zs=(1.10, 1.42, 9)),
    # round 3: the forearm held out of strong pronation. Past pro_sup ~1 the
    # pronators (PT, PQ) sit so short that all of them together give under
    # 1 N m (5-7 N m at pro_sup 0), while the biceps supinates with 4-7 N m
    # per unit activation as it flexes the elbow, so the pronated table's
    # hand rolls over whenever the arm works. Pronation above `ps_max` is
    # penalised and the palm is turned down by the shoulder instead (the full
    # orientation term, anchored to the pronated start, is dropped).
    "relocate_v3": dict(env="myoChallengeRelocateP2-v0", cls="MyoRelocatePosturesV3", out="myo_relocate_postures_v3.w",
                        xs=(-0.46, 0.06, 9), ys=(-0.46, -0.06, 7), zs=(0.94, 1.30, 10), ps_max=0.5, w_orient=0.0),
    "bimanual_v3": dict(env="myoChallengeBimanual-v0", cls="MyoBimanualPosturesV3", out="myo_bimanual_postures_v3.w",
                        xs=(-0.56, 0.08, 9), ys=(-0.46, -0.06, 7), zs=(1.10, 1.42, 9), ps_max=0.5, w_orient=0.0),
    # round 5: postures near the arm's start. Every episode starts with the
    # palm 9 cm above the table's middle (elv 0.21, shoulder_elv 0.20, elbow
    # 1.50, pro_sup 1.32, flexion -0.26), within ~10 cm of every object, but
    # the base table puts the palm there with shoulder_elv 0.71 and elbow
    # 1.18: each reach reconfigures the arm, and the shoulder's slow response
    # to it swings the pinch 10-20 cm off its path. `rest_start` anchors the
    # regularisation at the start posture itself (wrist included; the grasp
    # direction is still the designed one), `w_rest` weights it, and
    # `w_smooth` pulls every grid posture toward its already-solved neighbours
    # (x, y and z one step back), so the table changes slowly everywhere.
    "relocate_v5": dict(env="myoChallengeRelocateP2-v0", cls="MyoRelocatePosturesV5", out="myo_relocate_postures_v5.w",
                        xs=(-0.46, 0.06, 9), ys=(-0.46, -0.06, 7), zs=(0.94, 1.30, 10),
                        rest_start=True, w_rest=(1.0, 0.3, 0.3, 0.3, 0.1, 0.1, 0.1), w_smooth=1.0),
}


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--npz", help="also save the solve (table, errors) here")
    ap.add_argument("--from-npz", help="re-emit the Tungsten table from a saved solve")
    ap.add_argument("--profile", default="relocate", choices=sorted(PROFILES))
    a = ap.parse_args()
    global XS, YS, ZS, OUT, CLASS, ENV
    pr = PROFILES[a.profile]
    XS, YS, ZS = (np.linspace(*pr[k]) for k in ("xs", "ys", "zs"))
    OUT, CLASS, ENV = os.path.join(SKILLS, pr["out"]), pr["cls"], pr["env"]
    from myosuite.utils import gym
    env = gym.make(ENV)
    u = env.unwrapped
    u.seed(0)
    env.reset(seed=0)
    m = u.mj_model
    q0 = u.mj_data.qpos.copy()
    d = mujoco.MjData(m)
    adr = [m.jnt_qposadr[m.joint(n).id] for n in JOINTS]
    lo = np.array([m.jnt_range[m.joint(n).id][0] for n in JOINTS])
    hi = np.array([m.jnt_range[m.joint(n).id][1] for n in JOINTS])
    palm = m.site("S_grasp").id

    def fk(x):
        d.qpos[:] = q0
        d.qpos[adr] = x
        couple_joints(m, d.qpos)
        mujoco.mj_kinematics(m, d)
        return d.site_xpos[palm].copy(), d.site_xmat[palm].reshape(3, 3).copy()

    x_start = q0[adr].copy()
    for n, v in GRASP_WRIST.items():
        x_start[JOINTS.index(n)] = v
    # hard bounds kept clear of the joint stops (the reflexes cannot hold a
    # posture pressed against a stop), and the start posture inside them
    span = hi - lo
    blo, bhi = lo + np.minimum(0.1, 0.1 * span), hi - np.minimum(0.1, 0.1 * span)
    x_start = np.clip(x_start, blo, bhi)
    p_start, R_star = fk(x_start)
    # grasp direction: palm site -> pinch point (designed offset), in the palm frame
    g_local = R_star.T @ np.array([0.02, -0.01, -0.042])
    g_local /= np.linalg.norm(g_local)
    g_star = R_star @ g_local
    ps_max = pr.get("ps_max")
    w_orient = pr.get("w_orient", 0.3)
    i_ps = JOINTS.index("pro_sup")
    if ps_max is not None:
        # the same hand-fixed grasp direction (from the pronated design), held
        # down with the forearm out of strong pronation
        x_start[i_ps] = min(x_start[i_ps], ps_max)
    rest = x_start.copy()
    if pr.get("rest_start"):
        rest = np.clip(q0[adr].copy(), blo, bhi)
    for n, v in pr.get("rest", {}).items():
        rest[JOINTS.index(n)] = v
    # regularisation toward the start posture per joint: the plane of elevation
    # moves the palm little while the upper arm hangs, so it is held hardest
    w_rest = np.array(pr.get("w_rest", (1.0, 0.03, 0.05, 0.02, 0.1, 0.1, 0.1)))
    w_smooth = pr.get("w_smooth", 0.0)
    nbrs = []  # already-solved neighbour postures of the grid point being solved

    def cost(x, target):
        p, R = fk(x)
        c = 1e4 * np.sum((p - target) ** 2)
        c += 5.0 * np.sum((R @ g_local - g_star) ** 2)        # grasp direction held (2 dof)
        c += w_orient * np.sum(rotvec(R_star.T @ R) ** 2)     # full orientation, weakly
        c += np.sum(w_rest * (x - rest) ** 2)
        if ps_max is not None:                                  # keep the pronators strong
            c += 200.0 * max(0.0, x[i_ps] - ps_max) ** 2
        for nb in nbrs:
            c += w_smooth * np.sum((x - nb) ** 2)
        return c

    if a.from_npz:
        table = np.load(a.from_npz)["table"]
        write(table, contractions(m, q0, adr, table))
        return
    table = np.zeros((len(XS), len(YS), len(ZS), len(JOINTS)))
    err = np.zeros((len(XS), len(YS), len(ZS), 2))
    prev = x_start.copy()
    for i, x in enumerate(XS):
        for j, y in enumerate(YS):
            for k, z in enumerate(ZS):
                target = np.array([x, y, z])
                if w_smooth > 0.0:
                    nbrs[:] = [table[i - 1, j, k]] if i else []
                    nbrs.extend([table[i, j - 1, k]] if j else [])
                    nbrs.extend([table[i, j, k - 1]] if k else [])
                best = None
                for start in (prev, x_start, table[i - 1, j, k] if i else x_start):
                    r = minimize(cost, start, args=(target,), bounds=list(zip(blo, bhi)), method="L-BFGS-B",
                                 options={"maxiter": 400})
                    if best is None or r.fun < best.fun:
                        best = r
                table[i, j, k] = best.x
                p, R = fk(best.x)
                err[i, j, k] = [np.linalg.norm(p - target), np.arccos(np.clip((R @ g_local) @ g_star, -1, 1))]
                prev = best.x
    sys.stderr.write(f"position error: median {np.median(err[..., 0]) * 1000:.1f} mm, "
                     f"90% {np.quantile(err[..., 0], 0.9) * 1000:.1f} mm, max {err[..., 0].max() * 1000:.1f} mm; "
                     f"grasp-direction error median {np.degrees(np.median(err[..., 1])):.1f} deg, "
                     f"90% {np.degrees(np.quantile(err[..., 1], 0.9)):.1f} deg\n")
    if a.npz:
        np.savez(a.npz, table=table, err=err, xs=XS, ys=YS, zs=ZS)
    write(table, contractions(m, q0, adr, table))


def arm_muscles(m):
    ids = [i for i in range(m.nu) if m.actuator_dyntype[i] == mujoco.mjtDyn.mjDYN_MUSCLE]
    return [i for i in ids if not m.actuator(i).name.startswith(FINGER_MUSCLES)]


def contractions(m, q0, adr, table):
    """True contraction (Lmax - L) / (Lmax - Lmin) of every arm muscle at
    every grid posture (fingers at the reference posture; arm muscles cross
    no finger joint)."""
    ids = arm_muscles(m)
    lr = m.actuator_lengthrange[ids]
    d = mujoco.MjData(m)
    out = np.zeros(table.shape[:3] + (len(ids),))
    for idx in np.ndindex(*table.shape[:3]):
        d.qpos[:] = q0
        d.qpos[adr] = table[idx]
        couple_joints(m, d.qpos)
        mujoco.mj_forward(m, d)
        L = d.actuator_length[ids]
        out[idx] = (lr[:, 1] - L) / (lr[:, 1] - lr[:, 0])
    return out, [m.actuator(i).name for i in ids]


def write(table, contr):
    import contextlib
    import io
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        emit(table, *contr)
    with open(OUT, "w") as f:
        f.write(buf.getvalue())
    sys.stderr.write(f"wrote {OUT}\n")


def fmt(v):
    s = f"{v:.5f}"
    return "~" + s if not s.startswith("-") else "~" + s


def emit(table, contr, names):
    nx, ny, nz, nj = table.shape
    nm = len(names)
    print(f"# {CLASS}: midpoint arm postures and contraction vectors for")
    print("# palm-site targets.")
    print("#")
    print("# Generated by playground/tasks/myo_relocate_ik.py (inverse kinematics on the")
    print("# myoArm model, forward kinematics only): for each point of a grid over the")
    print(f"# {ENV} workspace, the seven arm joints that put the palm site there with the")
    print("# grasp direction pointing down, and the true contraction of each of the arm")
    print("# muscles (shoulder, elbow, forearm, wrist) at that posture. `at` interpolates")
    print("# either table trilinearly and clamps to the grid.")
    print()
    print(f"+ {CLASS}")
    print("  -> .joints")
    print("    [" + ", ".join(f'"{n}"' for n in JOINTS) + "]")
    print()
    print("  -> .muscles")
    print("    [" + ", ".join(f'"{n}"' for n in names) + "]")
    print()
    print("  -> .grid")
    print(f"    [{fmt(XS[0])}, {fmt(XS[-1])}, {nx}, {fmt(YS[0])}, {fmt(YS[-1])}, {ny}, {fmt(ZS[0])}, {fmt(ZS[-1])}, {nz}]")
    print()
    print("  # table[((ix * ny + iy) * nz + iz) * 7 + joint] (rad)")
    print("  -> .table")
    flat = table.reshape(-1)
    rows = [", ".join(fmt(v) for v in flat[i:i + 7]) for i in range(0, len(flat), 7)]
    print("    [" + ",\n     ".join(rows) + "]")
    print()
    print(f"  # contractions[((ix * ny + iy) * nz + iz) * {nm} + muscle]")
    print("  -> .contractions")
    flat = contr.reshape(-1)
    rows = [", ".join(fmt(v) for v in flat[i:i + nm]) for i in range(0, len(flat), nm)]
    print("    [" + ",\n     ".join(rows) + "]")
    print()
    print("  # `width` values for palm target (x, y, z), trilinear in the grid.")
    print("  -> .at(tab, width, x, y, z)")
    print("    g = grid")
    print("    fx = cell(x, g[0], g[1], g[2])")
    print("    fy = cell(y, g[3], g[4], g[5])")
    print("    fz = cell(z, g[6], g[7], g[8])")
    print("    ny = g[5]")
    print("    nz = g[8]")
    print("    out = (0...width).map ->(i) ~0.0")
    print("    c = 0")
    print("    while c < 8")
    print("      ix = fx[0]")
    print("      wx = ~1.0 - fx[1]")
    print("      if c % 2 == 1")
    print("        ix = fx[0] + 1")
    print("        wx = fx[1]")
    print("      iy = fy[0]")
    print("      wy = ~1.0 - fy[1]")
    print("      if (c / 2) % 2 == 1")
    print("        iy = fy[0] + 1")
    print("        wy = fy[1]")
    print("      iz = fz[0]")
    print("      wz = ~1.0 - fz[1]")
    print("      if c / 4 == 1")
    print("        iz = fz[0] + 1")
    print("        wz = fz[1]")
    print("      w = wx * wy * wz")
    print("      base = ((ix * ny + iy) * nz + iz) * width")
    print("      k = 0")
    print("      while k < width")
    print("        out[k] += w * tab[base + k]")
    print("        k += 1")
    print("      c += 1")
    print("    out")
    print()
    print("  # [lower index, fraction] of v in a grid of n points over [lo, hi], clamped.")
    print("  -> .cell(v, lo, hi, n)")
    print("    u = (v - lo) / (hi - lo) * (n - 1)")
    print("    return [0, ~0.0] if u <= ~0.0")
    print("    return [n - 2, ~1.0] if u >= n - 1")
    print("    i = 0")
    print("    while i + 1 < n - 1 && i + 1 <= u")
    print("      i += 1")
    print("    [i, u - i]")


if __name__ == "__main__":
    main()
