"""MyoChallenge 2022 Baoding balls, phase 2 (myoHand: 39 muscles, forearm and hand).

Two balls in the upturned palm must follow two targets that circle an
ellipse (x radius 2-3 cm, y radius 2.2-3.2 cm) in the palm's frame: a third
of the episodes hold still (HOLD), a third turn clockwise, a third counter-
clockwise, at one turn per 4-6 s, starting from a random phase. Balls are
1.8-2.4 cm in radius and 30-300 g (nominal 43 g), with random friction. An
episode lasts 200 steps of 25 ms (5 s) and ends early when a ball falls
below z = 1.25.

Official scoring (baoding_v1.BaodingEnvV1): a step is `solved` when both
balls are within 1.5 cm of their targets; the score is the mean over
episodes of (solved steps / 200), so a dropped episode keeps what it earned.

Sensors added for the skill (palm frame = the target sites' parent body,
coordinates relative to the ellipse centre, metres):
  balls   [x1, y1, x2, y2]  ball centres
  goals   [x1, y1, x2, y2]  target positions
  ball_z  [z1, z2]          ball heights in the palm frame (drop warning)
  touch   ball contact force (N) per hand group
          [thumb, index, middle, ring, little, palm] for ball 1, then ball 2
"""

import numpy as np
import mujoco

from myo_bridge import MyoTask

TOUCH_GROUPS = [
    ("thumb", ["firstmc", "proximal_thumb", "distal_thumb"]),
    ("index", ["proxph2", "midph2", "distph2"]),
    ("middle", ["proxph3", "midph3", "distph3"]),
    ("ring", ["proxph4", "midph4", "distph4"]),
    ("little", ["proxph5", "midph5", "distph5"]),
    ("palm", ["secondmc", "thirdmc", "fourthmc", "fifthmc", "lunate", "scaphoid", "pisiform",
              "triquetrum", "capitate", "trapezium", "trapezoid", "hamate"]),
]


class BaodingCache:
    def __init__(self, sim):
        m, u = sim.m, sim.u
        self.frame = m.site_bodyid[u.target1_sid]
        self.balls = [u.object1_sid, u.object2_sid]
        self.targets = [u.target1_sid, u.target2_sid]
        self.ball_bodies = [u.object1_bid, u.object2_bid]
        self.group = {}
        for k, (_, names) in enumerate(TOUCH_GROUPS):
            for n in names:
                self.group[m.body(n).id] = k
        self.force = np.zeros(6)


def cache(sim):
    c = getattr(sim, "_baoding_cache", None)
    if c is None:
        c = sim._baoding_cache = BaodingCache(sim)
    return c


def episode_store(sim):
    ep = getattr(sim, "_ep", None)
    if ep is None:
        ep = sim._ep = {}
    return ep


def palm_frame(sim, c):
    d = sim.d
    return d.xpos[c.frame].copy(), d.xmat[c.frame].reshape(3, 3).copy()


def local_xy(sim, c, sid, p, R):
    loc = R.T @ (sim.d.site_xpos[sid] - p)
    cx, cy = sim.u.center_pos
    return loc[0] - cx, loc[1] - cy, loc[2]


def ball_touch(sim, c):
    m, d = sim.m, sim.d
    out = np.zeros(12)
    for i in range(d.ncon):
        con = d.contact[i]
        b1, b2 = m.geom_bodyid[con.geom1], m.geom_bodyid[con.geom2]
        for slot, bb in enumerate(c.ball_bodies):
            if b1 == bb or b2 == bb:
                other = b2 if b1 == bb else b1
                k = c.group.get(other)
                if k is not None:
                    mujoco.mj_contactForce(m, d, i, c.force)
                    out[slot * 6 + k] += abs(c.force[0])
    return out


