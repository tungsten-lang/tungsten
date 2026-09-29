"""Series-elastic tendon validation for the v3 anatomy (HumanoidV3Builder).

Two tools:

  ElasticProbe   per-physics-step bookkeeping of every plantarflexor and knee
                 extensor muscle-tendon unit (MTU): tendon force and energy,
                 and the power of the tendon, the fibre and the whole MTU.
                 Works on v3 (elastic) and v2 (rigid: tendon terms are zero,
                 fibre = MTU) bodies alike.
  hop            two-legged hopping in place (root x and pitch locked, so only
                 the vertical bounce is tested) under a simple spinal
                 controller: positive force feedback on the soleus,
                 gastrocnemius and vasti in stance (Geyer, Seyfarth & Blickhan
                 2003), a push-off burst once the body starts rising, joint PD
                 servos (through the muscles) everywhere else. The same
                 controller and inputs run on the rigid (v2) and elastic (v3)
                 bodies.

Sign conventions: lengths shorten with contraction; a power is positive when
the element delivers work (shortens under tension). Units: an MTU's length is
in its muscle's units (radians of its joint at coef 1) and its force a torque
(N m), so work and energy come out in J.

    .venv/bin/python playground/tendon_v3.py hop --out out/tendon_v3_hop.json
    .venv/bin/python playground/tendon_v3.py stance run_v3 params/run_v3.txt --out out/run_v3_tendon.json
"""

import argparse
import json
import math
import os
import sys

import mujoco
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from body import HumanoidV2Builder, HumanoidV3Builder, scene_xml, settle_fibers  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROBED = ("ankle_pos", "gas", "knee_neg", "rf")
GROUP = {"ankle_pos": "achilles", "gas": "achilles", "knee_neg": "quadriceps", "rf": "quadriceps"}


class ElasticProbe:
    """Tendon / fibre / MTU power of the probed muscles, integrated per step."""

    def __init__(self, m, sides=("l", "r")):
        self.units = []
        for side in sides:
            for suffix in PROBED:
                name = f"{side}_{suffix}"
                a = mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_ACTUATOR, name)
                if a < 0:
                    continue
                t = mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_TENDON, f"{name}_see")
                K = float(m.tendon_stiffness[t]) if t >= 0 else 0.0
                self.units.append({"name": name, "side": side, "group": GROUP[suffix], "act": a, "see": t, "K": K})
        self.n = len(self.units)
        self.rows = []  # per step: t, then per unit (F_T, E_T, P_T, P_F, P_MTU, F_M)

    def sample(self, d):
        out = [d.time]
        for u in self.units:
            F_M = -float(d.actuator_force[u["act"]])
            v_F = float(d.actuator_velocity[u["act"]])
            if u["see"] >= 0:
                L_T = float(d.ten_length[u["see"]])
                v_T = float(d.ten_velocity[u["see"]])
                F_T = u["K"] * max(0.0, L_T)
                E_T = 0.5 * u["K"] * max(0.0, L_T) ** 2
                P_T = -F_T * v_T if L_T > 0 else 0.0
                P_MTU = -F_T * (v_T + v_F)
            else:
                F_T, E_T, P_T = F_M, 0.0, 0.0
                P_MTU = -F_M * v_F
            P_F = -F_M * v_F
            out += [F_T, E_T, P_T, P_F, P_MTU, F_M]
        self.rows.append(out)

    def array(self):
        return np.array(self.rows)

    def window(self, a, b, groups=("achilles", "quadriceps"), sides=("l", "r")):
        """Work and energy of the probed units between times a and b, summed per group."""
        R = self.array()
        t = R[:, 0]
        w = (t >= a) & (t <= b)
        if np.count_nonzero(w) < 3:
            return {}
        dt = np.diff(t, prepend=t[0])
        out = {}
        for g in groups:
            sel = [k for k, u in enumerate(self.units) if u["group"] == g and u["side"] in sides]
            if not sel:
                continue
            col = lambda k, j: R[w, 1 + 6 * k + j]  # noqa: E731
            E = sum(col(k, 1) for k in sel)
            P_T = sum(col(k, 2) for k in sel)
            P_F = sum(col(k, 3) for k in sel)
            P_M = sum(col(k, 4) for k in sel)
            F = sum(col(k, 0) for k in sel)
            dw = dt[w]
            pos = lambda p: float(np.sum(np.maximum(p, 0.0) * dw))  # noqa: E731
            neg = lambda p: float(np.sum(np.minimum(p, 0.0) * dw))  # noqa: E731
            mtu_pos = pos(P_M)
            # the tendon's part of the MTU's positive work: while the MTU delivers
            # work (P_MTU = P_T + P_fibre > 0), recoil power up to P_MTU (recoil that
            # instead stretches the fibre is not work done on the skeleton)
            recoil_in_push = float(np.sum(np.clip(P_T, 0.0, np.maximum(P_M, 0.0)) * dw))
            out[g] = {
                "peak_tendon_energy_J": round(float(np.max(E)), 2),
                "tendon_stored_J": round(-neg(P_T), 2),
                "tendon_returned_J": round(pos(P_T), 2),
                "fibre_positive_J": round(pos(P_F), 2),
                "fibre_negative_J": round(neg(P_F), 2),
                "mtu_positive_J": round(mtu_pos, 2),
                "mtu_negative_J": round(neg(P_M), 2),
                "tendon_part_of_mtu_positive_J": round(recoil_in_push, 2),
                "tendon_share_of_mtu_positive": round(recoil_in_push / mtu_pos, 3) if mtu_pos > 1e-6 else None,
                "peak_force_Nm": round(float(np.max(F)), 1),
            }
        return out


