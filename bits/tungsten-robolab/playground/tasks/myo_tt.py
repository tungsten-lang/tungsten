"""MyoChallenge 2025 table tennis: robolab's MyoTT skill on the official env.

The environment (MyoSuite 2.12, myosuite/envs/myo/myochallenge/tabletennis_v0.py)
is used unchanged: myoArm + myoTorso (273 muscles) plus the two pelvis
position actuators, a free paddle held only by the hand's contacts, 3 s
episodes at 100 Hz. `solved` is the official criterion: the ball touches
the paddle and then lands on the opponent's half (no second own-half
bounce, no double touch). TT_ENV=P2 switches to the randomised phase-2 serve
(serve position and velocity, paddle mass, ball friction).

Metrics per episode (beyond the bridge's): hit (paddle touched the ball),
solved, contact time, paddle speed at contact, the ball's closest approach
to the pad centre before contact (misses), where the return landed, the
movement onset (reaction) of the pelvis and of the paddle relative to the
body, and effort (mean squared activation over all 273 muscles, the
bridge's `effort`).
"""

import os
import sys

import numpy as np

_PLAYGROUND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PLAYGROUND not in sys.path:  # run as a script (the evaluation report)
    sys.path.insert(0, _PLAYGROUND)

from myo_bridge import MyoTask  # noqa: E402

PHASE = os.environ.get("TT_ENV", "P1")

# ---- realistic-physics test variant (TT_REAL_SPIN=1; NOT the challenge) ----------
# The official env has no air (opt.density 0), its compiler clamps every
# body's inertia to 1e-4 kg m^2 (boundinertia), 139 times the ball's thin
# shell, and its ball contacts (solref -8e4 -1, direct) damp the slip at the
# contact point at only ~1 /s, so a bounce removes ~0.5% of the tangential
# velocity: contacts barely spin the ball and spin barely moves it. With
# TT_REAL_SPIN=1 (opt-in; off, the task is unchanged) the ball gets:
#   inertia  the thin shell's 2/3 m r^2 (7.2e-7 kg m^2 for 2.7 g, r 0.02 m),
#            with its mass-matrix block (dof_M0: MuJoCo takes a "simple"
#            free body's block from it, not from body_inertia) and constraint
#            weights (dof_invweight0, body_invweight0) set to match
#   drag     F = -1/2 rho Cd A |v| v              (rho 1.2, Cd TT_DRAG_CD 0.5)
#   Magnus   F = 1/2 rho C A r (omega x v)        (C TT_MAGNUS_C 0.3; the
#            linear lift model, i.e. a lift coefficient C_L = C S at spin
#            ratio S = r |omega| / |v|)
#   friction Coulomb friction at every contact of the ball (the rigid-ball
#            bounce model): while it touches a body, the normal impulse the
#            contact has delivered (m times the rise of the normal relative
#            velocity, substep by substep) buys a tangential impulse budget
#            mu J_n, spent on removing the slip of the ball's surface over
#            the other surface (up to m_eff |v_slip| per substep, m_eff =
#            1 / (1/m + r^2/I) = 0.4 m: rolling, if the budget lasts); the
#            force acts at the contact point (so it spins the ball) and its
#            reaction on the other body. mu: table TT_MU_TABLE 0.25, the
#            pad's rubber TT_MU_PAD 0.8, anything else TT_MU_OTHER 0.3;
#            TT_MU_TABLE=TT_MU_PAD=TT_MU_OTHER=0 leaves MuJoCo's own contact;
#            otherwise the ball's contacts are made frictionless in MuJoCo
#            (condim 1; the ball's geom has the contact priority), whose soft
#            friction rows would cancel this friction (the env's randomised
#            ball friction then plays no part)
#   seeing   the env's ball_vel observation is a velocimeter in the ball's
#            own frame (harmless when the ball cannot spin): it is replaced
#            by the ball's world velocity each step
# with A = pi r^2, v the ball's world velocity (air at rest), omega its
# world angular velocity (a free joint's qvel carries it in the body frame:
# rotated by xmat). The forces are recomputed every physics substep (2 ms;
# the env steps 5 per 10 ms action, on its robot's own MjData) in MuJoCo's
# control callback (after collision detection, before the constraint
# solve), written to xfrc_applied; the callback only acts on the model and
# data it was installed for, and is removed when the episode's metrics are
# taken. Air torque on the spin (spin decay) is not modelled.
AIR_RHO = 1.2
_AERO = {}


def real_spin_on():
    return os.environ.get("TT_REAL_SPIN") == "1"


def _ball_contacts(m, d, gid):
    """{other body: (its geom, contact point, normal pointing into the ball)} for
    the bodies touching the ball (the deepest contact per body)."""
    n = d.ncon
    if n == 0:
        return {}
    G = d.contact.geom[:n]
    out = {}
    for i in np.nonzero((G[:, 0] == gid) | (G[:, 1] == gid))[0]:
        dist = float(d.contact.dist[i])
        if dist > 0.0:
            continue
        g1, g2 = int(G[i, 0]), int(G[i, 1])
        other = g2 if g1 == gid else g1
        nrm = np.array(d.contact.frame[i][:3])
        if g1 == gid:
            nrm = -nrm   # the frame's normal points from geom1 to geom2
        ob = int(m.geom_bodyid[other])
        if ob not in out or dist < out[ob][3]:
            out[ob] = (other, np.array(d.contact.pos[i]), nrm, dist)
    return out