class MyoBaodingTask(MyoTask):
    name = "myo_baoding"
    env_id = "myoChallengeBaodingP2-v1"
    coupled_geometry = True
    geometry_pairs = True  # joint-pair length corrections (validated) for the finger muscles
    forward_keys = ["object1_pos", "object2_pos", "target1_pos", "target2_pos"]

    def extra_sensors(self, sim):
        c = cache(sim)
        p, R = palm_frame(sim, c)
        b1 = local_xy(sim, c, c.balls[0], p, R)
        b2 = local_xy(sim, c, c.balls[1], p, R)
        t1 = local_xy(sim, c, c.targets[0], p, R)
        t2 = local_xy(sim, c, c.targets[1], p, R)
        return [
            ("balls", [b1[0], b1[1], b2[0], b2[1]]),
            ("goals", [t1[0], t1[1], t2[0], t2[1]]),
            ("ball_z", [b1[2], b2[2]]),
            ("touch", ball_touch(sim, c)),
        ]

    def on_step(self, sim, obs, reward, info):
        ep = episode_store(sim)
        ep.setdefault("act_sq", []).append(float(np.mean(sim.d.act ** 2)))
        c = cache(sim)
        p, R = palm_frame(sim, c)
        b1 = local_xy(sim, c, c.balls[0], p, R)
        b2 = local_xy(sim, c, c.balls[1], p, R)
        t1 = local_xy(sim, c, c.targets[0], p, R)
        ep.setdefault("phi", []).append(float(np.arctan2(b1[1] - b2[1], b1[0] - b2[0])))
        ep.setdefault("mid", []).append(float(np.hypot(0.5 * (b1[0] + b2[0]), 0.5 * (b1[1] + b2[1]))))
        ep.setdefault("phi_goal", []).append(float(np.arctan2(t1[1], t1[0])))

    def metrics(self, sim, log):
        infos = sim.infos
        horizon = self.horizon(sim)
        solved = [float(i["rwd_dict"]["solved"]) for i in infos]
        d1 = [-float(i["rwd_dict"]["pos_dist_1"]) for i in infos]
        d2 = [-float(i["rwd_dict"]["pos_dist_2"]) for i in infos]
        act_reg = [-float(i["rwd_dict"]["act_reg"]) for i in infos]
        ep = episode_store(sim)
        phi = np.unwrap(np.array(ep.get("phi", [0.0])))
        return {
            "score": round(float(np.sum(solved) / horizon), 4),
            "solved_steps": int(np.sum(solved)),
            "held_frac": round(len(infos) / horizon, 4),
            "task": str(sim.u.which_task).split(".")[-1],
            "mean_err": round(float(np.mean(np.array(d1) + np.array(d2)) / 2), 4) if d1 else 1.0,
            "turn": round(float(phi[-1] - phi[0]) / (2 * np.pi), 3),
            "mid_err": round(float(np.mean(ep.get("mid", [0.05]))), 4),
            "effort_official": round(float(np.mean(act_reg)), 5) if act_reg else 0.0,
            "act_sq": round(float(np.mean(ep.get("act_sq", [0.0]))), 5),
        }

    def horizon(self, sim):
        return getattr(sim.u, "horizon", 200) or 200

    def score(self, metrics):
        # official score, plus shaping: keep the balls (held fraction) and
        # keep them near their targets
        near = max(0.0, 1.0 - metrics.get("mean_err", 1.0) / 0.05)
        return metrics.get("score", 0.0) + 0.3 * metrics.get("held_frac", 0.0) + 0.3 * near * metrics.get("held_frac", 0.0)

    def trace_row(self, sim, info):
        c = cache(sim)
        p, R = palm_frame(sim, c)
        b1 = local_xy(sim, c, c.balls[0], p, R)
        b2 = local_xy(sim, c, c.balls[1], p, R)
        t1 = local_xy(sim, c, c.targets[0], p, R)
        t2 = local_xy(sim, c, c.targets[1], p, R)
        phi = np.degrees(np.arctan2(b1[1] - b2[1], b1[0] - b2[0]))
        phg = np.degrees(np.arctan2(t1[1], t1[0]))
        f = lambda v: " ".join(f"{1000 * x:5.0f}" for x in v)
        return (f"phi {phi:6.1f} goal {phg:6.1f} b1 {f(b1)} b2 {f(b2)} t1 {f(t1[:2])} t2 {f(t2[:2])} "
                f"err {1000 * np.linalg.norm(np.array(b1[:2]) - t1[:2]):4.0f} {1000 * np.linalg.norm(np.array(b2[:2]) - t2[:2]):4.0f} "
                f"ok {int(info['rwd_dict']['solved'])} {getattr(sim, '_dbg', '')}")

    def on_command(self, sim, cmd):
        if cmd.startswith("dbg:"):
            sim._dbg = cmd[4:]

    def camera(self, m, d, cam):
        c = 0.5 * (d.site_xpos[m.site("ball1_site").id] + d.site_xpos[m.site("ball2_site").id])
        cam.lookat[:] = c
        cam.distance = 0.32
        cam.azimuth = 90
        cam.elevation = -70

    def hud_text(self, m, d):
        return ""

    def title(self):
        return f"robolab baoding on {self.env_id}"


TASK = MyoBaodingTask