# ---- hopping in place ----------------------------------------------------------------


def hop_model(elastic, timestep, stiffness_scale=1.0):
    b = (HumanoidV3Builder("planar", stiffness_scale=stiffness_scale) if elastic
         else HumanoidV2Builder("planar"))
    lock = ('<joint joint1="root_x" polycoef="0 0 0 0 0"/>'
            '<joint joint1="root_pitch" polycoef="0 0 0 0 0"/>')
    xml = scene_xml(b, extra_equality=lock, timestep=timestep)
    m = mujoco.MjModel.from_xml_string(xml)
    return b, m


class Hopper:
    """Positive-force-feedback hopping controller acting through the muscles."""

    def __init__(self, b, m, G=1.2, a_pre=0.12, a_push=0.35, delay=0.015, hold=None):
        self.m, self.b = m, b
        self.names = [mu.name for mu in b.spec.muscles]
        self.ids = [m.actuator(n).id for n in self.names]
        self.idx = {n: k for k, n in enumerate(self.names)}
        self.peak = np.array([mu.peak for mu in b.spec.muscles])
        self.G, self.a_pre, self.a_push, self.delay = G, a_pre, a_push, delay
        self.hold = hold or {"spine_flex": 0.0, "l_shoulder_flex": 0.0, "r_shoulder_flex": 0.0,
                             "l_elbow": 0.4, "r_elbow": 0.4, "l_hip_flex": 0.08, "r_hip_flex": 0.08,
                             "l_toe": 0.0, "r_toe": 0.0}
        self.hist = []  # (t, muscle forces)
        self.floor = m.geom("floor").id
        self.feet = {m.geom(n).id for n in ("l_foot", "r_foot", "l_toes", "r_toes")}
        self.push = False
        self.stance = False

    def grf(self, d):
        f6 = np.zeros(6)
        tot = 0.0
        for i in range(d.ncon):
            c = d.contact[i]
            if (c.geom1 == self.floor and c.geom2 in self.feet) or (c.geom2 == self.floor and c.geom1 in self.feet):
                mujoco.mj_contactForce(self.m, d, i, f6)
                tot += abs(f6[0])
        return tot

    def servo(self, d, a, joint, q_star, kp=4.0, kd=0.3, tone=0.08):
        q = d.joint(joint).qpos[0]
        qd = d.joint(joint).qvel[0]
        u = kp * (q_star - q) - kd * qd
        a[self.idx[joint + "_pos"]] = np.clip(tone + u, 0, 1)
        a[self.idx[joint + "_neg"]] = np.clip(tone - u, 0, 1)

    def control(self, d):
        F = -d.actuator_force[self.ids] / self.peak
        self.hist.append((d.time, F.copy()))
        while len(self.hist) > 2 and self.hist[1][0] <= d.time - self.delay:
            self.hist.pop(0)
        Fd = self.hist[0][1]
        grf = self.grf(d)
        stance = grf > 30.0
        vz = d.joint("root_z").qvel[0]
        if stance and not self.stance:
            self.push = False
        if stance and vz > 0.0:
            self.push = True
        self.stance = stance
        a = np.zeros(len(self.ids))
        for j, q in self.hold.items():
            self.servo(d, a, j, q)
        for side in ("l", "r"):
            ext = [f"{side}_ankle_pos", f"{side}_gas", f"{side}_knee_neg"]
            for n in ext:
                k = self.idx[n]
                if stance:
                    a[k] = self.a_pre + self.G * Fd[k] + (self.a_push if self.push else 0.0)
                else:
                    a[k] = self.a_pre
            # antagonists quiet; knee and ankle flexors hold a landing posture in flight
            if not stance:
                self.servo(d, a, f"{side}_knee", 0.25, kp=2.0, tone=0.0)
                self.servo(d, a, f"{side}_ankle", 0.15, kp=2.0, tone=0.0)
                a[self.idx[f"{side}_knee_neg"]] = max(a[self.idx[f"{side}_knee_neg"]], self.a_pre)
                a[self.idx[f"{side}_ankle_pos"]] = max(a[self.idx[f"{side}_ankle_pos"]], self.a_pre)
            else:
                a[self.idx[f"{side}_knee_pos"]] = 0.0
                a[self.idx[f"{side}_ankle_neg"]] = 0.0
            a[self.idx[f"{side}_rf"]] = 0.05
            a[self.idx[f"{side}_ham"]] = 0.05
        d.ctrl[self.ids] = np.clip(a, 0, 1)
        return stance, grf


