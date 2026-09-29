"""Offline posture table for the prosthesis (MPL left arm) in myo_bimanual.

The MPL arm has position servos, so it needs joint angles, not contractions.
This solves inverse kinematics on the bimanual model (forward kinematics on a
private MjData; the environment is never stepped) for a grid of targets for
the MPL palm centre (the env's Rpalm_pos: the midpoint of the palm_thumb and
palm_pinky sites), holding the hand palm down with the fingers pointing
forward (-y), as it starts. Seven joints: shoulder fe / abad, humeral
rotation, elbow, wrist pronation / deviation / flexion.

Writes lib/robolab/skills/myo_bimanual_prosthesis.w: class
MyoBimanualProsthesis with the joint list, every servo's control range (the
controller turns an angle into the env's normalised action), the grid, the
table and a trilinear interpolator.

    .venv-myo/bin/python playground/tasks/myo_bimanual_ik.py [--npz out.npz]
"""

import argparse
import contextlib
import io
import os
import sys

import numpy as np
import mujoco
from scipy.optimize import minimize

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from myo_bridge import couple_joints  # noqa: E402

ARM = ["prosthesis/Lshoulder_fe", "prosthesis/Lshoulder_abad", "prosthesis/Lhumeral_rot", "prosthesis/Lelbow",
       "prosthesis/wrist_PRO", "prosthesis/wrist_UDEV", "prosthesis/wrist_FLEX"]
# handover region in front of the body, over to the goal pillar (x 0.4 +- 0.1)
XS = np.linspace(-0.2, 0.6, 9)
YS = np.linspace(-0.46, -0.06, 6)
ZS = np.linspace(1.1, 1.46, 7)
OUT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "lib", "robolab", "skills", "myo_bimanual_prosthesis.w")


def fmt(v):
    return f"~{v:.5f}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--npz")
    a = ap.parse_args()
    from myosuite.utils import gym
    env = gym.make("myoChallengeBimanual-v0")
    u = env.unwrapped
    u.seed(0)
    env.reset(seed=0)
    m = u.mj_model
    q0 = u.mj_data.qpos.copy()
    d = mujoco.MjData(m)
    jid = [m.joint(n).id for n in ARM]
    adr = [m.jnt_qposadr[j] for j in jid]
    lo = np.array([m.jnt_range[j][0] for j in jid])
    hi = np.array([m.jnt_range[j][1] for j in jid])
    span = hi - lo
    blo, bhi = lo + 0.05 * span, hi - 0.05 * span
    s_th, s_pk, s_bk = (m.site(n).id for n in ("prosthesis/palm_thumb", "prosthesis/palm_pinky", "prosthesis/palm_back"))
    s_mid = m.site("prosthesis/middle_proximal").id

    def fk(x):
        d.qpos[:] = q0
        d.qpos[adr] = x
        couple_joints(m, d.qpos)
        mujoco.mj_kinematics(m, d)
        c = 0.5 * (d.site_xpos[s_th] + d.site_xpos[s_pk])
        up = d.site_xpos[s_bk] - c              # palm back: +z when palm down
        fwd = d.site_xpos[s_mid] - c            # toward the fingers: -y
        return c, up / (np.linalg.norm(up) + 1e-9), fwd / (np.linalg.norm(fwd) + 1e-9)

    x_start = np.clip(q0[adr], blo, bhi)
    _, up0, fwd0 = fk(x_start)
    up_star = np.array([0.0, 0.0, 1.0])
    fwd_star = np.array([0.0, -1.0, 0.0])

    def cost(x, target):
        c, up, fwd = fk(x)
        k = 1e4 * np.sum((c - target) ** 2)
        k += 2.0 * np.sum((up - up_star) ** 2) + 1.0 * np.sum((fwd - fwd_star) ** 2)
        k += 0.01 * np.sum((x - x_start) ** 2)
        return k

    table = np.zeros((len(XS), len(YS), len(ZS), len(ARM)))
    err = np.zeros((len(XS), len(YS), len(ZS), 2))
    prev = x_start.copy()
    for i, xv in enumerate(XS):
        for j, yv in enumerate(YS):
            for k, zv in enumerate(ZS):
                target = np.array([xv, yv, zv])
                best = None
                for start in (prev, x_start):
                    r = minimize(cost, start, args=(target,), bounds=list(zip(blo, bhi)), method="L-BFGS-B")
                    if best is None or r.fun < best.fun:
                        best = r
                table[i, j, k] = best.x
                c, up, fwd = fk(best.x)
                err[i, j, k] = [np.linalg.norm(c - target), np.degrees(np.arccos(np.clip(up @ up_star, -1, 1)))]
                prev = best.x
    sys.stderr.write(f"MPL palm error: median {np.median(err[..., 0]) * 1000:.1f} mm, 90% "
                     f"{np.quantile(err[..., 0], 0.9) * 1000:.1f} mm; palm-down error median "
                     f"{np.median(err[..., 1]):.1f} deg, 90% {np.quantile(err[..., 1], 0.9):.1f} deg\n")
    if a.npz:
        np.savez(a.npz, table=table, err=err, xs=XS, ys=YS, zs=ZS)
    motors = [i for i in range(m.nu) if m.actuator_dyntype[i] != mujoco.mjtDyn.mjDYN_MUSCLE]
    names = [m.actuator(i).name for i in motors]
    ranges = [m.actuator_ctrlrange[i] for i in motors]
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        emit(table, names, ranges)
    open(OUT, "w").write(buf.getvalue())
    sys.stderr.write(f"wrote {OUT}\n")