def _aero_callback(m, d):
    import mujoco
    st = _AERO
    if not st or m is not st["m"] or d is not st["d"]:
        return
    b, a = st["bid"], st["dof"]
    for ob in st["pushed"]:
        d.xfrc_applied[ob] = 0.0
    st["pushed"] = []
    v = np.array(d.qvel[a:a + 3])
    w = d.xmat[b].reshape(3, 3) @ np.array(d.qvel[a + 3:a + 6])
    f = -st["kd"] * np.linalg.norm(v) * v + st["km"] * np.cross(w, v)
    tq = np.zeros(3)
    if st["friction"]:
        live = {}
        res = np.zeros(6)
        for ob, (g, p, nrm, _) in _ball_contacts(m, d, st["gid"]).items():
            rb = p - d.xpos[b]
            vo = np.zeros(3)
            static = int(m.body_weldid[ob]) == 0
            if not static:
                mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_XBODY, ob, res, 0)
                vo = res[3:] + np.cross(res[:3], p - d.xpos[ob])
            rel = v + np.cross(w, rb) - vo
            vn = float(rel @ nrm)
            prev = st["touch"].get(ob)
            budget = 0.0
            if prev is not None:
                budget = prev["budget"] + st["mu"][g] * st["mass"] * max(0.0, vn - prev["vn"])
            vt = rel - vn * nrm
            sp = float(np.linalg.norm(vt))
            dj = min(st["meff"] * sp, budget) if sp > 1e-9 else 0.0
            if dj > 0.0:
                F = -(dj / st["dt"]) * vt / sp
                f = f + F
                tq = tq + np.cross(rb, F)
                if not static:
                    d.xfrc_applied[ob, :3] -= F
                    d.xfrc_applied[ob, 3:] -= np.cross(p - d.xipos[ob], F)
                    st["pushed"].append(ob)
            live[ob] = {"vn": vn, "budget": budget - dj}
        st["touch"] = live
    d.xfrc_applied[b, :3] = f
    d.xfrc_applied[b, 3:] = tq


