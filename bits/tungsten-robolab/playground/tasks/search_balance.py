"""Search benchmark P2: standing balance under random pushes on a MyoSuite body.

Body and physics: MyoSuite's myoChallengeChaseTagP1-v0 (the myoLeg: 80
muscles at their normal strength, 14 leg joints), started from the model's
standing keyframe (reset_type "none": key 0, a slight crouch with zero
velocity) with the opponent parked out of reach (static policy) so the
chase logic never ends an episode early. Muscle geometry is sampled with
the knee couplings applied (MyoTask.coupled_geometry), so a joint-space
posture maps to the right quadriceps contractions.

Skill: lib/robolab/skills/search_balance.w (a standing midpoint held by the
reflexes plus ankle, hip and lateral balance corrections).

Perturbation: `seed` >= 1 draws a push schedule: three pushes on the pelvis
starting at 0.9, 2.2 and 3.5 s (+- 0.25 s), each 0.2 s long, horizontal, in a
uniformly random direction, with magnitudes drawn from `push_n` (N) and
scaled 0.8 / 1.0 / 1.2 (the last push is the hardest). Pushes are external
disturbances (MjData.xfrc_applied on the pelvis), never assists; nothing
edits qpos during a rollout. seed 0 is quiet standing.

Metrics:
    t_fall        first time the pelvis dropped below 0.65 m or the pelvis
                  tilted more than 0.6 rad from vertical (horizon if never)
    survived      t_fall reached the horizon
    sway          RMS horizontal COM speed while standing (m/s)
    foot_drift    horizontal distance the heels slid or stepped (m, both
                  summed, final vs initial)
    pelvis_z      mean pelvis height while standing (m)
    effort        mean squared activation (from MyoSim)
    pushes        the push schedule [(t, fx, fy), ...]
    q_stand       the midpoint actually held: the 14 leg joint angles at t = 0.6 s
                  (before the earliest push), whatever representation set it

Score (per rollout): 10 * t_fall / horizon + 2 * survived - 2 * sway
- 1 * foot_drift - 4 * effort. Practice aggregates several push seeds.
"""

import math
import os

import numpy as np

from myo_bridge import MyoTask


MIDPOINT_JOINTS = [j + side for side in ("_r", "_l") for j in ("hip_flexion", "hip_adduction", "hip_rotation",
                                                                "knee_angle", "ankle_angle", "subtalar_angle", "mtp_angle")]


class SearchBalanceTask(MyoTask):
    name = "search_balance"
    # a frozen build (./build.sh <skill> then copy to bin/frozen/), so a rebuild of every
    # skill mid-benchmark cannot swap the controller under a running comparison
    controller = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "bin", "frozen", "robolab_search_balance")
    env_id = "myoChallengeChaseTagP1-v0"
    env_kwargs = {"reset_type": "none", "opponent_probabilities": (1.0, 0.0, 0.0)}
    coupled_geometry = True
    seconds = 5.0
    seed = 0
    push_n = (70.0, 140.0)
    push_len = 0.2
    fall_z = 0.65
    fall_tilt = 0.6

    def schedule(self, seed):
        if not seed:
            return []
        rng = np.random.default_rng(1000 + int(seed))
        out = []
        for t0, scale in ((0.9, 0.8), (2.2, 1.0), (3.5, 1.2)):
            t = t0 + rng.uniform(-0.25, 0.25)
            ang = rng.uniform(0.0, 2 * math.pi)
            mag = scale * rng.uniform(*self.push_n)
            out.append((round(t, 4), round(mag * math.cos(ang), 3), round(mag * math.sin(ang), 3)))
        return out

    def _init(self, sim):
        self.pushes = self.schedule(getattr(sim, "seed", self.seed))  # MyoSim's seed (task.seed unless overridden)
        self.pelvis = sim.m.body("pelvis").id
        self.root = sim.m.body(sim.root).id
        self.rec = []
        self.heels0 = [sim.d.body(n).xpos[:2].copy() for n in ("calcn_l", "calcn_r")]
        self.t_fall = None
        self.q_stand = None
        self.joint_adr = {j: sim.m.jnt_qposadr[sim.m.joint(j).id] for j in MIDPOINT_JOINTS}

    def extra_sensors(self, sim):
        # called while the controller starts (handshake), before the first step
        if not hasattr(self, "rec") or getattr(self, "_sim", None) is not sim:
            self._sim = sim
            self._init(sim)
        return []

    def on_step(self, sim, obs, reward, info):
        d = sim.d
        t = float(d.time)
        f = np.zeros(6)
        for tp, fx, fy in self.pushes:
            if tp <= t < tp + self.push_len:
                f[0] += fx
                f[1] += fy
        # MyoSuite steps its robot's own MjData (sim.d is the observation copy
        # it syncs from), so the disturbance goes on the robot's data
        robot = getattr(getattr(sim.u, "robot", None), "mj_data", d)
        robot.xfrc_applied[self.pelvis] = f
        up = d.xmat[self.root].reshape(3, 3)[:, 2]
        tilt = math.acos(max(-1.0, min(1.0, float(up[2]))))
        z = float(d.xpos[self.root][2])
        v = d.subtree_linvel[self.root] if hasattr(d, "subtree_linvel") else np.zeros(3)
        self.rec.append((t, z, tilt, float(v[0]), float(v[1])))
        if self.q_stand is None and t >= 0.6:
            self.q_stand = {j: round(float(d.qpos[a]), 4) for j, a in self.joint_adr.items()}
        if self.t_fall is None and (z < self.fall_z or tilt > self.fall_tilt):
            self.t_fall = t

    def metrics(self, sim, log):
        horizon = self.seconds
        t_fall = self.t_fall if self.t_fall is not None else min(float(sim.d.time), horizon)
        if self.t_fall is None and float(sim.d.time) < horizon - 1e-6:
            t_fall = float(sim.d.time)  # the environment ended the episode (MyoSuite's fall check)
        r = np.array(self.rec) if self.rec else np.zeros((1, 5))
        standing = r[:, 0] <= t_fall
        rs = r[standing] if np.any(standing) else r
        heels = [sim.d.body(n).xpos[:2] for n in ("calcn_l", "calcn_r")]
        drift = float(sum(np.linalg.norm(h - h0) for h, h0 in zip(heels, self.heels0)))
        return {
            "t_fall": round(t_fall, 3),
            "survived": t_fall >= horizon - 0.02,
            "sway": round(float(np.sqrt(np.mean(rs[:, 3] ** 2 + rs[:, 4] ** 2))), 4),
            "foot_drift": round(drift, 4),
            "pelvis_z": round(float(np.mean(rs[:, 1])), 4),
            "pushes": self.pushes,
            "q_stand": self.q_stand,
        }

    def score(self, metrics):
        if "error" in metrics or "t_fall" not in metrics:
            return -1e9
        s = 10.0 * metrics["t_fall"] / self.seconds + 2.0 * float(metrics["survived"])
        s -= 2.0 * metrics["sway"] + 1.0 * metrics["foot_drift"] + 4.0 * metrics.get("effort", 0.0)
        return s

    def camera(self, m, d, cam):
        root = d.body("pelvis").xpos
        cam.lookat[:] = [root[0], root[1], 0.9]
        cam.distance = 3.0
        cam.azimuth = 150
        cam.elevation = -10

    def title(self):
        return "robolab on MyoSuite: push-recovery balance (search benchmark P2)"


TASK = SearchBalanceTask
