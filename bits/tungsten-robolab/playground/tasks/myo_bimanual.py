"""MyoChallenge 2024 bimanual handover (myoArm, 63 muscles, + MPL prosthetic arm
and hand, 17 position servos).

The myoArm (right) picks a gelatin box (7.2 x 8.8 x 2.8 cm, 97 +- 50 g) off
the start pillar (x -0.4, randomised +-5.5 cm, top at z 1.09), hands it to
the prosthesis (left), which places it on the goal pillar (x +0.4, +-9.8 cm).
1000 steps of 10 ms (10 s).

Official scoring (bimanual_v0.BimanualEnvV1.get_metrics): an episode succeeds
when more than 5 steps are `solved` (box within 0.17 m of the goal pillar's
top centre and the goal having touched the box for >= 10 frames) and the
contact history passes evaluate_contact_trajectory: the myo hand touched the
box for >= 100 frames, the prosthesis for >= 100 frames, nothing else ever
touched it, and over the last 8 frames only the goal pillar did.

Note (MyoSuite 2.12.2): `_get_done` ends the episode on the step after the
first solved step, so an episode that stops at termination can never have
more than 2 solved steps and the > 5 criterion is unreachable. With
`continue_after_solve` (default on, reported) this task keeps stepping past a
solve-termination until the 10 s horizon (a drop still ends the episode),
which is what the > 5-step criterion needs; `success_at_done` reports the
same criterion on the truncated trajectory.

Sensors added for the skill:
  tips     myo thumb, index and middle tip positions (9)
  touch    myo hand-box contact force (N) per group
           [thumb, index, middle, ring, little, palm]
  touch_pos force-weighted centroid of those contacts (world; zeros if none)
  box_up   the box's local z axis in world (3), its yaw in the xy plane (1)
  pros_q   prosthesis joint angles, in servo order (17)
"""

import numpy as np
import mujoco

from myo_bridge import MyoTask
from myosuite.envs.myo.myochallenge.bimanual_v0 import evaluate_contact_trajectory

TOUCH_GROUPS = [
    ("thumb", ["firstmc", "proximal_thumb", "distal_thumb"]),
    ("index", ["proxph2", "midph2", "distph2"]),
    ("middle", ["proxph3", "midph3", "distph3"]),
    ("ring", ["proxph4", "midph4", "distph4"]),
    ("little", ["proxph5", "midph5", "distph5"]),
    ("palm", ["secondmc", "thirdmc", "fourthmc", "fifthmc", "lunate", "scaphoid", "pisiform",
              "triquetrum", "capitate", "trapezium", "trapezoid", "hamate"]),
]


class BimanualCache:
    def __init__(self, sim):
        m, u = sim.m, sim.u
        self.tips = [m.site(n).id for n in ("THtip", "IFtip", "MFtip")]
        self.obj_bid = u.obj_bid
        self.group = {}
        for k, (_, names) in enumerate(TOUCH_GROUPS):
            for n in names:
                self.group[m.body(n).id] = k
        self.pros = [m.actuator_trnid[a, 0] for a in sim.motor_ids]
        self.pros_adr = [m.jnt_qposadr[j] for j in self.pros]
        self.force = np.zeros(6)


def cache(sim):
    c = getattr(sim, "_bim_cache", None)
    if c is None:
        c = sim._bim_cache = BimanualCache(sim)
    return c


def episode_store(sim):
    ep = getattr(sim, "_ep", None)
    if ep is None:
        ep = sim._ep = {}
    return ep


def box_touch(sim, c, where=None):
    """Myo hand-box contact force per group; with `where`, also the
    force-weighted contact centroid (world, zeros when nothing touches)."""
    m, d = sim.m, sim.d
    out = np.zeros(6)
    acc, wsum = np.zeros(3), 0.0
    for i in range(d.ncon):
        con = d.contact[i]
        b1, b2 = m.geom_bodyid[con.geom1], m.geom_bodyid[con.geom2]
        if c.obj_bid not in (b1, b2):
            continue
        k = c.group.get(b2 if b1 == c.obj_bid else b1)
        if k is not None:
            mujoco.mj_contactForce(m, d, i, c.force)
            fz = abs(c.force[0])
            out[k] += fz
            acc += fz * con.pos
            wsum += fz
    if where is not None:
        where[:] = acc / wsum if wsum > 1e-9 else 0.0
    return out