class MyoTTTask(MyoTask):
    name = "myo_tt"
    env_id = f"myoChallengeTableTennis{PHASE}-v0"
    # the bridge's joint-pair length corrections (opt-in; the practised
    # postures were tuned without them)
    geometry_pairs = os.environ.get("TT_PAIRS") == "1"
    # lengths sampled with the joint-equality couplings applied (the
    # shoulder's clavicle and scapula follow its elevation); opt-in
    coupled_geometry = os.environ.get("TT_COUPLED") == "1"
    # the pelvis slides' mass-matrix columns and accelerations (mcol_pelvis_x,
    # mcol_pelvis_y, cacc): the inertial load the 139 kg slide puts on every
    # joint, for the skill's inverse-dynamics feed-forward (id_mode); extra
    # sensor blocks only, which a controller that does not read them ignores
    coupling_joints = ("pelvis_x", "pelvis_y")

    # the skill's servo joints, in its order (MyoTTKin.servo_joints)
    servo_joints = ("elv_angle", "shoulder_elv", "shoulder_rot", "elbow_flexion", "pro_sup", "deviation", "flexion",
                    "axial_rotation")

    def hand_jacobian(self, sim):
        """The hand's (S_grasp site) world linear and angular Jacobians over the
        servo joints at the current posture, each joint's equality-slaved
        joints folded in by the constraint's derivative there: forward
        kinematics of the model at the observed joint angles (the skill's
        jac_live; it otherwise uses constants taken at one posture)."""
        import mujoco
        m, d = sim.m, sim.d
        if not hasattr(sim, "_tt_jac"):
            cols = []
            for nm in self.servo_joints:
                j = m.joint(nm).id
                deps = [(m.jnt_dofadr[j], None, None)]
                for e in range(m.neq):
                    if m.eq_type[e] == mujoco.mjtEq.mjEQ_JOINT and m.eq_obj2id[e] == j:
                        deps.append((m.jnt_dofadr[m.eq_obj1id[e]], m.jnt_qposadr[j], np.array(m.eq_data[e][:5])))
                cols.append(deps)
            sim._tt_jac = (cols, m.site("S_grasp").id, np.zeros((3, m.nv)), np.zeros((3, m.nv)))
        cols, site, jp, jr = sim._tt_jac
        mujoco.mj_jacSite(m, d, jp, jr, site)
        JV, JW = np.zeros((3, len(cols))), np.zeros((3, len(cols)))
        for k, deps in enumerate(cols):
            for dof, qa, c in deps:
                # y = c0 + c1 x + c2 x^2 + c3 x^3 + c4 x^4: dy/dx at the master's angle
                g = 1.0 if c is None else c[1] + d.qpos[qa] * (2 * c[2] + d.qpos[qa] * (3 * c[3] + 4 * c[4] * d.qpos[qa]))
                JV[:, k] += g * jp[:, dof]
                JW[:, k] += g * jr[:, dof]
        return np.r_[JV.ravel(), JW.ravel()]

    ARM_MUSCLES = ("DELT1", "DELT2", "DELT3", "SUPSP", "INFSP", "SUBSC", "TMIN", "TMAJ", "PECM1", "PECM2", "PECM3",
                   "LAT1", "LAT2", "LAT3", "CORB", "TRIlong", "TRIlat", "TRImed", "ANC", "SUP", "BIClong", "BICshort",
                   "BRA", "BRD", "ECRL", "ECRB", "ECU", "FCR", "FCU", "PL", "PT", "PQ")

    def arm_moments(self, sim):
        """Opt-in (params `lt_arms 1`, so older controllers see the same handshake): the live
        moment arms d length / d q (m/rad, MuJoCo's actuator moments at the current posture) of the
        32 arm muscles (MyoTTKin.arm_muscles order) over the 8 servo joints, row-major (muscle i,
        joint j at 8 i + j), each joint's equality-slaved joints folded in by the constraint's
        derivative there (as hand_jac). The controller's own length model is additive (each joint
        swept alone from the reset posture): on the shoulder it is off by up to 0.36 of a muscle's
        range at the forehand's commanded posture (BIClong) and 0.86 at the backhand's."""
        import mujoco
        m, d = sim.m, sim.d
        if not hasattr(sim, "_tt_jac"):
            self.hand_jacobian(sim)
        cols = sim._tt_jac[0]
        if not hasattr(sim, "_tt_arm_ids"):
            sim._tt_arm_ids = [m.actuator(n).id for n in self.ARM_MUSCLES]
        mom = np.zeros((m.nu, m.nv))
        mujoco.mju_sparse2dense(mom, d.actuator_moment, d.moment_rownnz, d.moment_rowadr, d.moment_colind)
        A = mom[sim._tt_arm_ids]
        out = np.zeros((len(sim._tt_arm_ids), len(cols)))
        for k, deps in enumerate(cols):
            for dof, qa, c in deps:
                g = 1.0 if c is None else c[1] + d.qpos[qa] * (2 * c[2] + d.qpos[qa] * (3 * c[3] + 4 * c[4] * d.qpos[qa]))
                out[:, k] += g * A[:, dof]
        return out.ravel()

    def real_spin_setup(self, sim):
        """TT_REAL_SPIN: the ball's thin-shell inertia and the air (see the
        module comment), installed once per episode before the first step."""
        import mujoco
        m, d = sim.m, sim.d
        b = m.body("pingpong").id
        r = float(m.geom_size[m.geom("pingpong").id][0])
        a = int(m.jnt_dofadr[m.joint("pingpong_freejoint").id])
        inertia = 2.0 / 3.0 * float(m.body_mass[b]) * r * r
        m.body_inertia[b] = inertia
        # a free body with a diagonal inertia is "simple": MuJoCo takes its
        # mass-matrix block from dof_M0 (compiled) rather than the inertia
        m.dof_M0[a + 3:a + 6] = inertia
        m.dof_invweight0[a + 3:a + 6] = 1.0 / inertia
        m.body_invweight0[b, 1] = 1.0 / inertia
        area = np.pi * r * r
        # MyoSuite integrates its robot's own MjData (the env's mj_data is a
        # copy synchronised after each step): the air acts on that one
        robot = getattr(sim.u, "robot", None) if hasattr(sim, "u") else None
        dphys = getattr(robot, "mj_data", None) or d
        env = os.environ.get
        mu = np.full(m.ngeom, float(env("TT_MU_OTHER", "0.3")))
        for i in range(m.ngeom):
            nm = m.geom(i).name
            if "table" in nm:
                mu[i] = float(env("TT_MU_TABLE", "0.25"))
            elif nm == "pad":
                mu[i] = float(env("TT_MU_PAD", "0.8"))
        mass = float(m.body_mass[b])
        if mu.max() > 0.0:
            # the ball's contacts become frictionless in MuJoCo (the ball's
            # geom has the higher priority, so its condim rules): the soft
            # friction rows would hold the slip to their slow reference and
            # cancel the Coulomb friction applied here
            m.geom_condim[m.geom("pingpong").id] = 1
        _AERO.clear()
        _AERO.update(m=m, d=dphys, bid=b, dof=a, gid=m.geom("pingpong").id, dt=float(m.opt.timestep),
                     kd=0.5 * AIR_RHO * float(env("TT_DRAG_CD", "0.5")) * area,
                     km=0.5 * AIR_RHO * float(env("TT_MAGNUS_C", "0.3")) * area * r,
                     mu=mu, friction=bool(mu.max() > 0.0), mass=mass,
                     meff=1.0 / (1.0 / mass + r * r / inertia), touch={}, pushed=[])
        mujoco.set_mjcb_control(_aero_callback)
        sim.tt_real = True
        sim.tt_ww = []

    def extra_sensors(self, sim):
        if real_spin_on() and not getattr(sim, "tt_real", False):
            self.real_spin_setup(sim)
        # hand_jac: the hand's Jacobians at the current posture (the skill's
        # jac_live); an extra block, which a controller that does not read it
        # ignores
        out = [("hand_jac", self.hand_jacobian(sim))]
        if sim.params.get("lt_arms", 0) > 0.5:
            out.append(("arm_mom", self.arm_moments(sim)))
        # TT_SPIN_ORACLE=1: the ball's true angular velocity (privileged, not
        # in the challenge's observations), for the oracle-spin upper bound
        if os.environ.get("TT_SPIN_ORACLE") != "1":
            return out
        j = sim.m.joint("pingpong_freejoint")
        a = sim.m.jnt_dofadr[j.id]
        return out + [("oracle_spin", np.array(sim.d.qvel[a + 3:a + 6]))]

    def on_command(self, sim, cmd):
        if cmd.startswith("spin:"):
            sim.tt_spin = (sim.d.time, [float(x) for x in cmd.split(":")[1:]])
        elif cmd.startswith("flm:"):
            sim.tt_flm = float(cmd.split(":")[1])
        elif cmd.startswith("fam:"):
            sim.tt_fam = int(float(cmd.split(":")[1]))
        elif cmd.startswith("famdir:"):
            v = [float(x) for x in cmd.split(":")[1:]]
            sim.tt_fam = int(v[0])
            sim.tt_famdir = v[1:]
        elif cmd.startswith("aim:"):
            if not hasattr(sim, "tt_aim"):
                sim.tt_aim = []
            sim.tt_aim.append((sim.d.time, *[float(x) for x in cmd.split(":")[1:]]))
        elif cmd.startswith("side:"):
            sim.tt_side = int(cmd.split(":")[1])
        elif cmd.startswith("qs:"):
            sim.tt_qs = [float(x) for x in cmd.split(":")[1:]]
        elif cmd.startswith("feat:"):
            sim.tt_feat = [float(x) for x in cmd.split(":")[1:]]
        elif cmd.startswith("qc:"):
            sim.tt_qc = [float(x) for x in cmd.split(":")[1:]]
        elif cmd == "stroke":
            sim.tt_stroke = sim.d.time

    def on_step(self, sim, obs, reward, info):
        if getattr(sim, "tt_real", False):
            # the env's ball_vel is a velocimeter at a site on the ball, so in
            # the ball's own frame, which now spins: the controller (and the
            # log) get the ball's world velocity instead, as a player sees it
            a = sim.m.jnt_dofadr[sim.m.joint("pingpong_freejoint").id]
            sim.u.obs_dict["ball_vel"] = np.array(sim.d.qvel[a:a + 3])
        o = sim.u.obs_dict
        m, d = sim.m, sim.d
        if not hasattr(sim, "tt_log"):
            sim.tt_log = []
        nrm = d.geom_xmat[m.geom("pad").id].reshape(3, 3)[:, 2]
        pad = d.geom_xpos[m.geom("pad").id]
        j = m.joint("pingpong_freejoint")
        if not hasattr(sim, "tt_w"):
            sim.tt_w = []
        sim.tt_w.append(d.qvel[m.jnt_dofadr[j.id] + 3:m.jnt_dofadr[j.id] + 6].copy())
        if getattr(sim, "tt_real", False):
            # the ball's angular velocity in the world frame
            sim.tt_ww.append(d.xmat[m.body("pingpong").id].reshape(3, 3) @ sim.tt_w[-1])
        act = np.asarray(o["act"], dtype=float)
        sim.tt_log.append(np.r_[d.time, o["ball_pos"], o["ball_vel"], pad, o["paddle_vel"], nrm,
                                o["pelvis_pos"], o["touching_info"], o["palm_err"],
                                float(np.mean(act ** 2)), float(np.linalg.norm(act) / len(act)), o["palm_pos"]])

    def metrics(self, sim, log):
        L = np.array(sim.tt_log)
        t, ball, bvel, pad, pvel, nrm, pel, touch, palm = (L[:, 0], L[:, 1:4], L[:, 4:7], L[:, 7:10], L[:, 10:13],
                                                           L[:, 13:16], L[:, 16:19], L[:, 19:25], L[:, 25:28])
        out = {}
        out["serve"] = [round(float(x), 3) for x in np.r_[ball[0], bvel[0]]]
        hit_idx = np.nonzero(touch[:, 0] > 0)[0]
        hit = len(hit_idx) > 0
        out["hit"] = 1.0 if hit else 0.0
        k = hit_idx[0] if hit else None
        # closest approach of the ball to the pad centre before contact
        end = k if hit else len(L)
        dist = np.linalg.norm(ball[:end] - pad[:end], axis=1) if end > 0 else np.array([9.0])
        j = int(np.argmin(dist))
        out["miss_dist"] = round(float(dist[j]), 4)
        out["miss_vec"] = [round(float(x), 3) for x in (ball[j] - pad[j])]
        if hit:
            out["t_contact"] = round(float(t[k]), 3)
            kk = max(k - 1, 0)
            out["paddle_speed"] = round(float(np.linalg.norm(pvel[kk])), 3)
            # the pad centre's world velocity (the env's paddle_vel is a
            # velocimeter in the paddle's own frame; its norm is the speed)
            vw = (pad[kk] - pad[max(kk - 1, 0)]) / max(t[kk] - t[max(kk - 1, 0)], 1e-6)
            out["paddle_vel"] = [round(float(x), 3) for x in vw]
            out["ball_in_exact"] = [round(float(x), 4) for x in bvel[kk]]
            # the ball leaves the paddle: first step without paddle contact
            j2 = k
            while j2 < len(L) - 1 and touch[j2, 0] > 0:
                j2 += 1
            out["ball_out_exact"] = [round(float(x), 4) for x in bvel[j2]]
            out["ball_pos_out"] = [round(float(x), 4) for x in ball[j2]]
            out["pad_normal"] = [round(float(x), 3) for x in nrm[kk]]
            out["pad_at_contact"] = [round(float(x), 3) for x in pad[kk]]
            out["pad_minus_palm"] = [round(float(x), 3) for x in (pad[kk] - L[kk, 30:33])]
            out["ball_in"] = [round(float(x), 2) for x in bvel[kk]]
            # the return: first contact after leaving the paddle
            after = np.nonzero((touch[k + 1:, 1:].sum(axis=1) > 0))[0]
            if len(after):
                a = k + 1 + after[0]
                lab = ["own", "opponent", "net", "ground", "env"][int(np.argmax(touch[a, 1:6] > 0))]
                out["landed"] = lab
                out["land_xy"] = [round(float(ball[a, 0]), 3), round(float(ball[a, 1]), 3)]
            out["ball_out"] = [round(float(x), 2) for x in bvel[min(k + 3, len(L) - 1)]]
        # movement onset: pelvis speed above 0.1 m/s
        pv = np.linalg.norm(np.diff(pel, axis=0), axis=1) / np.maximum(np.diff(t), 1e-6)
        on = np.nonzero(pv > 0.1)[0]
        out["pelvis_onset"] = round(float(t[on[0] + 1]), 3) if len(on) else None
        out["palm_err_max"] = round(float(np.linalg.norm(palm, axis=1).max()), 3)
        out["trunk_flex_end"] = round(float(sim.d.qpos[sim.m.jnt_qposadr[sim.m.joint("flex_extension").id]]), 3)
        out["side"] = getattr(sim, "tt_side", 0)
        # the pad's lateral offset from the pelvis, 0.40-0.50 s
        w2 = (t >= 0.40) & (t <= 0.50)
        if w2.any():
            out["pad_offset"] = round(float(np.mean(pad[w2, 1] - pel[w2, 1])), 4)
        if hasattr(sim, "tt_qs"):
            out["q_servo"] = [round(x, 5) for x in sim.tt_qs]
        if hasattr(sim, "tt_feat"):
            out["feat"] = [round(x, 5) for x in sim.tt_feat]
        if hasattr(sim, "tt_qc"):
            out["q_corr"] = [round(x, 4) for x in sim.tt_qc]
        if hasattr(sim, "tt_stroke"):
            out["t_stroke"] = round(float(sim.tt_stroke), 3)
        # spin: the skill's estimate (from the bounce) against the true
        # angular velocity at the same moment and at contact (privileged,
        # evaluation only); the stroke family and its direction against the
        # pad's achieved velocity direction at contact (x-z plane)
        W = np.array(sim.tt_w)
        if hasattr(sim, "tt_spin"):
            ts, w_est = sim.tt_spin
            ks = int(np.argmin(np.abs(t - ts)))
            out["spin_est"] = [round(x, 5) for x in w_est]
            out["spin_true_at_est"] = [round(float(x), 5) for x in W[ks]]
            out["spin_err"] = round(float(np.linalg.norm(np.array(w_est) - W[ks])), 5)
        kc = hit_idx[0] - 1 if hit else None
        if kc is not None and kc >= 0:
            out["spin_true_at_contact"] = [round(float(x), 5) for x in W[kc]]
        if hasattr(sim, "tt_flm"):
            # the flick chooser's robust landing margin at the lock (m)
            out["flick_margin"] = round(sim.tt_flm, 4)
        if hasattr(sim, "tt_fam"):
            out["family"] = ["?", "block", "over", "chop", "give", "flick", "scoop"][sim.tt_fam]
        if hasattr(sim, "tt_famdir") and hit and "paddle_vel" in out:
            dv = np.array([sim.tt_famdir[0], 0.0, sim.tt_famdir[1]])
            pv = np.array(out["paddle_vel"])
            pxz = np.array([pv[0], 0.0, pv[2]])
            if np.linalg.norm(pxz) > 0.05:
                c = float(pxz @ dv / np.linalg.norm(pxz))
                out["stroke_dir_err_deg"] = round(float(np.degrees(np.arccos(np.clip(c, -1, 1)))), 2)
            if len(sim.tt_famdir) >= 5:
                # what the return depends on (a nearly frictionless contact):
                # the pad's speed along its normal, achieved minus expected
                ve = np.array(sim.tt_famdir[2:5])
                nn = np.array(out["pad_normal"])
                out["pad_vn_err"] = round(float((pv - ve) @ nn), 3)
        if hasattr(sim, "tt_aim"):
            # feed-forward quality: the pad's normal against the aim law's and
            # its height against the ball's crossing, 0.40-0.50 s
            A = np.array(sim.tt_aim)
            w = (A[:, 0] >= 0.40) & (A[:, 0] <= 0.50)
            if w.any():
                angs = []
                for row in A[w]:
                    kk = int(np.argmin(np.abs(t - row[0])))
                    a = row[1:4] / np.linalg.norm(row[1:4])
                    angs.append(np.degrees(np.arccos(min(1.0, abs(float(a @ nrm[kk]))))))
                out["pose_angle_err"] = round(float(np.mean(angs)), 3)
                out["pose_height_err"] = round(float(np.mean(np.abs(A[w, 4]))), 4)
        if hasattr(sim, "tt_aim") and sim.tt_aim:
            out["aim_normal_last"] = [round(float(x), 3) for x in sim.tt_aim[-1][1:4]]
        if hasattr(sim, "tt_aim") and hit:
            a = [row for row in sim.tt_aim if row[0] <= t[k] + 1e-9]
            if a:
                out["aim_normal"] = [round(float(x), 3) for x in a[-1][1:4]]
                out["aim_height_err"] = round(float(a[-1][4]), 3)
        # effort from the muscles' activation states: mean squared, and the
        # challenge's act_reg magnitude (|act| / 273)
        out["effort_act"] = round(float(L[:, 28].mean()), 4)
        out["act_reg"] = round(float(L[:, 29].mean()), 5)
        # grip study: the pad normal's angle (sign-free) from the aim over 0.3-0.5 s
        tgt = np.array([0.975, 0.19, 0.10]) / np.linalg.norm([0.975, 0.19, 0.10])
        win = (t >= 0.3) & (t <= 0.5)
        if win.any():
            ang = np.degrees(np.arccos(np.clip(np.abs(nrm[win] @ tgt), 0, 1)))
            out["normal_err_deg"] = round(float(ang.mean()), 2)
        if getattr(sim, "tt_real", False):
            out.update(self.real_spin_metrics(sim, L))
        return out

    def real_spin_metrics(self, sim, L):
        """TT_REAL_SPIN: the true spin (world frame) the ball brings in and
        takes out, as signed topspin (+) / backspin (-) about the axis
        z x (its horizontal direction of travel), rad/s, and sidespin (about
        z); the return's speed and peak height. The air is removed here."""
        import mujoco
        mujoco.set_mjcb_control(None)
        _AERO.clear()
        t, ball, bvel, touch = L[:, 0], L[:, 1:4], L[:, 4:7], L[:, 19:25]
        W = np.array(sim.tt_ww)
        out = {}

        def top(k):
            vh = np.array([bvel[k, 0], bvel[k, 1], 0.0])
            n = np.linalg.norm(vh)
            if n < 1e-6:
                return 0.0
            return float(W[k] @ np.cross([0.0, 0.0, 1.0], vh / n))

        hit_idx = np.nonzero(touch[:, 0] > 0)[0]
        # the incoming ball: just before contact (or at its closest approach)
        if len(hit_idx):
            kin = max(hit_idx[0] - 1, 0)
        else:
            pad = L[:, 7:10]
            kin = int(np.argmin(np.linalg.norm(ball - pad, axis=1)))
        out["spin_in"] = [round(float(x), 2) for x in W[kin]]
        out["topspin_in"] = round(top(kin), 2)
        # the serve's spin after its table bounce (first own-half contact)
        bnc = np.nonzero(touch[:, 1] > 0)[0]
        if len(bnc):
            kb = min(bnc[0] + 2, len(L) - 1)
            out["topspin_bounce"] = round(top(kb), 2)
        if not len(hit_idx):
            return out
        k = hit_idx[0]
        j2 = k
        while j2 < len(L) - 1 and touch[j2, 0] > 0:
            j2 += 1
        ko = min(j2 + 2, len(L) - 1)
        out["spin_out"] = [round(float(x), 2) for x in W[ko]]
        out["topspin_out"] = round(top(ko), 2)
        out["sidespin_out"] = round(float(W[ko, 2]), 2)
        out["spin_out_mag"] = round(float(np.linalg.norm(W[ko])), 2)
        out["ret_speed"] = round(float(np.linalg.norm(bvel[ko])), 3)
        after = np.nonzero(touch[j2:, 1:].sum(axis=1) > 0)[0]
        end = j2 + after[0] if len(after) else len(L)
        out["ret_peak_z"] = round(float(ball[j2:max(end, j2 + 1), 2].max()), 3)
        return out

    def score(self, m):
        if os.environ.get("TT_OBJ") == "pose":
            drop = 10.0 if m.get("palm_err_max", 1.0) > 0.2 else 0.0
            fold = 5.0 * max(0.0, -0.05 - m.get("trunk_flex_end", -1.0))
            if os.environ.get("TT_POSE_OFF"):
                fold += 20.0 * abs(m.get("pad_offset", 9.0) - float(os.environ["TT_POSE_OFF"]))
            hw = float(os.environ.get("TT_POSE_HW", "50"))
            return (-(m.get("pose_angle_err", 90.0) + hw * m.get("pose_height_err", 1.0)) / 10.0 - drop - fold
                    - float(os.environ.get("TT_EFFORT_W", "0")) * m.get("effort_act", 0.0))
        if os.environ.get("TT_OBJ") == "grip":
            drop = 10.0 if m.get("palm_err_max", 1.0) > 0.2 else 0.0
            return -0.1 * m.get("normal_err_deg", 90.0) - drop - 0.5 * m.get("effort", 0.0)
        # success first; then how far inside the opponent's half the return
        # landed (its centre is (-0.69, 0.04), half-size 0.69 x 0.76), or how
        # close a miss came
        s = 10.0 * m.get("solved", 0.0) + 2.0 * m.get("hit", 0.0)
        xy = m.get("land_xy")
        if not m.get("hit"):
            s -= 5.0 * m.get("miss_dist", 1.0)
        elif xy:
            dx = abs(xy[0] + 0.69) / 0.69
            dy = abs(xy[1] - 0.04) / 0.76
            s -= min(3.0, max(dx, dy))
        else:
            s -= 3.0
        return s - float(os.environ.get("TT_EFFORT_W", "0.5")) * m.get("effort_act", m.get("effort", 0.0))

    def hud_text(self, m, d):
        ball = m.joint("pingpong_freejoint")
        bv = d.qvel[m.jnt_dofadr[ball.id]:m.jnt_dofadr[ball.id] + 3]
        pad = m.joint("paddle_freejoint")
        pv = d.qvel[m.jnt_dofadr[pad.id]:m.jnt_dofadr[pad.id] + 3]
        return f"ball {np.linalg.norm(bv):4.1f} m/s   paddle {np.linalg.norm(pv):4.1f} m/s"

    def title(self):
        return f"robolab MyoTT on MyoSuite {self.env_id}"

    def camera(self, m, d, cam):
        v = os.environ.get("TT_CAM", "broadcast")
        if v == "hand":
            cam.lookat[:] = d.geom_xpos[m.geom("pad").id]
            cam.distance = 0.55
            cam.azimuth = float(os.environ.get("TT_AZ", "150"))
            cam.elevation = -15
        elif v == "side":
            cam.lookat[:] = [1.9, 0.3, 1.0]
            cam.distance = 2.6
            cam.azimuth = 90
            cam.elevation = -10
        else:
            # broadcast: raised, behind and to the side of the player, down the table
            cam.lookat[:] = [0.75, 0.05, 1.0]
            cam.distance = 3.6
            cam.azimuth = 198
            cam.elevation = -17


