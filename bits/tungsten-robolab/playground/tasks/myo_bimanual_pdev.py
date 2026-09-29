"""Development task for the bimanual prosthesis alone: the same environment,
metrics and scoring as myo_bimanual, but the start pillar sits within the
MPL arm's reach (x = PDEV_X, default 0.0; the official task's is at -0.4,
which the MPL cannot reach) and the myo arm idles (params myo_idle = 1,
m_now = 1, m_v4 = 1 of MyoBimanualV4Skill). The score rewards the
prosthesis's own part of a success: >= 100 contact frames, the box set on
the goal pillar with only the pillar touching it at the end, no stray
contact.
"""

import os

import mujoco
import numpy as np

from tasks.myo_bimanual import MyoBimanualTask


class MyoBimanualPdevTask(MyoBimanualTask):
    name = "myo_bimanual_pdev"

    def __init__(self):
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        self.controller = os.path.join(root, "bin", "robolab_myo_bimanual_v4")
        x = float(os.environ.get("PDEV_X", "0.0"))
        self.env_kwargs = {"start_center": np.array([x, -0.25, 1.05])}

    def extra_sensors(self, sim):
        # MyoSuite 2.12.2's reset writes the start position into the env's
        # mj_data, not the physics' (u.robot.mj_data), so the box always
        # starts at the keyframe's x = -0.4: move it onto the (moved) start
        # pillar in the physics' data once, after the first step
        n = len(getattr(sim, "infos", []))
        if n == 1:
            u = sim.u
            for m, d in ((u.robot.mj_model, u.robot.mj_data), (sim.m, sim.d)):
                adr = m.jnt_qposadr[m.body_jntadr[u.obj_bid]]
                site = d.site_xpos[u.obj_sid]
                d.qpos[adr:adr + 2] += m.body_pos[u.start_bid][:2] - site[:2]
                d.qpos[adr + 2] += u.PILLAR_HEIGHT + 0.046 - site[2]
                dof = m.jnt_dofadr[m.body_jntadr[u.obj_bid]]
                d.qvel[dof:dof + 6] = 0.0
                mujoco.mj_forward(m, d)
        return super().extra_sensors(sim)

    def metrics(self, sim, log):
        out = super().metrics(sim, log)
        ep = sim._ep
        hist = ep.get("touch_hist", [])
        labels = [set(str(x).split(".")[-1] for x in s) for s in hist]
        tail = labels[-8:]
        goal_only = float(len(tail) == 8 and all(s == {"GOAL"} for s in tail))
        out["goal_only_end"] = goal_only
        out["pros_success"] = float(out["solved_steps"] > 5 and out["env_frames"] == 0 and goal_only > 0
                                    and out["pros_frames"] >= 100)
        return out

    def score(self, m):
        s = m.get("pros_success", 0.0)
        s += 0.3 * min(1.0, m.get("pros_frames", 0) / 100.0)
        s += 0.3 * max(0.0, 1.0 - m.get("min_goal_dist", 1.0) / 0.6)
        s += 0.2 * m.get("goal_only_end", 0.0)
        s += 0.1 * min(1.0, m.get("solved_steps", 0) / 10.0)
        s -= 0.2 * min(1.0, m.get("env_frames", 0) / 10.0)
        return s


TASK = MyoBimanualPdevTask
