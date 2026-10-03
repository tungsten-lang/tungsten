#!/usr/bin/env python3
"""Does the champion's paddle keep one plane on its way to the ball? (30 Sep 2026, from Erik's note that most strokes hold a constant plane.)

    .venv-myo/bin/python scratchpad/tt4/plane_probe.py [LOGDIR]        # default out/tt3/logs_o0 (T3's record of the champion, 200 serves)

Read-only: it reads T3's per-tick records (playground/tasks/myo_tt.py TT_SAVE_LOG format: L = time, ball, ball vel, pad centre, paddle vel, pad normal, pelvis,
touch, palm error, ..., X = 12 joint angles then 12 joint speeds, contact = tick of the first paddle touch) and the MyoSuite model, and reports

  1. how far the pad normal rotates in the last 0.05-0.30 s before contact, and how fast it is turning at contact;
  2. how hard the paddle's direction of travel is aligned with its normal at contact (a block: along it; a brush: across it);
  3. the grasp: the paddle's pose relative to the hand is rigid? (the normal recomputed from the logged joints with a rigid hand against the logged normal);
  4. the lever of each joint on the normal (|joint axis x normal|: rad of normal per rad of joint) and each joint's share of the normal's turning at contact.
"""
import glob
import os
import sys

import numpy as np

R = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LOGDIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(R, "out/tt3/logs_o0")
XML = os.path.join(R, ".venv-myo/lib/python3.12/site-packages/myosuite/envs/myo/assets/arm/myoarm_tabletennis.xml")
JN = ("elv_angle", "shoulder_elv", "shoulder_rot", "elbow_flexion", "pro_sup", "deviation", "flexion", "axial_rotation", "flex_extension", "lat_bending", "pelvis_x", "pelvis_y")
# [dependent, independent, coefficient] (playground/tasks/myo_tt_oracle.py COUPLINGS = lib/robolab/skills/myo_tt.w MyoTTKin.couplings)
COUPLINGS = [("Abs_r3", "flex_extension", 0.6429), ("L4_L5_FE", "flex_extension", 0.185), ("L3_L4_FE", "flex_extension", 0.204), ("L2_L3_FE", "flex_extension", 0.231),
             ("L1_L2_FE", "flex_extension", 0.255), ("L4_L5_LB", "lat_bending", 0.1811), ("L3_L4_LB", "lat_bending", 0.2453), ("L2_L3_LB", "lat_bending", 0.2501),
             ("L1_L2_LB", "lat_bending", 0.188), ("L4_L5_AR", "axial_rotation", 0.0378), ("L3_L4_AR", "axial_rotation", 0.0378), ("L2_L3_AR", "axial_rotation", 0.0311),
             ("L1_L2_AR", "axial_rotation", 0.0289), ("sternoclavicular_r2", "shoulder_elv", -0.242), ("sternoclavicular_r3", "shoulder_elv", 0.1025),
             ("unrotscap_r2", "shoulder_elv", 0.242), ("unrotscap_r3", "shoulder_elv", -0.1025), ("acromioclavicular_r1", "shoulder_elv", 0.178),
             ("acromioclavicular_r2", "shoulder_elv", -0.049), ("acromioclavicular_r3", "shoulder_elv", 0.396), ("unrothum_r1", "shoulder_elv", -0.178),
             ("unrothum_r2", "shoulder_elv", 0.049), ("unrothum_r3", "shoulder_elv", -0.396), ("shoulder1_r2", "elv_angle", -1.0)]


def ang(a, b):
    return np.degrees(np.arccos(np.clip(a @ b / (np.linalg.norm(a) * np.linalg.norm(b)), -1, 1)))


def pct(x, q):
    return float(np.percentile(x, q)) if len(x) else float("nan")


def stat(x):
    x = np.asarray(x, float)
    return f"median {pct(x, 50):6.1f}  p90 {pct(x, 90):6.1f}  max {np.max(x) if len(x) else float('nan'):6.1f}  (n={len(x)})"