TASK = MyoTTTask


# ---- evaluation report -----------------------------------------------------------

def wilson(k, n, z=1.96):
    """95% Wilson score interval for k successes in n trials."""
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    den = 1 + z * z / n
    c = (p + z * z / (2 * n)) / den
    h = z * np.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return (round(float(c - h), 4), round(float(c + h), 4))


def _episode(job):
    import sys
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    from myo_bridge import MyoSim
    params, seed, env_id = job
    task = MyoTTTask()
    task.env_id = env_id or MyoTTTask.env_id
    sim = MyoSim(task, params=params, seed=seed)
    res = sim.run()
    res["seed"] = seed
    return res


def evaluate(params, seeds, workers=2, env_id=None):
    import multiprocessing as mp
    with mp.Pool(workers) as pool:
        rows = pool.map(_episode, [(params, s, env_id) for s in seeds])
    n = len(rows)
    solved = sum(1 for r in rows if r.get("solved", 0) > 0)
    hit = sum(1 for r in rows if r.get("hit", 0) > 0)
    hits = [r for r in rows if r.get("hit", 0) > 0]

    def stat(key, rs):
        v = [r[key] for r in rs if r.get(key) is not None]
        if not v:
            return None
        return {"mean": round(float(np.mean(v)), 4), "sd": round(float(np.std(v)), 4),
                "min": round(float(np.min(v)), 4), "max": round(float(np.max(v)), 4)}
    summary = {
        "env": env_id or MyoTTTask.env_id, "episodes": n, "seeds": [int(seeds[0]), int(seeds[-1])],
        "success_rate": round(solved / n, 4), "success_ci95": wilson(solved, n),
        "hit_rate": round(hit / n, 4), "hit_ci95": wilson(hit, n),
        "paddle_speed_at_contact": stat("paddle_speed", hits),
        "t_contact": stat("t_contact", hits),
        "movement_onset_pelvis": stat("pelvis_onset", rows),
        "effort_mean_sq_activation": stat("effort_act", rows),
        "effort_command_mean_sq": stat("effort", rows),
        "act_reg": stat("act_reg", rows),
        "landed": {k: sum(1 for r in hits if r.get("landed") == k) for k in ("opponent", "own", "net", "ground", "env", None)},
        "miss_dist_of_misses": stat("miss_dist", [r for r in rows if not r.get("hit")]),
        "failures": failure_breakdown(rows),
    }
    if any("spin_err" in r for r in rows):
        summary["spin_err_rad_s"] = stat("spin_err", rows)
        for r in rows:
            if "spin_true_at_contact" in r:
                r["_wc"] = float(np.linalg.norm(r["spin_true_at_contact"]))
        summary["spin_true_at_contact_rad_s"] = stat("_wc", rows)
    if any("family" in r for r in rows):
        fams = sorted({r.get("family") for r in rows if r.get("family")})
        summary["families"] = {f: {"n": sum(1 for r in rows if r.get("family") == f),
                                   "hit": sum(1 for r in rows if r.get("family") == f and r.get("hit")),
                                   "solved": sum(1 for r in rows if r.get("family") == f and r.get("solved"))}
                               for f in fams}
        summary["stroke_dir_err_deg"] = stat("stroke_dir_err_deg", rows)
        summary["pad_normal_speed_err_m_s"] = stat("pad_vn_err", rows)
    return summary, rows


