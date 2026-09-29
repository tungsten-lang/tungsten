"""MyoChallenge 2023 Relocate on the phase-2 EVALUATION environment
(myoChallengeRelocateP2eval-v0, as myo_relocate_eval) for the round-6 skill
(MyoRelocateV6Skill, bin/robolab_myo_relocate_v6), with the round-5
diagnostics (tasks/myo_relocate_v5.py) plus the eval env's randomisation.

The receptacle the physics steps is not the one the observation shows. In
MyoSuite 2.12.2 the env keeps two MjData: `env.mj_data` (observed and scored;
its mocap receptacle stays at the model's (0, -0.25, 0.9)) and
`env.robot.mj_data` (the one mj_step advances; its qpos is copied back each
step), whose mocap receptacle sits at the pose reset() draws from
target_xyz_range / target_rxryrz_range (eval: x -0.5..0.4, y -0.5..-0.1,
z 0.9..1.1, tilted up to 0.3 rad; P2: x 0..0.3, y -0.45..-0.1, z 0.9..1.05).
So an invisible 20 x 20 cm box with 20 cm walls stands at a random place in
the workspace: the arm and the object collide with it, the goal test uses the
visible one. Diagnostics below record where it stands and when it is hit.

RELOC6_ENV=p2 runs the same task on the P2 environment
(myoChallengeRelocateP2-v0), for like-for-like diagnostics. (The eval env's
"more initial joint noise" is not random: MyoSuite 2.12.2 starts every
episode at init_qpos + 0.015 x each joint's range, against 0.01 on P2, so the
arm starts from one fixed, slightly different posture.)

Extra diagnostics (metrics; never sensed by the controller):
  mass       the object's mass (kg; 50-300 g on the eval env, 50-200 g on P2)
  gmax       the largest geom half-size (m; up to 3.5 cm, P2 2.5 cm)
  vol        the three primitives' summed bounding-box volume (cm^3)
  fric       sliding friction of the object's geoms
  z0         the object's resting height after the drop (site z at 0.3 s)
  x_set, y_set  where the object's site is at 0.35 s, after the drop
  roll       how far it moved (xy) from its start by then: the drop bounces
             and rolls the eval env's larger objects
  push       how far the object's site moved (xy) between the start of the
             descend and the close: the pinch pushing it away
  ghost_x/y/z   the physical (invisible) receptacle's position
  t_ghost_arm   when the arm or hand first touched it (-1: never)
  t_ghost_obj   when the object first touched it (-1: never)
  slip_z     the held object's drop relative to the palm during lift and carry
             (m: palm-object z gap growth while touching)
"""

import json
import os

import numpy as np

from tasks.myo_relocate import cache, episode_store, hand_touch
from tasks.myo_relocate_v5 import MyoRelocateV5Task

ENV_EVAL = "myoChallengeRelocateP2eval-v0"
ENV_P2 = "myoChallengeRelocateP2-v0"


def ghost_contacts(sim, ep, c):
    """The physical receptacle (the robot's MjData, see the module doc): its
    pose once, and the first time the arm or hand, and the object, touch it."""
    rd = getattr(getattr(sim.u, "robot", None), "mj_data", None)
    if rd is None:
        return
    m = sim.m
    tb = m.body("target").id
    if "ghost" not in ep:
        ep["ghost"] = np.array(rd.mocap_pos[m.body_mocapid[tb]], dtype=float)
    t = float(rd.time)
    for i in range(rd.ncon):
        con = rd.contact[i]
        b1, b2 = m.geom_bodyid[con.geom1], m.geom_bodyid[con.geom2]
        if b1 == tb:
            other = b2
        elif b2 == tb:
            other = b1
        else:
            continue
        if other == c.obj_body:
            ep.setdefault("t_ghost_obj", t)
        elif other != 0 and m.body(other).name != "table":
            if "t_ghost_arm" not in ep:
                ep["t_ghost_arm"] = t
                ep["ghost_arm_body"] = m.body(other).name
                ep["ghost_arm_z"] = float(con.pos[2])