def hop(elastic=True, timestep=0.001, seconds=6.0, drop=0.10, control_dt=0.002, stiffness_scale=1.0, **ctl):
    b, m = hop_model(elastic, timestep, stiffness_scale)
    d = mujoco.MjData(m)
    d.qpos[m.joint("root_z").qposadr[0]] = drop
    for side in ("l", "r"):
        d.qpos[m.joint(f"{side}_knee").qposadr[0]] = 0.25
        d.qpos[m.joint(f"{side}_ankle").qposadr[0]] = 0.15
        d.qpos[m.joint(f"{side}_hip_flex").qposadr[0]] = 0.08
    settle_fibers(m, d)
    h = Hopper(b, m, **ctl)
    probe = ElasticProbe(m)
    sub = max(1, round(control_dt / timestep))
    pel = m.body("pelvis").id
    rec = []  # t, stance, grf, com_z
    while d.time < seconds:
        stance, grf = h.control(d)
        for _ in range(sub):
            mujoco.mj_step(m, d)
            probe.sample(d)
        rec.append((d.time, stance, grf, float(d.subtree_com[pel][2]), float(np.mean(d.act ** 2))))
        if not np.all(np.isfinite(d.qpos)):
            return {"error": "diverged", "t": d.time}
    return summarize_hops(m, rec, probe, seconds)


def drop_jump(elastic=True, timestep=0.001, drop=0.30, control_dt=0.002, stiffness_scale=1.0, **ctl):
    """One drop jump: the body falls `drop` m (feet first, legs in the landing
    posture) onto the floor, lands and rebounds under the hopping controller;
    measured over the ground contact: rebound height (COM apex after take-off
    minus COM at touchdown), contact time, and the MTU energetics."""
    b, m = hop_model(elastic, timestep, stiffness_scale)
    d = mujoco.MjData(m)
    d.qpos[m.joint("root_z").qposadr[0]] = drop
    for side in ("l", "r"):
        d.qpos[m.joint(f"{side}_knee").qposadr[0]] = 0.25
        d.qpos[m.joint(f"{side}_ankle").qposadr[0]] = 0.15
        d.qpos[m.joint(f"{side}_hip_flex").qposadr[0]] = 0.08
    settle_fibers(m, d)
    h = Hopper(b, m, **ctl)
    probe = ElasticProbe(m)
    sub = max(1, round(control_dt / timestep))
    pel = m.body("pelvis").id
    td = to = cand = None
    z_td = apex = None
    while d.time < 2.0:
        stance, grf = h.control(d)
        for _ in range(sub):
            mujoco.mj_step(m, d)
            probe.sample(d)
        z = float(d.subtree_com[pel][2])
        if td is None:
            if stance:
                td, z_td = d.time, z
        elif to is None:
            # take-off: the feet leave the ground rising and stay off for 20 ms
            # (a foot rocking off for a few ms mid-stance is not a take-off)
            if stance:
                cand = None
            elif cand is None and d.joint("root_z").qvel[0] > 0:
                cand, apex = d.time, z
            elif cand is not None:
                apex = max(apex, z)
                if d.time - cand >= 0.02:
                    to = cand
        else:
            if stance:
                break
            apex = max(apex, z)
        if not np.all(np.isfinite(d.qpos)):
            return {"error": "diverged"}
    if to is None:
        return {"note": "no take-off"}
    w = probe.window(td, to)
    return {"contact_time_s": round(to - td, 3), "rebound_m": round(apex - z_td, 3),
            "tendon_returned_J": round(sum(w[g]["tendon_returned_J"] for g in w), 2),
            "fibre_positive_J": round(sum(w[g]["fibre_positive_J"] for g in w), 2),
            "mtu_positive_J": round(sum(w[g]["mtu_positive_J"] for g in w), 2),
            "tendon_share_of_mtu_positive": round(sum(w[g]["tendon_part_of_mtu_positive_J"] for g in w)
                                                  / max(1e-9, sum(w[g]["mtu_positive_J"] for g in w)), 3),
            "achilles": w.get("achilles"), "quadriceps": w.get("quadriceps")}