def failure_class(r):
    """The outcome class used in out/myo_tt_metrics.json's failure breakdowns."""
    if r.get("solved"):
        return "solved"
    if r.get("hit"):
        lab = r.get("landed")
        if lab == "own":
            return "hit: landed on own half"
        if lab == "net":
            return "hit: net"
        return "hit: out (long, wide or back)"
    mv, md = r.get("miss_vec", [0, 0, 0]), r.get("miss_dist", 9)
    if md < 0.10:
        return "miss: within 10 cm (rim/timing)"
    if abs(mv[1]) > abs(mv[2]):
        return "miss: lateral (out of reach)"
    return "miss: pad below the ball" if mv[2] > 0 else "miss: pad above the ball"


def failure_breakdown(rows):
    out = {}
    for r in rows:
        side = {1: "forehand", 2: "backhand"}.get(r.get("side"), "none")
        c = failure_class(r)
        out.setdefault(side, {})
        out[side][c] = out[side].get(c, 0) + 1
    return out


def render(params, seeds, env_id, slowmo, video, gif, sheet, gif_scale=0.4, gif_every=3):
    """Record consecutive serves, every control step, played back slowmo x slower."""
    from myo_bridge import MyoSim
    from render import Recorder
    frames, first, ep1 = [], None, None
    for seed in seeds:
        task = MyoTTTask()
        task.env_id = env_id or MyoTTTask.env_id
        sim = MyoSim(task, params=params, seed=seed)
        rec = Recorder(sim, fps=100, scene_option=task.scene_option())
        res = sim.run(recorder=rec)
        res["seed"] = seed
        print({k: res.get(k) for k in ("seed", "solved", "hit", "t_contact", "paddle_speed", "landed", "land_xy")})
        # hold the last frame a moment between serves
        frames += rec.frames + [rec.frames[-1]] * 15
        first = first or rec
        ep1 = ep1 or list(rec.frames)
    first.frames = frames
    first.fps = int(round(100 / slowmo))
    if video:
        first.write_mp4(video)
    if gif:
        first.write_gif(gif, scale=gif_scale, every=gif_every)
    if sheet:
        first.frames = ep1
        first.write_sheet(sheet)


