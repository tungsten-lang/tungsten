"""MyoStand: 3D standing balance on the ChaseTag myoLeg, with pushes.

Quiet stance from the standing key frame (reset_type="none") on the official
myoChallengeChaseTagP1-v0 model. This is a ROBUSTNESS TEST, not an official
task: a push schedule applies horizontal forces to the pelvis/torso body
(STAND_PUSH newtons for 0.2 s; 0 disables), alternating forward, left,
backward and right every 2.5 s starting at 1.5 s, with the direction jittered
by the seed. The skill never sees the pushes except through its senses.

Metrics: time (to 10 s), fallen, pushes survived, COM sway (mean and max
horizontal COM distance from the feet centre), effort, pelvis height.
"""

import math
import os

import numpy as np

from myo_bridge import MyoTask, ROOT


class MyoStandTask(MyoTask):
    name = "myo_stand"
    env_id = "myoChallengeChaseTagP1-v0"
    env_kwargs = {"reset_type": "none"}
    controller = os.path.join(ROOT, "bin", "robolab_myo_walk")
    coupled_geometry = True
    seconds = 10.0

    def __init__(self):
        self.push = float(os.environ.get("STAND_PUSH", "0"))
        self.push_t = float(os.environ.get("STAND_PUSH_T", "0.2"))
        self.rec = []
        self.pushes = []
        self.parked = False

    def set_seed_reset(self, seed):
        pass  # the seed jitters the push directions (see on_step)

    def extra_sensors(self, sim):
        return [("walk_goal", [0.0, 0.0, 0.0])] + muscle_constants(sim)

    def on_step(self, sim, obs, reward, info):
        d = sim.d
        if not self.parked:
            sim.u.opponent.opponent_policy = "stationary"
            sim.u.opponent.set_opponent_pose([5.9, 5.9, 0.0])
            self.parked = True
            self.rng = np.random.default_rng(sim.seed)
        rid = sim.m.body(sim.root).id
        # MyoSuite steps the robot's own MjData; sim.d is a synced copy, so
        # an external force has to go to the robot's data
        xf = sim.u.robot.mj_data.xfrc_applied
        xf[rid, :] = 0.0
        if self.push > 0:
            k = int((d.time - 1.5) // 2.5)
            t0 = 1.5 + 2.5 * k
            if k >= 0 and t0 <= d.time < t0 + self.push_t:
                fwd = d.body(sim.root).xmat.reshape(3, 3)[:, 0]
                psi = math.atan2(fwd[1], fwd[0]) + k * math.pi / 2 + self.rng.normal(0, 0.3)
                xf[rid, 0] = self.push * math.cos(psi)
                xf[rid, 1] = self.push * math.sin(psi)
                if not self.pushes or self.pushes[-1] != k:
                    self.pushes.append(k)
        com = d.subtree_com[rid][:2].copy()
        feet = 0.5 * (d.body("calcn_l").xpos[:2] + d.body("calcn_r").xpos[:2])
        self.rec.append((d.time, float(np.linalg.norm(com - feet)), float(d.body("pelvis").xpos[2])))

    def metrics(self, sim, log):
        if not self.rec:
            return {}
        sway = np.array([r[1] for r in self.rec])
        z = np.array([r[2] for r in self.rec])
        acts = np.array([row[2] for row in log]) if log else np.zeros((1, sim.n))
        fallen = bool(z[-1] < 0.5)
        return {"sway": round(float(np.mean(sway)), 4), "sway_max": round(float(np.max(sway)), 4),
                "pelvis_z": round(float(np.mean(z)), 3), "fallen": fallen,
                "pushes": len(self.pushes) - (1 if fallen and self.pushes else 0),
                "effort": round(float(np.mean(acts ** 2)), 4)}

    def score(self, m):
        if "error" in m:
            return -1e9
        return 3.0 * m.get("time", 0.0) - 10.0 * m.get("sway", 1.0) - 20.0 * m.get("effort", 1.0) + m.get("pelvis_z", 0.0)


TASK = MyoStandTask


def muscle_constants(sim):
    """Peak force and length range of every muscle, as constant sensor blocks
    (the handshake does not carry them; MyoWalkHip needs them)."""
    fmax = sim.m.actuator_gainprm[sim.muscle_ids, 2]
    rng = sim.lr[:, 1] - sim.lr[:, 0]
    return [("muscle_fmax", fmax), ("muscle_range", rng)]