def emit(table, names, ranges):
    nx, ny, nz, nj = table.shape
    print("# MyoBimanualProsthesis: posture table for the MPL prosthetic arm.")
    print("#")
    print("# Generated by playground/tasks/myo_bimanual_ik.py (inverse kinematics on the")
    print("# bimanual model, forward kinematics only): the seven MPL arm joints that put the")
    print("# palm centre (the env's Rpalm_pos) at each grid point, palm down, fingers")
    print("# forward. `servos` / `ranges` list every prosthesis servo and its control")
    print("# range, in the order of the env's action vector.")
    print()
    print("+ MyoBimanualProsthesis")
    print("  -> .joints")
    print("    [" + ", ".join(f'"{n}"' for n in ARM) + "]")
    print()
    print("  -> .servos")
    print("    [" + ", ".join(f'"{n}"' for n in names) + "]")
    print()
    print("  -> .ranges")
    print("    [" + ", ".join(f"{fmt(r[0])}, {fmt(r[1])}" for r in ranges) + "]")
    print()
    print("  -> .grid")
    print(f"    [{fmt(XS[0])}, {fmt(XS[-1])}, {nx}, {fmt(YS[0])}, {fmt(YS[-1])}, {ny}, {fmt(ZS[0])}, {fmt(ZS[-1])}, {nz}]")
    print()
    print("  -> .table")
    flat = table.reshape(-1)
    rows = [", ".join(fmt(v) for v in flat[i:i + nj]) for i in range(0, len(flat), nj)]
    print("    [" + ",\n     ".join(rows) + "]")
    print()
    print("  -> .at(x, y, z)")
    print("    g = grid")
    print("    tab = table")
    print("    fx = cell(x, g[0], g[1], g[2])")
    print("    fy = cell(y, g[3], g[4], g[5])")
    print("    fz = cell(z, g[6], g[7], g[8])")
    print("    ny = g[5]")
    print("    nz = g[8]")
    print("    out = [~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]")
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
    print("      base = ((ix * ny + iy) * nz + iz) * 7")
    print("      k = 0")
    print("      while k < 7")
    print("        out[k] += w * tab[base + k]")
    print("        k += 1")
    print("      c += 1")
    print("    out")
    print()
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