def lff_learn(a, params):
    """Learn the feed-forward map (iterative learning across serves): run `k`
    fresh serves with the current weights, fit the servo's own correction at
    lock (what the feed-forward still lacked) on the serve's features by ridge
    regression, add `alpha` of it to the weights; repeat. Serves the pelvis
    cannot reach (lateral residual > 5 cm) are left out of the fit. The
    weights are checked on the held-out serves every `hold_every` rounds."""
    import json
    import multiprocessing as mp
    P = dict(params)
    P["lff"] = 1.0
    W = np.array([P.get(f"lff{i}", 0.0) for i in range(48)]).reshape(8, 6)
    rng = np.random.default_rng(a.seed * 7919 + 29)
    held = list(range(a.held0, a.held0 + a.held))
    best = (-1.0, None)

    def put(W):
        for i in range(48):
            P[f"lff{i}"] = float(np.clip(W.flat[i], -3.0, 3.0))

    with mp.Pool(a.workers) as pool:
        for it in range(a.gens):
            put(W)
            seeds = [int(v) for v in rng.integers(100000, 999999, a.k)]
            rows = pool.map(_episode, [(dict(P), sd, None) for sd in seeds], chunksize=1)
            F, Q = [], []
            for r in rows:
                if r.get("feat") and r.get("q_servo") and abs(r["feat"][5]) < 0.05:
                    F.append(r["feat"])
                    Q.append(r["q_servo"])
            row = {"it": it + 1, "solved": float(np.mean([r.get("solved", 0) for r in rows])),
                   "hit": float(np.mean([r.get("hit", 0) for r in rows])), "n_fit": len(F)}
            if len(F) >= 8:
                F, Q = np.array(F), np.array(Q)
                lam = a.ridge * len(F)
                dW = np.linalg.solve(F.T @ F + lam * np.eye(F.shape[1]), F.T @ Q).T
                W = W + a.alpha * dW
                row["servo_rms"] = float(np.sqrt(np.mean(Q ** 2)))
            if (it + 1) % a.hold_every == 0 or it + 1 == a.gens:
                put(W)
                hr = pool.map(_episode, [(dict(P), sd, None) for sd in held], chunksize=1)
                hs = float(np.mean([r.get("solved", 0) for r in hr]))
                row.update({"held_solved": hs, "held_hit": float(np.mean([r.get("hit", 0) for r in hr]))})
                if hs > best[0]:
                    best = (hs, dict(P))
                    with open(a.out, "w") as f:
                        f.write(f"# myo_tt learned feed-forward, round {it + 1}: held-out {len(held)} serves "
                                f"({a.held0}..) solved {hs:.3f}\n")
                        for k2 in sorted(P):
                            if not k2.startswith("__"):
                                f.write(f"{k2} {float(P[k2])!r}\n")
            print(json.dumps({k2: (round(v, 3) if isinstance(v, float) else v) for k2, v in row.items()}), flush=True)
    print("best held-out solved", best[0])