def summarize_hops(m, rec, probe, seconds, last=5):
    t = np.array([r[0] for r in rec])
    st = np.array([r[1] for r in rec])
    grf = np.array([r[2] for r in rec])
    z = np.array([r[3] for r in rec])
    eff = np.array([r[4] for r in rec])
    on = [t[k] for k in range(1, len(t)) if st[k] and not st[k - 1]]
    off = [t[k] for k in range(1, len(t)) if not st[k] and st[k - 1]]
    stances = []
    for a in on:
        b = [x for x in off if x > a]
        if b:
            stances.append((a, b[0]))
    weight = float(sum(m.body_mass[1:])) * 9.81
    out = {"hops": len(stances)}
    if len(stances) < last + 2:
        out["note"] = "fewer hops than requested"
        return out
    use = stances[-last - 1:-1]
    cyc = [(s[0], n[0]) for s, n in zip(use, stances[-last:])]
    out["contact_time_s"] = round(float(np.mean([b - a for a, b in use])), 3)
    out["hop_period_s"] = round(float(np.mean([b - a for a, b in cyc])), 3)
    apex = []
    for a, b in cyc:
        w = (t >= a) & (t < b)
        apex.append(float(np.max(z[w])))
    td = [float(np.interp(a, t, z)) for a, _ in cyc]
    out["com_apex_m"] = round(float(np.mean(apex)), 3)
    out["apex_above_touchdown_m"] = round(float(np.mean(np.array(apex) - np.array(td))), 3)
    out["peak_grf_bw"] = round(float(np.mean([np.max(grf[(t >= a) & (t <= b)]) for a, b in use])) / weight, 2)
    out["effort_msa"] = round(float(np.mean(eff[(t >= cyc[0][0]) & (t < cyc[-1][1])])), 4)
    # tendon energetics per hop cycle (touchdown to touchdown: a closed cycle, so a
    # lossless tendon returns what it stores) and within the stance alone
    def mean_windows(wins):
        per = [probe.window(a, b) for a, b in wins]
        agg = {}
        for g in per[0]:
            agg[g] = {k: round(float(np.mean([p[g][k] for p in per if p[g][k] is not None])), 3)
                      for k in per[0][g] if per[0][g][k] is not None}
        return agg
    out["per_cycle"] = mean_windows(cyc)
    out["per_stance"] = mean_windows(use)
    pc = out["per_cycle"]
    tot_mtu = sum(pc[g]["mtu_positive_J"] for g in pc)
    rec = sum(pc[g]["tendon_part_of_mtu_positive_J"] for g in pc)
    out["tendon_share_of_mtu_positive_all"] = round(rec / tot_mtu, 3) if tot_mtu > 0 else None
    out["tendon_returned_per_cycle_J"] = round(sum(pc[g]["tendon_returned_J"] for g in pc), 2)
    out["fibre_positive_per_cycle_J"] = round(sum(pc[g]["fibre_positive_J"] for g in pc), 2)
    return out


# ---- running / jumping stance energetics ------------------------------------------------


