"""MyoChallenge 2022 die reorientation, phase 2 (myoHand: 39 muscles).

A die rests in the upturned palm; each episode draws a goal pose (position
+-2 cm, orientation with each Euler angle uniform in +-180 deg) and a die
size (+-7 mm), mass (50-250 g) and friction. 150 steps of 10 ms (1.5 s).

Official scoring (reorient_v0.ReorientEnvV0): a step is `solved` when the
die is within 2.5 cm of the goal (corrected for the display offset) and the
norm of the Euler-angle difference goal_rot - obj_rot is below 0.262 rad;
the episode ends when the die strays 20 cm (a drop). An episode succeeds when
more than 5 steps are solved; the score is the success rate.

Sensors added for the skill:
  rot_vec   rotation that takes the die to the goal orientation, as a
            rotation vector in the palm frame (rad): the axis to roll about
  pos_loc   goal - die position in the palm frame (m)
  die_axes  die axes (x, y, z unit vectors) in the palm frame (9)
  touch     die contact force (N) per hand group
            [thumb, index, middle, ring, little, palm]
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


def rotvec(R):
    c = np.clip((np.trace(R) - 1) / 2, -1.0, 1.0)
    ang = np.arccos(c)
    if ang < 1e-9:
        return np.zeros(3)
    if ang > np.pi - 1e-6:  # 180 deg: axis from the diagonal
        ax = np.sqrt(np.maximum(0, (np.diag(R) + 1) / 2))
        return ax * ang
    w = np.array([R[2, 1] - R[1, 2], R[0, 2] - R[2, 0], R[1, 0] - R[0, 1]]) / (2 * np.sin(ang))
    return w * ang


class DieCache:
    def __init__(self, sim):
        m, u = sim.m, sim.u
        self.obj_sid = u.object_sid
        self.goal_sid = u.goal_sid
        self.obj_bid = u.object_bid
        self.frame = m.body("trapezium").id if mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_BODY, "trapezium") >= 0 else 1
        self.group = {}
        for k, (_, names) in enumerate(TOUCH_GROUPS):
            for n in names:
                if mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_BODY, n) >= 0:
                    self.group[m.body(n).id] = k
        self.force = np.zeros(6)


def cache(sim):
    c = getattr(sim, "_die_cache", None)
    if c is None:
        c = sim._die_cache = DieCache(sim)
    return c


def episode_store(sim):
    ep = getattr(sim, "_ep", None)
    if ep is None:
        ep = sim._ep = {}
    return ep


def die_touch(sim, c):
    m, d = sim.m, sim.d
    out = np.zeros(6)
    for i in range(d.ncon):
        con = d.contact[i]
        b1, b2 = m.geom_bodyid[con.geom1], m.geom_bodyid[con.geom2]
        if c.obj_bid not in (b1, b2):
            continue
        k = c.group.get(b2 if b1 == c.obj_bid else b1)
        if k is not None:
            mujoco.mj_contactForce(m, d, i, c.force)
            out[k] += abs(c.force[0])
    return out


class MyoDieTask(MyoTask):
    name = "myo_die"
    env_id = "myoChallengeDieReorientP2-v0"
    coupled_geometry = True
    geometry_pairs = True  # joint-pair length corrections (validated) for the finger muscles
    forward_keys = ["obj_pos", "goal_pos", "pos_err", "obj_rot", "goal_rot", "rot_err"]

    def extra_sensors(self, sim):
        c = cache(sim)
        d = sim.d
        P = d.xmat[c.frame].reshape(3, 3)
        Ro = d.site_xmat[c.obj_sid].reshape(3, 3)
        Rg = d.site_xmat[c.goal_sid].reshape(3, 3)
        w = rotvec(Rg @ Ro.T)                       # world-frame rotation die -> goal
        return [
            ("rot_vec", P.T @ w),
            ("pos_loc", P.T @ np.asarray(sim.u.obs_dict["pos_err"])),
            ("die_axes", (P.T @ Ro).T.ravel()),
            ("touch", die_touch(sim, c)),
        ]

    def on_step(self, sim, obs, reward, info):
        ep = episode_store(sim)
        ep.setdefault("act_sq", []).append(float(np.mean(sim.d.act ** 2)))
        c = cache(sim)
        Ro = sim.d.site_xmat[c.obj_sid].reshape(3, 3)
        Rg = sim.d.site_xmat[c.goal_sid].reshape(3, 3)
        ep.setdefault("ang", []).append(float(np.linalg.norm(rotvec(Rg @ Ro.T))))

    def metrics(self, sim, log):
        infos = sim.infos
        solved = [float(i["rwd_dict"]["solved"]) for i in infos]
        pos = [-float(i["rwd_dict"]["pos_dist"]) for i in infos]
        rot = [-float(i["rwd_dict"]["rot_dist"]) for i in infos]
        act_reg = [-float(i["rwd_dict"]["act_reg"]) for i in infos]
        ep = episode_store(sim)
        ang = ep.get("ang", [np.pi])
        n = int(np.sum(solved))
        return {
            "success": float(n > 5),
            "solved_steps": n,
            "min_rot_dist": round(float(np.min(rot)), 4) if rot else 9.0,
            "final_pos_dist": round(float(pos[-1]), 4) if pos else 1.0,
            "start_angle": round(float(ang[0]), 4),
            "min_angle": round(float(np.min(ang)), 4),
            "final_angle": round(float(ang[-1]), 4),
            "held": float(len(infos) >= 150),
            "effort_official": round(float(np.mean(act_reg)), 5) if act_reg else 0.0,
            "act_sq": round(float(np.mean(ep.get("act_sq", [0.0]))), 5),
        }

    def score(self, metrics):
        # success, then shaping: rotate toward the goal (geodesic angle
        # reduction), keep the die (no drop)
        gain = max(0.0, metrics.get("start_angle", 3.0) - metrics.get("final_angle", 3.0)) / np.pi
        return metrics.get("success", 0.0) + 0.3 * gain + 0.2 * metrics.get("held", 0.0)

    def trace_row(self, sim, info):
        od = sim.u.obs_dict
        c = cache(sim)
        Ro = sim.d.site_xmat[c.obj_sid].reshape(3, 3)
        Rg = sim.d.site_xmat[c.goal_sid].reshape(3, 3)
        f = lambda v: " ".join(f"{x:6.2f}" for x in v)
        return (f"rot_err {f(od['rot_err'])} |euler| {np.linalg.norm(od['rot_err']):5.2f} geo {np.linalg.norm(rotvec(Rg @ Ro.T)):5.2f} "
                f"pos_err {f(od['pos_err'])} touch {f(die_touch(sim, c))} ok {int(info['rwd_dict']['solved'])} {getattr(sim, '_dbg', '')}")

    def on_command(self, sim, cmd):
        if cmd.startswith("dbg:"):
            sim._dbg = cmd[4:]

    def camera(self, m, d, cam):
        cam.lookat[:] = d.site_xpos[m.site("object_o").id]
        cam.distance = 0.3
        cam.azimuth = 90
        cam.elevation = -60

    def title(self):
        return f"robolab die reorientation on {self.env_id}"


TASK = MyoDieTask
