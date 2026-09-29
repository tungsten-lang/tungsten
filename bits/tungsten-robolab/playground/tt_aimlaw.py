"""Python port of the skill's aim law (MyoTTSkill#landing, choose_target, aim_normal, aim_w, aim_residual), for offline studies.

The skill's pad normals point toward the player (x > 0). plan = [t, y, z, vx, vy, vz] is the ball's state where it crosses
the pad's plane x = xp. Parameters as in the params files (defaults of the skill).
"""
import numpy as np

DEFAULTS = dict(e_pad=1.0, mu_t=0.0, kick_z=0.0, nz_bias=-0.07, land_x=-0.85, land_y=0.1, land_pull=0.0,
                box_x0=-1.2, box_x1=-0.7, box_y0=-0.5, box_y1=0.6, k_vp=0.6, d_push=-0.1, t_push=0.139)


def clamp(x, lo, hi):
    return lo if x < lo else hi if x > hi else x


def landing(plan, n, xp, vp, P):
    u = np.array(plan[3:6]) - vp
    un = u @ n
    a = 1.0 - P["mu_t"]
    b = 1.0 + P["e_pad"] - P["mu_t"]
    o = vp + a * u - b * un * n + np.array([0.0, 0.0, P["kick_z"]])
    if o[0] > -0.5:
        return [9.0, plan[1]]
    h = plan[2] - 0.815
    t = (o[2] + np.sqrt(clamp(o[2] ** 2 + 2 * 9.81 * h, 0.0, 1000.0))) / 9.81
    return [xp + o[0] * t, plan[1] + o[1] * t]


def choose_target(plan, n, xp, vp, P, bh_box_dx=0.0):
    lp = landing(plan, n, xp, vp, P)
    x = lp[0] + (P["land_x"] - lp[0]) * P["land_pull"]
    y = lp[1] + (P["land_y"] - lp[1]) * P["land_pull"]
    tx = clamp(x, P["box_x0"] + bh_box_dx, P["box_x1"] + bh_box_dx)
    ty = clamp(y, P["box_y0"], P["box_y1"])
    return tx, ty


def aim_w(plan, v, s, tx, ty, xp, vp, P):
    dx = tx - xp
    dy = ty - plan[1]
    dd = np.hypot(dx, dy)
    dz = 0.815 - plan[2]
    g = 9.81
    disc = s ** 4 - g * (g * dd * dd + 2.0 * dz * s * s)
    th = 0.6
    if disc > 0.0:
        th = np.arctan((s * s - np.sqrt(disc)) / (g * dd))
    h = s * np.cos(th)
    k = 1.0 - P["mu_t"]
    return np.array([k * (v[0] - vp[0]) + vp[0] - h * dx / dd, k * (v[1] - vp[1]) + vp[1] - h * dy / dd,
                     k * (v[2] - vp[2]) + vp[2] + P["kick_z"] - s * np.sin(th)])


def aim_residual(plan, v, s, tx, ty, xp, vp, P):
    w = aim_w(plan, v, s, tx, ty, xp, vp, P)
    u = np.array(v) - vp
    return w @ w - (1.0 + P["e_pad"] - P["mu_t"]) * (u @ w)


def aim_normal(plan, tx, ty, xp, vp, P, raw=False):
    v = np.array(plan[3:6])
    s0 = np.linalg.norm(v) * P["e_pad"] + 2.0 * P["k_vp"] * 1.875 * P["d_push"] / P["t_push"]
    s1 = s0 * 0.9
    f0 = aim_residual(plan, v, s0, tx, ty, xp, vp, P)
    f1 = aim_residual(plan, v, s1, tx, ty, xp, vp, P)
    it = 0
    while it < 6 and abs(f1 - f0) > 1e-6:
        s2 = clamp(s1 - f1 * (s1 - s0) / (f1 - f0), 1.5, 15.0)
        s0, f0, s1 = s1, f1, s2
        f1 = aim_residual(plan, v, s1, tx, ty, xp, vp, P)
        it += 1
    w = aim_w(plan, v, s1, tx, ty, xp, vp, P)
    nn = np.linalg.norm(w)
    nz = w[2] / nn
    if not raw:
        nz += P["nz_bias"]
    nn2 = np.sqrt(w[0] ** 2 / nn ** 2 + w[1] ** 2 / nn ** 2 + nz ** 2)
    return np.array([w[0] / nn / nn2, w[1] / nn / nn2, nz / nn2]), s1