class MyoBimanualTask(MyoTask):
    name = "myo_bimanual"
    env_id = "myoChallengeBimanual-v0"
    coupled_geometry = True
    continue_after_solve = True
    forward_keys = ["obj_pos", "palm_pos", "Rpalm_pos", "start_pos", "goal_pos", "touching_body", "MPL_ori"]

    def extra_sensors(self, sim):
        c = cache(sim)
        d = sim.d
        self._install_continue(sim)
        R = d.xmat[c.obj_bid].reshape(3, 3)
        where = np.zeros(3)
        return [
            ("tips", np.concatenate([d.site_xpos[t] for t in c.tips])),
            ("touch", box_touch(sim, c, where)),
            ("touch_pos", where),
            ("box_up", np.concatenate([R[:, 2], [np.arctan2(R[1, 0], R[0, 0])]])),
            ("pros_q", d.qpos[c.pros_adr]),
        ]

    def _install_continue(self, sim):
        """Keep stepping past the env's solve-termination (see the module note);
        a drop (box below z 0.3) or the time limit still ends the episode."""
        if not self.continue_after_solve or getattr(sim, "_continue_installed", False):
            return
        sim._continue_installed = True
        step = sim.env.step

        def stepped(a):
            obs, r, term, trunc, info = step(a)
            ep = episode_store(sim)
            if term and "done_step" not in ep:
                ep["done_step"] = len(sim.infos) + 1
            z = float(sim.u.obs_dict["obj_pos"][2])
            if term and z >= 0.3:
                term = False
            return obs, r, term, trunc, info
        sim.env.step = stepped

    def on_step(self, sim, obs, reward, info):
        ep = episode_store(sim)
        ep.setdefault("act_sq", []).append(float(np.mean(sim.d.act ** 2)))
        ep.setdefault("touch_hist", []).append(set(sim.u.touch_history[-1]) if sim.u.touch_history else set())
        # copied now: obs_dict["obj_pos"] is a view into mj_data
        od = sim.u.obs_dict
        ep.setdefault("obj_z", []).append(float(od["obj_pos"][2]))
        tb = od["touching_body"]
        if tb[0] > 0:  # held by the myo hand
            ep["held_z"] = max(ep.get("held_z", 0.0), float(od["obj_pos"][2]))
            ep.setdefault("held_pos", []).append(np.array(od["obj_pos"], dtype=float))

    def metrics(self, sim, log):
        infos = sim.infos
        ep = episode_store(sim)
        solved = [float(i["rwd_dict"]["solved"]) for i in infos]
        hist = ep.get("touch_hist", [])
        issue = evaluate_contact_trajectory(hist)
        n = int(np.sum(solved))
        cut = ep.get("done_step", len(infos))
        n_cut = int(np.sum(solved[:cut]))
        issue_cut = evaluate_contact_trajectory(hist[:cut]) if hist else "empty"
        labels = [set(str(x).split(".")[-1] for x in s) for s in hist]
        myo = sum(1 for s in labels if "MYO" in s)
        pros = sum(1 for s in labels if "PROSTH" in s)
        env_c = sum(1 for s in labels if "ENV" in s)
        goal_d = [float(np.asarray(i["rwd_dict"]["goal_dist"]).ravel()[0]) for i in infos]
        obj_z = ep.get("obj_z", [])
        out = {
            "success": float(n > 5 and issue is None),
            "success_at_done": float(n_cut > 5 and issue_cut is None),
            "solved_steps": n,
            "contact_issue": str(issue).split(".")[-1] if issue is not None else "none",
            "myo_frames": myo,
            "pros_frames": pros,
            "env_frames": env_c,
            "min_goal_dist": round(float(np.min(goal_d)), 4) if goal_d else 1.0,
            "max_obj_z": round(float(np.max(obj_z)), 4) if obj_z else 0.0,
            "held_z": round(float(ep.get("held_z", 0.0)), 4),
            "effort_official": round(float(np.mean([float(np.asarray(i["rwd_dict"]["act"]).ravel()[0]) for i in infos])), 5),
            "act_sq": round(float(np.mean(ep.get("act_sq", [0.0]))), 5),
        }
        # staged progress without the success term (the arena's
        # bimanual_stages metric while success is out of reach)
        out["progress"] = round(self.score(out) - out["success"], 4)
        return out

    def score(self, metrics):
        # success, then the stages: myo holds (myo frames), lift, prosthesis
        # holds, box brought to the goal, no stray contact
        s = metrics.get("success", 0.0)
        s += 0.2 * min(1.0, metrics.get("myo_frames", 0) / 100.0)
        s += 0.2 * min(1.0, max(0.0, metrics.get("max_obj_z", 1.1) - 1.12) / 0.1)
        s += 0.3 * min(1.0, metrics.get("pros_frames", 0) / 100.0)
        s += 0.3 * max(0.0, 1.0 - metrics.get("min_goal_dist", 1.0) / 0.8)
        s -= 0.1 * min(1.0, metrics.get("env_frames", 0) / 10.0)
        return s

    def trace_row(self, sim, info):
        od = sim.u.obs_dict
        c = cache(sim)
        f = lambda v: " ".join(f"{x:6.3f}" for x in v)
        return (f"obj {f(od['obj_pos'])} palm-obj {f(od['palm_pos'] - od['obj_pos'])} Rpalm-obj {f(od['Rpalm_pos'] - od['obj_pos'])} "
                f"touch {''.join(str(int(x)) for x in od['touching_body'])} myo {f(box_touch(sim, c))} ok {int(info['rwd_dict']['solved'])} "
                f"{getattr(sim, '_dbg', '')}")

    def on_command(self, sim, cmd):
        if cmd.startswith("dbg:"):
            sim._dbg = cmd[4:]

    def camera(self, m, d, cam):
        cam.lookat[:] = [0.0, -0.25, 1.15]
        cam.distance = 1.6
        cam.azimuth = 90
        cam.elevation = -25

    def title(self):
        return f"robolab bimanual handover on {self.env_id}"


TASK = MyoBimanualTask