def practice(a, params):
    """Practice on FRESH serves: every generation draws `k` new training seeds
    (shared by its candidates, so they are ranked on the same serves), so no
    fixed set of serves can be overfitted; every `hold_every` generations the
    optimizer's mean (CMA / sep-CMA) or incumbent is scored on a fixed
    held-out set, and the best held-out parameters are kept."""
    import json
    import multiprocessing as mp
    import search
    names = [n.strip() for n in a.only.split(",")]
    tun = search.describe("myo_tt", fixed=params)
    rep = search.BoxRep.from_tunables(tun, only=names, init=params)
    opt = search.make_optimizer(a.method, rep.x0, a.sigma, a.seed, **({"popsize": a.pop} if a.pop else {}))
    rng = np.random.default_rng(a.seed * 7919 + 13)
    held = list(range(a.held0, a.held0 + a.held))
    best = (-1e18, None, None)
    log = open(a.log, "w") if a.log else None

    def score_of(res):
        return float(np.mean([r[0] for r in res]))

    def hold_out(pool, x):
        p = rep.decode(x)
        res = pool.map(search.rollout, [("myo_tt", p, sd, 0.0) for sd in held], chunksize=1)
        m = [r[1] for r in res]
        return score_of(res), float(np.mean([mm.get("solved", 0) for mm in m])), float(np.mean([mm.get("hit", 0) for mm in m])), p

    with mp.Pool(a.workers) as pool:
        for g in range(a.gens):
            seeds = [int(v) for v in rng.integers(100000, 999999, a.k)]
            X = np.atleast_2d(opt.ask())
            jobs = [("myo_tt", rep.decode(np.clip(x, 0, 1)), sd, 0.0) for x in X for sd in seeds]
            res = pool.map(search.rollout, jobs, chunksize=1)
            scores, solved = [], []
            for i in range(len(X)):
                r = res[i * a.k:(i + 1) * a.k]
                scores.append(score_of(r))
                solved.append(float(np.mean([rr[1].get("solved", 0) for rr in r])))
            opt.tell(X, scores, None)
            row = {"gen": g + 1, "seeds": seeds, "gen_best": max(scores), "gen_median": float(np.median(scores)),
                   "gen_best_solved": solved[int(np.argmax(scores))], "pop_solved": float(np.mean(solved)),
                   "info": opt.info()}
            if (g + 1) % a.hold_every == 0 or g + 1 == a.gens:
                x = getattr(opt, "mean", None)
                if x is None:
                    x = getattr(getattr(opt, "es", None), "mean", None)
                if x is None:
                    x = X[int(np.argmax(scores))]
                hs, hsol, hhit, p = hold_out(pool, np.clip(x, 0, 1))
                row.update({"held_score": hs, "held_solved": hsol, "held_hit": hhit})
                if hs > best[0]:
                    best = (hs, p, (hsol, hhit))
                    with open(a.out, "w") as f:
                        f.write(f"# myo_tt practice ({a.method}, fresh seeds x{a.k}/gen), gen {g + 1}: held-out "
                                f"{len(held)} serves ({a.held0}..): score {hs:.3f}, solved {hsol:.3f}, hit {hhit:.3f}\n")
                        for k2 in sorted(p):
                            if not k2.startswith("__"):
                                f.write(f"{k2} {float(p[k2])!r}\n")
            print(json.dumps({k2: (round(v, 3) if isinstance(v, float) else v) for k2, v in row.items() if k2 != "seeds"}), flush=True)
            if log:
                log.write(json.dumps(row, default=float) + "\n")
                log.flush()
    print("best held-out", best[0], best[2])


