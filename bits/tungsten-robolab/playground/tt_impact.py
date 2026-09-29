"""Offline model of the table-tennis return (round 10): impact, flight, outcome.

Everything here works on the per-episode metrics that tasks/myo_tt.py records (`tt_eval.py` output):
the ball's velocity just before contact (`ball_in_exact`), the pad's normal and world velocity at
contact, the ball's position when it leaves the pad, its exit velocity (`ball_out_exact`) and where the
return first touched something (`landed`, `land_xy`). The environment's geometry (MuJoCo model):

  opponent half  x in [-1.37, 0], y in [-0.72, 0.80], top z 0.796   (ball centre 0.816 on it)
  net            x = 0 (half thickness 0.005), y in [-0.8725, 0.9525], z up to 0.9475
  own half       x in [0, 1.37], same y, same top
  pad            radius 0.093 (disc), paddle mass 0.10-0.15 kg, ball 2.7 g, radius 0.02

`impact(v_in, vp, n, e, mu)` is the controller's aim-law impact model (a nearly elastic, grippy wall).
`flight(p, v)` integrates gravity only (the challenge has no air) until the ball first touches the
opponent half, the net, our half or the floor, and returns that event.
"""

import numpy as np

G = 9.81
R_BALL = 0.02
Z_TOP = 0.796
Z_C = Z_TOP + R_BALL          # ball centre on a table top
NET_TOP = 0.9475
Y_LO, Y_HI = -0.72, 0.80      # table width (centre 0.04, half 0.76)
X_FAR = -1.37


def impact(v_in, vp, n, e=1.0, mu=0.0, kick=0.0):
    """Ball velocity after the pad: v_out = vp + (1-mu) u - (1+e-mu)(u.n) n + kick ez, u = v - vp."""
    v_in, vp, n = np.asarray(v_in, float), np.asarray(vp, float), np.asarray(n, float)
    n = n / np.linalg.norm(n, axis=-1, keepdims=True)
    u = v_in - vp
    un = np.sum(u * n, axis=-1, keepdims=True)
    return vp + (1 - mu) * u - (1 + e - mu) * un * n + np.array([0.0, 0.0, kick])


def flight(p, v, dt=0.002, t_max=2.5):
    """First contact of a ballistic ball with the table halves, the net or the floor.
    Returns (label, x, y, t): label in {"opp", "own", "net", "ground", "air"}."""
    p = np.array(p, float)
    v = np.array(v, float)
    t = 0.0
    while t < t_max:
        pn = p + v * dt - 0.5 * np.array([0, 0, G]) * dt * dt
        vn = v + np.array([0, 0, -G]) * dt
        # net plane crossing
        if (p[0] > 0.0 + 0.005 + R_BALL) != (pn[0] > 0.0 + 0.005 + R_BALL) or (p[0] < -0.005 - R_BALL) != (pn[0] < -0.005 - R_BALL):
            f = (0.0 - p[0]) / (pn[0] - p[0]) if pn[0] != p[0] else 0.5
            f = min(max(f, 0.0), 1.0)
            yc = p[1] + f * (pn[1] - p[1])
            zc = p[2] + f * (pn[2] - p[2])
            if -0.8725 - R_BALL <= yc <= 0.9525 + R_BALL and 0.6425 - R_BALL <= zc <= NET_TOP + R_BALL:
                return "net", 0.0, yc, t + f * dt
        # table top crossing (ball centre reaches Z_C going down)
        if p[2] > Z_C >= pn[2] and vn[2] < 0:
            f = (p[2] - Z_C) / (p[2] - pn[2])
            xc = p[0] + f * (pn[0] - p[0])
            yc = p[1] + f * (pn[1] - p[1])
            if Y_LO - R_BALL <= yc <= Y_HI + R_BALL:
                if X_FAR - R_BALL <= xc <= 0.0:
                    return "opp", xc, yc, t + f * dt
                if 0.0 < xc <= 1.37 + R_BALL:
                    return "own", xc, yc, t + f * dt
        if pn[2] < 0.05:
            return "ground", pn[0], pn[1], t
        p, v, t = pn, vn, t + dt
    return "air", p[0], p[1], t


def flight_batch(P, V, **kw):
    return [flight(p, v, **kw) for p, v in zip(P, V)]


def normal_from_angles(pitch, yaw):
    """Unit normal pointing at the ball (+x): pitch up +, yaw toward +y."""
    cp, sp = np.cos(pitch), np.sin(pitch)
    return np.array([cp * np.cos(yaw), cp * np.sin(yaw), sp])


def angles_from_normal(n):
    n = np.asarray(n, float)
    n = n / np.linalg.norm(n, axis=-1, keepdims=True)
    return np.arcsin(np.clip(n[..., 2], -1, 1)), np.arctan2(n[..., 1], n[..., 0])


def landing_ok(p0, v, y_margin=0.0, z_net=NET_TOP + R_BALL, x_margin=0.0):
    """Vectorised outcome of a ballistic ball from p0 (3,) with velocities v (..., 3): True where its
    first touch is the opponent's half (over the net, within the table). Ignores the net's y extent
    (the net spans the table) and bounces."""
    v = np.asarray(v, float)
    vx, vy, vz = v[..., 0], v[..., 1], v[..., 2]
    x0, y0, z0 = p0
    with np.errstate(divide="ignore", invalid="ignore"):
        t1 = -x0 / vx
        zn = z0 + vz * t1 - 0.5 * G * t1 * t1
        disc = vz * vz + 2 * G * (z0 - Z_C)
        t2 = (vz + np.sqrt(np.maximum(disc, 0.0))) / G
        xl = x0 + vx * t2
        yl = y0 + vy * t2
        ok = (vx < -0.3) & (t1 > 0) & (zn > z_net) & (disc > 0) & (xl <= -x_margin) & (xl >= X_FAR + x_margin) \
            & (yl >= Y_LO + y_margin) & (yl <= Y_HI - y_margin)
    return ok


def normals_grid(pitch_deg, yaw_deg):
    """Unit pad axes (pointing +x) on a grid: returns (P, Y, 3)."""
    P, Y = np.meshgrid(np.radians(pitch_deg), np.radians(yaw_deg), indexing="ij")
    return np.stack([np.cos(P) * np.cos(Y), np.cos(P) * np.sin(Y), np.sin(P)], axis=-1)


def margin(p0, v):
    """Slack (m) of a return leaving p0 with velocity v: the smallest of net clearance (ball centre above the net top
    plus its radius), distance to the far edge, to the net line (landing on the opponent's half), and to the side
    lines. Positive = the ball lands on the opponent's half (the flight model reproduced the environment's `solved`
    for every hit checked)."""
    x0, y0, z0 = p0
    vx, vy, vz = v
    if vx >= -0.3:
        return -1.0
    t1 = -x0 / vx
    zn = z0 + vz * t1 - 0.5 * G * t1 * t1
    disc = vz * vz + 2 * G * (z0 - Z_C)
    if disc <= 0:
        return -1.0
    t2 = (vz + np.sqrt(disc)) / G
    xl = x0 + vx * t2
    yl = y0 + vy * t2
    return float(min(zn - (NET_TOP + R_BALL), xl - X_FAR, -xl, Y_HI - yl, yl - Y_LO))