def stance_energetics(task_name, params_path, seconds, seed=None, last=5.0, env=None):
    """Run a task with the probe attached; per foot stance in the last `last`
    seconds, the Achilles and quadriceps energetics of the stance leg, plus the
    ankle joint's positive work."""
    for k, v in (env or {}).items():
        os.environ[k] = v
    import importlib
    from bridge import Sim
    from practice import read_params
    task = importlib.import_module(f"tasks.{task_name}").TASK()
    if seed is not None:
        task.seed = seed
    sim = Sim(task, params=read_params(params_path))
    probe = ElasticProbe(sim.m)
    m = sim.m
    feet = {"l": {m.geom("l_foot").id, m.geom("l_toes").id}, "r": {m.geom("r_foot").id, m.geom("r_toes").id}}
    floor = {g for g in range(m.ngeom) if m.geom(g).name in ("floor", "runway", "pit", "far_ground")}
    contact_log = []
    joints = {s: {j: m.joint(f"{s}_{j}") for j in ("ankle", "knee")} for s in ("l", "r")}
    jlog = []
    orig = task.before_step

    def before_step(mm, dd):
        orig(mm, dd)
        on = {"l": False, "r": False}
        for i in range(dd.ncon):
            c = dd.contact[i]
            for g1, g2 in ((c.geom1, c.geom2), (c.geom2, c.geom1)):
                if g2 in floor:
                    for s in on:
                        if g1 in feet[s]:
                            on[s] = True
        contact_log.append((dd.time, on["l"], on["r"]))
        probe.sample(dd)
        # joint power of the ankle and knee from all actuators and passive forces
        row = [dd.time]
        for s in ("l", "r"):
            for j in ("ankle", "knee"):
                jj = joints[s][j]
                dof = jj.dofadr[0]
                tau = dd.qfrc_actuator[dof] + dd.qfrc_passive[dof]
                row.append(tau * dd.qvel[dof])
        jlog.append(row)

    task.before_step = before_step
    metrics = sim.run(seconds)
    t = np.array([c[0] for c in contact_log])
    J = np.array(jlog)
    T = t[-1]
    out = {"task": task_name, "params": params_path, "seconds": seconds, "seed": seed,
           "metrics": {k: metrics.get(k) for k in ("distance", "steady_speed", "speed_last5", "t_100m", "fell",
                                                    "contact_time", "official_m", "effective_m", "takeoff_vx",
                                                    "takeoff_vz", "contact_time_s")}}
    per = []
    for si, s in enumerate(("l", "r")):
        c = np.array([x[1 + si] for x in contact_log])
        # stances: contact intervals, merging gaps under 20 ms (the foot box and
        # toe segment rocking on the ground split a stance into flickers)
        spans, a0, last_on = [], None, None
        for k in range(len(t)):
            if c[k]:
                if a0 is None:
                    a0 = t[k]
                elif last_on is not None and t[k] - last_on > 0.02:
                    spans.append((a0, last_on))
                    a0 = t[k]
                last_on = t[k]
        if a0 is not None and last_on < t[-1]:
            spans.append((a0, last_on))
        for a, b in spans:
            if a < T - last or b - a < 0.05:
                continue
            w = probe.window(a, b, sides=(s,))
            ww = (J[:, 0] >= a) & (J[:, 0] <= b)
            dtj = np.diff(J[:, 0], prepend=J[0, 0])[ww]
            col = 1 + 2 * si
            w["ankle_joint_positive_J"] = round(float(np.sum(np.maximum(J[ww, col], 0) * dtj)), 2)
            w["knee_joint_positive_J"] = round(float(np.sum(np.maximum(J[ww, col + 1], 0) * dtj)), 2)
            w["contact_s"] = round(b - a, 3)
            per.append(w)
    to = getattr(task, "takeoff", None)
    if to is not None and to.get("touch"):
        # a jump task: the take-off stance (board touchdown to the last runway contact)
        s = to["foot"]
        a, b = to["touch"]["t"], to["t"]
        w = probe.window(a, b, sides=(s,))
        ww = (J[:, 0] >= a) & (J[:, 0] <= b)
        dtj = np.diff(J[:, 0], prepend=J[0, 0])[ww]
        col = 1 + 2 * ("l", "r").index(s)
        w["ankle_joint_positive_J"] = round(float(np.sum(np.maximum(J[ww, col], 0) * dtj)), 2)
        w["knee_joint_positive_J"] = round(float(np.sum(np.maximum(J[ww, col + 1], 0) * dtj)), 2)
        w["contact_s"] = round(b - a, 3)
        out["takeoff_stance"] = w
        return out
    out["stances"] = len(per)
    if per:
        agg = {}
        for g in ("achilles", "quadriceps"):
            if g in per[0]:
                agg[g] = {key: round(float(np.mean([p[g][key] for p in per if p[g].get(key) is not None])), 3)
                          for key in per[0][g] if per[0][g][key] is not None}
        agg["ankle_joint_positive_J"] = round(float(np.mean([p["ankle_joint_positive_J"] for p in per])), 2)
        agg["knee_joint_positive_J"] = round(float(np.mean([p["knee_joint_positive_J"] for p in per])), 2)
        agg["contact_s"] = round(float(np.mean([p["contact_s"] for p in per])), 3)
        if "achilles" in agg and agg["ankle_joint_positive_J"] > 0:
            agg["achilles_recoil_share_of_ankle_positive_work"] = round(
                agg["achilles"]["tendon_returned_J"] / agg["ankle_joint_positive_J"], 3)
        out["per_stance_mean"] = agg
    return out