if __name__ == "__main__":
    import argparse
    import json
    import sys
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap = argparse.ArgumentParser(description="Evaluate MyoTT over seeded episodes")
    ap.add_argument("--params")
    ap.add_argument("--episodes", type=int, default=100)
    ap.add_argument("--seed0", type=int, default=1000)
    ap.add_argument("--seeds", default="", help="comma-separated seeds (render / evaluate these instead of a range)")
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--set", default="", help="extra params name=value,...")
    ap.add_argument("--out")
    ap.add_argument("--render", type=int, default=0, help="record this many episodes (slow motion) instead")
    ap.add_argument("--slowmo", type=float, default=3.0)
    ap.add_argument("--gif_scale", type=float, default=0.4)
    ap.add_argument("--gif_every", type=int, default=3)
    ap.add_argument("--video")
    ap.add_argument("--gif")
    ap.add_argument("--sheet")
    ap.add_argument("--env", help="P1 or P2 (default: TT_ENV)")
    ap.add_argument("--practice", action="store_true", help="practise on fresh seeds (see practice())")
    ap.add_argument("--lff_learn", action="store_true", help="learn the feed-forward map (see lff_learn())")
    ap.add_argument("--alpha", type=float, default=0.6)
    ap.add_argument("--ridge", type=float, default=0.02)
    ap.add_argument("--only", default="")
    ap.add_argument("--method", default="cma")
    ap.add_argument("--sigma", type=float, default=0.12)
    ap.add_argument("--pop", type=int, default=0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--gens", type=int, default=30)
    ap.add_argument("--k", type=int, default=8, help="fresh training serves per generation")
    ap.add_argument("--held", type=int, default=48)
    ap.add_argument("--held0", type=int, default=80000)
    ap.add_argument("--hold_every", type=int, default=3)
    ap.add_argument("--log")
    a = ap.parse_args()
    params = {}
    if a.params:
        for line in open(a.params):
            parts = line.split()
            if len(parts) >= 2 and not line.startswith("#"):
                params[parts[0]] = float(parts[1])
    for kv in filter(None, a.set.split(",")):
        k, v = kv.split("=")
        params[k] = float(v)
    env_id = f"myoChallengeTableTennis{a.env}-v0" if a.env else None
    if a.practice:
        practice(a, params)
        sys.exit(0)
    if a.lff_learn:
        lff_learn(a, params)
        sys.exit(0)
    listed = [int(x) for x in a.seeds.split(",") if x.strip()]
    if a.render:
        render(params, listed or list(range(a.seed0, a.seed0 + a.render)), env_id, a.slowmo, a.video, a.gif, a.sheet,
               a.gif_scale, a.gif_every)
        sys.exit(0)
    summary, rows = evaluate(params, listed or list(range(a.seed0, a.seed0 + a.episodes)), a.workers, env_id)
    print(json.dumps(summary, indent=1))
    if a.out:
        json.dump({"summary": summary, "params": params, "episodes": rows}, open(a.out, "w"), indent=1)
