"""Fit MyoTT's spin model (lib/robolab/skills/myo_tt.w, MyoTTSpin) to MyoSuite's table tennis.

Two experiments on the official myoChallengeTableTennisP2-v0 model, both using the ball's
true angular velocity (mj_data.qvel, privileged) only to FIT the model offline; the
controller's estimator itself sees only the challenge observations.

  bounce   serves as the env launches them, stepped through the env (10 ms frames, the obs
           pipeline the controller sees). Estimator: the ball's horizontal velocity from
           position differences just before and just after the table bounce; spin change
           = cb (dv_t x z). Fits cb, reports the estimate's error against the true spin.
  pad      a kinematically driven pad (velocity re-imposed every 2 ms step, gravity off)
           struck by balls at random incidence, speed, pad velocity and incoming spin. Fits
           the restitution e, the tangential coupling k (share of the slip removed) and the
           spin's push on the return ks (v_out_t = (1 - k) u_t + ks r (w x n)), and reports
           how much spin a contact creates.

    .venv-myo/bin/python playground/myo_tt_spin_fit.py bounce --seeds 500000:500060
    .venv-myo/bin/python playground/myo_tt_spin_fit.py pad --trials 400

Results (MyoSuite 2.12.2): bounce cb 0.432 (theory r m / I = 0.54), estimate error 0.0005
rad/s against a true post-bounce spin of 0.024 rad/s; horizontal velocity kept across the
bounce 0.990. Pad: e 0.97, k 0.011, ks 0.0075; |dw| per impact 0.015 rad/s. The model's
compiler clamps every body's inertia to at least 1e-4 kg m^2 (boundinertia), 139 times the
ball's shell inertia 7.2e-7, so friction barely spins the ball and spin barely moves it.
"""

import argparse
import json

import mujoco
import numpy as np


def make_env():
    from myosuite.utils import gym
    env = gym.make("myoChallengeTableTennisP2-v0")
    return env, env.unwrapped


def bounce(a):
    env, u = make_env()
    m, d = u.mj_model, u.mj_data
    da = m.jnt_dofadr[m.joint("pingpong_freejoint").id]
    rows = []
    lo, hi = (int(x) for x in a.seeds.split(":"))
    for seed in range(lo, hi):
        u.seed(seed)
        env.reset(seed=seed)
        P, W, B = [], [], []
        for _ in range(60):
            o = u.obs_dict
            P.append(np.array(o["ball_pos"]))
            W.append(d.qvel[da + 3:da + 6].copy())
            B.append(float(o["touching_info"][1]))
            env.step(np.zeros(m.nu))
        P, W, B = map(np.array, (P, W, B))
        kb = np.nonzero(B > 0.5)[0]
        if len(kb) == 0 or kb[0] < 3 or kb[0] + 3 >= len(P):
            continue
        k = kb[0]
        v1 = (P[k - 1] - P[k - 2]) / 0.01
        v2 = (P[k + 2] - P[k + 1]) / 0.01
        dv = np.array([v2[0] - v1[0], v2[1] - v1[1], 0.0])
        rows.append((np.cross(dv, [0, 0, 1.0]), W[k + 3] - W[k - 2], np.linalg.norm(v2[:2]) / np.linalg.norm(v1[:2])))
    F = np.array([r[0] for r in rows])
    dW = np.array([r[1] for r in rows])
    cb = float((F * dW).sum() / (F * F).sum())
    err = np.linalg.norm(cb * F - dW, axis=1)
    print(json.dumps({"serves": len(rows), "cb": round(cb, 4), "cb_theory_r_m_over_I": 0.02 * 0.0027 / m.body_inertia[m.body("pingpong").id][0],
                      "spin_after_bounce_mean_rad_s": round(float(np.linalg.norm(dW, axis=1).mean()), 5),
                      "estimate_error_mean_rad_s": round(float(err.mean()), 6), "estimate_error_max_rad_s": round(float(err.max()), 6),
                      "horizontal_velocity_kept": round(float(np.mean([r[2] for r in rows])), 4),
                      "ball_inertia_compiled": m.body_inertia[m.body("pingpong").id].tolist()}, indent=1))