def validate():
    """The hop validation: the same spinal controller on the rigid and the
    elastic body (pure positive force feedback, and PFF plus a push burst),
    the elastic body at 0.5 / 1 / 2 ms, and at 0.5x / 2x tendon stiffness."""
    keys = ("hops", "contact_time_s", "hop_period_s", "apex_above_touchdown_m", "peak_grf_bw", "effort_msa",
            "tendon_returned_per_cycle_J", "fibre_positive_per_cycle_J", "tendon_share_of_mtu_positive_all")
    pick = lambda r: {k: r.get(k) for k in keys} | {"achilles_per_cycle": r.get("per_cycle", {}).get("achilles"),  # noqa: E731
                                                     "quadriceps_per_cycle": r.get("per_cycle", {}).get("quadriceps")}
    ctls = {"pff": {"G": 2.0, "a_pre": 0.05, "a_push": 0.0}, "pff_push": {"G": 1.6, "a_pre": 0.05, "a_push": 0.2}}
    out = {"controllers": ctls, "seconds": 6.0, "means_over": "the last 5 hop cycles (touchdown to touchdown)"}
    for cname, c in ctls.items():
        out[cname] = {"rigid_v2": pick(hop(False, 0.001, 6.0, **c)), "elastic_v3": pick(hop(True, 0.001, 6.0, **c))}
    out["drop_jump_30cm"] = {cname: {body: {str(dt): drop_jump(el, dt, **c) for dt in (0.00025, 0.0005, 0.001, 0.002)}
                                     for body, el in (("rigid_v2", False), ("elastic_v3", True))}
                             for cname, c in ctls.items()}
    c = ctls["pff"]
    out["timestep_check_pff_elastic"] = {str(dt): pick(hop(True, dt, 6.0, **c)) for dt in (0.0005, 0.001, 0.002)}
    out["stiffness_check_pff_elastic"] = {str(k): pick(hop(True, 0.001, 6.0, stiffness_scale=k, **c))
                                          for k in (0.5, 1.0, 2.0)}
    return out


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    h = sub.add_parser("hop")
    h.add_argument("--seconds", type=float, default=6.0)
    h.add_argument("--timestep", type=float, default=0.001)
    h.add_argument("--G", type=float, default=1.2)
    h.add_argument("--a_pre", type=float, default=0.12)
    h.add_argument("--a_push", type=float, default=0.35)
    h.add_argument("--out")
    v = sub.add_parser("validate", help="the hop validation set: rigid vs elastic, timestep and stiffness checks")
    v.add_argument("--out")
    s = sub.add_parser("stance")
    s.add_argument("task")
    s.add_argument("params")
    s.add_argument("--seconds", type=float, default=20.0)
    s.add_argument("--seed", type=int)
    s.add_argument("--out")
    a = ap.parse_args()
    if a.cmd == "hop":
        res = {}
        for label, el in (("rigid_v2", False), ("elastic_v3", True)):
            res[label] = hop(el, a.timestep, a.seconds, G=a.G, a_pre=a.a_pre, a_push=a.a_push)
        res["controller"] = {"G": a.G, "a_pre": a.a_pre, "a_push": a.a_push, "timestep": a.timestep}
    elif a.cmd == "validate":
        res = validate()
    else:
        res = stance_energetics(a.task, a.params, a.seconds, a.seed)
    print(json.dumps(res, indent=1))
    if a.out:
        with open(a.out, "w") as f:
            json.dump(res, f, indent=1)


if __name__ == "__main__":
    main()