class MyoRelocateV6Task(MyoRelocateV5Task):
    name = "myo_relocate_v6"
    env_id = ENV_P2 if os.environ.get("RELOC6_ENV") == "p2" else ENV_EVAL
    # diagnostics only: RELOC6_ENVKW (JSON) overrides the env's randomisation
    # kwargs, e.g. '{"qpos_noise_range": 0.01}' (P2 0.01, eval 0.015) or
    # P2's obj_geom_range / obj_mass_range on the eval env
    env_kwargs = json.loads(os.environ.get("RELOC6_ENVKW") or "{}")

    def __init__(self):
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        self.controller = os.path.join(root, "bin", "robolab_myo_relocate_v6")

    def on_step(self, sim, obs, reward, info):
        ep = episode_store(sim)
        m, d = sim.m, sim.d
        c = cache(sim)
        if "mass" not in ep:
            b = c.obj_body
            g0 = m.body_geomadr[b]
            gs = range(g0, g0 + m.body_geomnum[b])
            ep["mass"] = float(m.body_mass[b])
            ep["gmax"] = float(max(np.max(m.geom_size[g]) for g in gs))
            ep["vol"] = float(sum(8.0 * np.prod(m.geom_size[g]) for g in gs) * 1e6)
            ep["fric"] = float(m.geom_friction[g0][0])
        super().on_step(sim, obs, reward, info)
        ghost_contacts(sim, ep, c)
        # start disturbance: the largest arm/wrist joint speed over the first
        # three steps (a start inside the invisible receptacle is shoved out)
        if float(d.time) <= 0.031:
            v = max(abs(float(d.qvel[k])) for k in c.dof)
            ep["qd_start"] = max(ep.get("qd_start", 0.0), v)
            ep.setdefault("qd_steps", []).append(round(v, 3))
            ep.setdefault("qd_vec", []).extend(round(float(d.qvel[k]), 4) for k in c.dof)
        chunk = (sim.label or "").split(":")[-1]
        o = np.array(sim.u.obs_dict["obj_pos"], dtype=float)
        palm = np.array(sim.u.obs_dict["palm_pos"], dtype=float)
        t = float(d.time)
        if "xy_start" not in ep:
            ep["xy_start"] = o[:2].copy()
        if "z0" not in ep and t >= 0.3:
            ep["z0"] = float(o[2])
        if "xy_set" not in ep and t >= 0.35:
            ep["xy_set"] = o[:2].copy()
        if chunk == "descend" and "desc_xy" not in ep:
            ep["desc_xy"] = o[:2].copy()
        if chunk == "close" and "push" not in ep and "desc_xy" in ep:
            ep["push"] = float(np.linalg.norm(o[:2] - ep["desc_xy"]))
        if chunk in ("lift", "carry", "lower"):
            touch = float(np.sum(hand_touch(sim, c)))
            gap = float(palm[2] - o[2])
            if touch > 1.0:
                if "gap0" not in ep:
                    ep["gap0"] = gap
                ep["slip_z"] = max(ep.get("slip_z", 0.0), gap - ep["gap0"])

    def metrics(self, sim, log):
        out = super().metrics(sim, log)
        ep = episode_store(sim)
        out.update({
            "mass": round(ep.get("mass", 0.0), 4), "gmax": round(ep.get("gmax", 0.0), 4),
            "vol": round(ep.get("vol", 0.0), 2), "fric": round(ep.get("fric", 0.0), 3),
            "z0": round(ep.get("z0", 0.0), 4), "push": round(ep.get("push", -1.0), 4),
            "slip_z": round(ep.get("slip_z", 0.0), 4),
            "t_ghost_arm": round(ep.get("t_ghost_arm", -1.0), 3),
            "t_ghost_obj": round(ep.get("t_ghost_obj", -1.0), 3),
            "qd_start": round(ep.get("qd_start", 0.0), 3), "qd_steps": ep.get("qd_steps", []), "qd_vec": ep.get("qd_vec", []),
            "ghost_arm_body": ep.get("ghost_arm_body", ""), "ghost_arm_z": round(ep.get("ghost_arm_z", 0.0), 4),
        })
        g = ep.get("ghost", np.zeros(3))
        out.update({"ghost_x": round(float(g[0]), 4), "ghost_y": round(float(g[1]), 4), "ghost_z": round(float(g[2]), 4)})
        # (an episode that ends before 0.35 s, e.g. on a simulation blow-up,
        # reports where the object was last)
        xs = ep.get("xy_start", np.zeros(2))
        xe = ep.get("xy_set", ep["obj"][-1][:2] if ep.get("obj") else xs)
        out.update({"x_set": round(float(xe[0]), 4), "y_set": round(float(xe[1]), 4),
                    "roll": round(float(np.linalg.norm(xe - xs)), 4)})
        return out

    def score(self, metrics):
        # RELOC6_SCORE=official: the leaderboard measure weighted up (official
        # success counts as much as a genuine lift-and-place), plus the same
        # shaping; otherwise the round-5 score
        if os.environ.get("RELOC6_SCORE") == "official":
            return super().score(metrics) + 0.95 * metrics.get("success", 0.0)
        return super().score(metrics)

    def title(self):
        return f"robolab relocate (round 6) on {self.env_id}"


TASK = MyoRelocateV6Task