def quat_z_to(n):
    z = np.array([0, 0, 1.0])
    ax = np.cross(z, n)
    s, c = np.linalg.norm(ax), z @ n
    if s < 1e-9:
        return np.array([1.0, 0, 0, 0])
    ang = np.arctan2(s, c)
    return np.r_[np.cos(ang / 2), np.sin(ang / 2) * ax / s]


def pad(a):
    env, u = make_env()
    m, d = u.mj_model, u.mj_data
    u.seed(0)
    env.reset(seed=0)
    q0, v0 = d.qpos.copy(), d.qvel.copy()
    m.opt.gravity[:] = 0
    bj, pj = m.joint("pingpong_freejoint").id, m.joint("paddle_freejoint").id
    bq, bd, pq, pd = m.jnt_qposadr[bj], m.jnt_dofadr[bj], m.jnt_qposadr[pj], m.jnt_dofadr[pj]
    gpad, gball = m.geom("pad").id, m.geom("pingpong").id
    rng = np.random.default_rng(a.seed)
    E, X, Y, DW = [], [], [], []
    for _ in range(a.trials):
        n = rng.normal(size=3)
        n[0] = -abs(n[0]) - 1.5
        n /= np.linalg.norm(n)
        un, inc = rng.uniform(2, 9), np.radians(rng.uniform(0, 55))
        t1 = np.cross(n, [0, 0, 1.0])
        t1 /= np.linalg.norm(t1)
        t2 = np.cross(n, t1)
        phi = rng.uniform(0, 2 * np.pi)
        urel = -un * n + un * np.tan(inc) * (np.cos(phi) * t1 + np.sin(phi) * t2)
        vp = rng.uniform(-0.5, 2.5) * n + rng.uniform(-2.5, 2.5) * t1 + rng.uniform(-2.5, 2.5) * t2
        w_in = rng.normal(size=3) * rng.choice([0, 50, 200])
        d.qpos[:], d.qvel[:] = q0, v0
        center = np.array([2.6, -1.6, 1.6])
        qt = quat_z_to(n)
        R = np.zeros(9)
        mujoco.mju_quat2Mat(R, qt)
        d.qpos[pq:pq + 3] = center - R.reshape(3, 3) @ np.array([-0.07, 0, 0])
        d.qpos[pq + 3:pq + 7] = qt
        dirn = -urel / np.linalg.norm(urel)
        d.qpos[bq:bq + 3] = center + 0.07 / max(1e-6, dirn @ n) * dirn
        d.qvel[bd:bd + 3], d.qvel[bd + 3:bd + 6] = vp + urel, w_in
        mujoco.mj_forward(m, d)
        touched, pre, post = False, None, None
        for _ in range(200):
            d.qvel[pd:pd + 3], d.qvel[pd + 3:pd + 6] = vp, 0
            vb = d.qvel[bd:bd + 6].copy()
            mujoco.mj_step(m, d)
            c = any({d.contact[i].geom1, d.contact[i].geom2} == {gpad, gball} for i in range(d.ncon))
            if c and not touched:
                touched, pre = True, vb
            if touched and not c:
                post = d.qvel[bd:bd + 6].copy()
                break
        if pre is None or post is None:
            continue
        uu, ww = pre[:3] - vp, post[:3] - vp
        E.append(-(ww @ n) / (uu @ n))
        X.append((uu - (uu @ n) * n, 0.02 * np.cross(pre[3:], n)))
        Y.append(ww - (ww @ n) * n)
        DW.append(np.linalg.norm(post[3:] - pre[3:]))
    M = np.array([np.c_[x[0], x[1]] for x in X]).reshape(-1, 2)
    y = np.array(Y).ravel()
    coef, *_ = np.linalg.lstsq(M, y, rcond=None)
    print(json.dumps({"impacts": len(E), "e": round(float(np.mean(E)), 4), "e_sd": round(float(np.std(E)), 4),
                      "k_tangential_coupling": round(float(1 - coef[0]), 4), "ks_spin_push": round(float(coef[1]), 4),
                      "spin_change_per_impact_mean_rad_s": round(float(np.mean(DW)), 4)}, indent=1))


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("what", choices=["bounce", "pad"])
    ap.add_argument("--seeds", default="500000:500060")
    ap.add_argument("--trials", type=int, default=400)
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args()
    bounce(a) if a.what == "bounce" else pad(a)