def main():
    import mujoco
    files = sorted(glob.glob(os.path.join(LOGDIR, "*.npz")))
    if os.environ.get("PROBE_SEEDS"):   # e.g. 98000:98100, to compare on the same serves
        lo, hi = (int(x) for x in os.environ["PROBE_SEEDS"].split(":"))
        files = [f for f in files if lo <= int(os.path.basename(f)[:-4]) < hi]
    recs = []
    for f in files:
        z = np.load(f, allow_pickle=True)
        k = int(z["contact"])
        if k >= 3 and z["X"].ndim == 2 and len(z["X"]) == len(z["L"]):
            recs.append((os.path.basename(f), z["L"], z["X"], k - 1))   # kk = the tick before the contact, as metrics() does
    print(f"{len(files)} logs in {LOGDIR}, {len(recs)} with a paddle contact")
    dt = np.median(np.diff(recs[0][1][:, 0]))
    print(f"tick {dt * 1000:.1f} ms; contact time median {np.median([r[1][r[3], 0] for r in recs]):.3f} s")

    # the side of each serve: the plane of elevation reached at contact (forehand ~ +1.0, backhand ~ +0.3: T3 LOG 01:13)
    elv = np.array([r[2][r[3], 0] for r in recs])
    side = np.where(elv > 0.6, "forehand", "backhand")
    print("plane of elevation at contact histogram:", np.histogram(elv, bins=[-2, 0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 3])[0].tolist(), "->", {s: int((side == s).sum()) for s in ("forehand", "backhand")})

    print("\n== 1. the pad normal's rotation before contact (degrees between the normal at t_contact and at t_contact - lag)")
    for grp in ("forehand", "backhand", "all"):
        sel = [i for i in range(len(recs)) if grp == "all" or side[i] == grp]
        print(f"-- {grp}")
        for lag in (0.05, 0.10, 0.20, 0.30):
            ds = []
            for i in sel:
                _, L, X, kk = recs[i]
                t = L[:, 0]
                j = int(np.argmin(np.abs(t - (t[kk] - lag))))
                ds.append(ang(L[kk, 13:16], L[j, 13:16]))
            print(f"   lag {lag * 1000:3.0f} ms: {stat(ds)}")
        w = []
        for i in sel:
            _, L, X, kk = recs[i]
            t = L[:, 0]
            k0 = max(kk - 2, 0)
            w.append(ang(L[kk, 13:16], L[k0, 13:16]) / max(t[kk] - t[k0], 1e-6))
        print(f"   turning rate of the normal at contact (deg/s): {stat(w)}")
        print(f"   -> a contact-time shift of +-10 ms moves the face by median {0.010 * pct(w, 50):.1f} deg, p90 {0.010 * pct(w, 90):.1f} deg; +-20 ms: {0.020 * pct(w, 50):.1f} / {0.020 * pct(w, 90):.1f}")

    print("\n== 2. the direction of travel of the pad centre against its normal at contact (0 deg = straight along the normal: a block; 90 = across it: a brush)")
    for grp in ("forehand", "backhand"):
        sel = [i for i in range(len(recs)) if side[i] == grp]
        a, sp = [], []
        for i in sel:
            _, L, X, kk = recs[i]
            t = L[:, 0]
            v = (L[kk, 7:10] - L[kk - 1, 7:10]) / max(t[kk] - t[kk - 1], 1e-6)
            sp.append(np.linalg.norm(v))
            c = abs(v @ L[kk, 13:16]) / max(np.linalg.norm(v), 1e-9)
            a.append(np.degrees(np.arccos(np.clip(c, 0, 1))))
        print(f"   {grp}: angle {stat(a)}; speed m/s median {pct(sp, 50):.2f} p90 {pct(sp, 90):.2f}")

    print("\n== 3. the grasp: is the paddle rigid in the hand, and does its pose in the hand move?")
    m = mujoco.MjModel.from_xml_path(XML)
    d = mujoco.MjData(m)
    d.qpos[:] = m.key_qpos[0]
    mujoco.mj_forward(m, d)
    gid = m.geom("pad").id
    pad_b = m.geom_bodyid[gid]
    sid = m.site("S_grasp").id
    hand_b = m.site_bodyid[sid]
    n_key = d.geom_xmat[gid].reshape(3, 3)[:, 2].copy()
    Rh_key = d.xmat[hand_b].reshape(3, 3).copy()
    nh_key = Rh_key.T @ n_key                      # the pad normal in the hand body's frame at the model's start pose
    print(f"   hand body '{m.body(hand_b).name}', paddle body '{m.body(pad_b).name}'; start pose: pad normal in the world {np.round(n_key, 3).tolist()}, in the hand frame {np.round(nh_key, 3).tolist()}")
    jid = {n: m.joint(n).id for n in JN}
    qadr = {n: m.jnt_qposadr[jid[n]] for n in JN}
    dep = [(m.jnt_qposadr[m.joint(a).id], m.jnt_qposadr[m.joint(b).id], c) for a, b, c in COUPLINGS]
    base = m.key_qpos[0].copy()

    def pose(qv):
        q = base.copy()
        for k, n in enumerate(JN):
            q[qadr[n]] = qv[k]
        for da, ia, c in dep:
            q[da] = c * q[ia]
        d.qpos[:] = q
        mujoco.mj_kinematics(m, d)
        return d.xmat[hand_b].reshape(3, 3).copy(), d.site_xpos[sid].copy()

    perr, series = [], []
    for (name, L, X, kk) in recs:
        T = []
        for i in range(kk + 1):
            Rh, palm = pose(X[i, :12])
            T.append((Rh.T @ L[i, 13:16], Rh.T @ (L[i, 7:10] - palm), palm))
        series.append(T)
        perr.append(100 * np.linalg.norm(T[kk][2] - L[kk, 30:33]))
    print(f"   kinematics check: my palm position against the logged one at contact (cm): {stat(perr)}")
    print("   the pad normal in the HAND frame against its start-pose value (deg) and the pad centre's offset in the hand frame against the start (cm), by time:")
    for tt in (0.0, 0.1, 0.2, 0.3, 0.4):
        dn, dp = [], []
        for (name, L, X, kk), T in zip(recs, series):
            i = int(np.argmin(np.abs(L[:kk + 1, 0] - tt)))
            dn.append(ang(T[i][0], nh_key))
            dp.append(100 * np.linalg.norm(T[i][1] - series[0][0][1]))
        print(f"     t = {tt:.1f} s: normal in hand {stat(dn)}")
    print("   the grip after it has settled (the paddle swings ~20 deg in the hand in the first 0.1 s, before the fingers close: rows above): rotation of the pad normal IN THE HAND FRAME and shift of the pad centre in the hand frame before contact, by side")
    for grp in ("forehand", "backhand", "all"):
        sel = [i for i in range(len(recs)) if grp == "all" or side[i] == grp]
        for lag in (0.2, 0.1, 0.05):
            xr, xs = [], []
            for i in sel:
                (name, L, X, kk), T = recs[i], series[i]
                j = int(np.argmin(np.abs(L[:kk + 1, 0] - (L[kk, 0] - lag))))
                xr.append(ang(T[j][0], T[kk][0]))
                xs.append(100 * np.linalg.norm(T[j][1] - T[kk][1]))
            print(f"   {grp:8s} t_contact - {lag * 1000:3.0f} ms -> contact: normal turns {stat(xr)};  pad centre shifts (cm) median {pct(xs, 50):.1f} p90 {pct(xs, 90):.1f}")

    print("\n== 4. which joints can steer the plane (lever = |joint axis x LOGGED normal|: rad of normal per rad of joint; 1 = the joint swings the face, 0 = it only spins the face about its own normal)")
    names = JN[:10]
    levers = {s: [] for s in ("forehand", "backhand")}
    share = {s: {n: [] for n in names} for s in ("forehand", "backhand")}
    for i, (name, L, X, kk) in enumerate(recs):
        pose(X[kk, :12])
        n = L[kk, 13:16] / np.linalg.norm(L[kk, 13:16])
        row = []
        for nm in names:
            ax = d.xaxis[jid[nm]].copy()
            lev = float(np.linalg.norm(np.cross(ax, n)))
            row.append(lev)
            share[side[i]][nm].append(np.degrees(lev * abs(X[kk, 12 + JN.index(nm)])))
        levers[side[i]].append(row)
    for s in ("forehand", "backhand"):
        lv = np.array(levers[s])
        print(f"-- {s}: lever and the joint's own contribution to the normal's turning at contact (deg/s = lever x joint speed)")
        for k, nm in enumerate(names):
            print(f"   {nm:15s} lever median {np.median(lv[:, k]):.2f} (p10 {pct(lv[:, k], 10):.2f}, p90 {pct(lv[:, k], 90):.2f})   turning contribution median {pct(share[s][nm], 50):6.1f} deg/s  p90 {pct(share[s][nm], 90):6.1f}")
    print("\n(the contributions are upper bounds that ignore cancellation between joints; the net turning rate is in section 1)")


if __name__ == "__main__":
    main()
