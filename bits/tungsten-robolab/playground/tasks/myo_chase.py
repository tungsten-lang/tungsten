"""MyoChase: myoChallengeChaseTagP1-v0 under the official rules and scoring.

Nothing is changed in the environment: the official P1 reset (reset_type
"init": key frame 2, mid-stride at 1.5 m/s), the official opponent (10%
static at (0, -5), 45% stationary at a random spot >= 2 m away, 45% driving
a 1 m circle at 1 m/s), the official termination (tag within 0.5 m = win,
pelvis below 0.5 m = fall, |x| or |y| > 6.5 m = out of bounds, 20 s =
timeout) and the official score: rwd_sparse = 1 - t/20 on the tagging
step, 0 otherwise, summed over the episode (`sparse_sum`); the
challenge score is its mean over episodes. CHASE_ENV=myoChallengeChaseTagP2-v0
selects P2 (random terrain, CHASE or EVADE, random reset).

Metrics per episode: score_official (= sparse_sum), tagged, t_tag, fallen,
out_of_bounds, timeout, distance, mean speed, mean |yaw rate|, effort.

Practice setups (never in official runs): CHASE_SETUP=turn replaces the
sampled opponent, at the first step, by a stationary one at a bearing and
distance picked by the seed (TURN_SETUPS: mostly beside and behind the
walker, two ahead), so a candidate's turning is scored on the same cases
every generation; CHASE_SECONDS caps the episode (an untagged capped
episode scores 0 as a timeout would).
"""

import math
import os

import numpy as np

from myo_bridge import MyoTask, ROOT


class MyoChaseTask(MyoTask):
    name = "myo_chase"
    env_id = os.environ.get("CHASE_ENV", "myoChallengeChaseTagP1-v0")
    controller = os.path.join(ROOT, "bin", "robolab_myo_chase")
    coupled_geometry = True
    # MYO_GEOM_PAIRS=1: exact joint-pair length corrections (MPAIR); default off (the v1 params)
    geometry_pairs = os.environ.get("MYO_GEOM_PAIRS", "0") == "1"
    # MYO_GEOM_REF=<key>: sample the muscle geometry at that key frame (0 = quiet standing,
    # symmetric) instead of the reset posture; default: the reset posture (the v1 params)
    geometry_ref_key = int(os.environ["MYO_GEOM_REF"]) if os.environ.get("MYO_GEOM_REF") else None
    seconds = None  # the environment's own 20 s horizon

    def __init__(self):
        self.rec = []
        self.start = {}
        self.setup = os.environ.get("CHASE_SETUP", "")
        # CHASE_KW="terrain=FLAT,task_choice=EVADE": env overrides for practice and
        # diagnosis only (official runs leave the registered kwargs untouched)
        kw = {}
        for item in filter(None, os.environ.get("CHASE_KW", "").split(",")):
            k, v = item.split("=")
            kw[k] = v
        self.env_kwargs = kw
        if os.environ.get("CHASE_SECONDS"):
            self.seconds = float(os.environ["CHASE_SECONDS"])

    def place_opponent(self, sim):
        """CHASE_SETUP=turn: a stationary opponent at (bearing, distance) from the pelvis, by seed."""
        b_deg, dist = TURN_SETUPS[sim.seed % len(TURN_SETUPS)]
        p = sim.d.body("pelvis").xpos[:2]
        fwd = sim.d.body("root").xmat.reshape(3, 3)[:, 0]
        a = math.atan2(fwd[1], fwd[0]) + math.radians(b_deg)
        opp = sim.u.opponent
        opp.opponent_policy = "stationary"
        opp.set_opponent_pose([float(np.clip(p[0] + dist * math.cos(a), -5.5, 5.5)),
                               float(np.clip(p[1] + dist * math.sin(a), -5.5, 5.5)), 0.0])

    def extra_sensors(self, sim):
        return muscle_constants(sim)

    def on_step(self, sim, obs, reward, info):
        d = sim.d
        p = d.body("pelvis").xpos.copy()
        fwd = d.body("root").xmat.reshape(3, 3)[:, 0]
        if not self.rec and self.setup == "turn":
            self.place_opponent(sim)
        opp = sim.u.opponent.get_opponent_pose()[:2]
        if not self.rec:
            # the opponent at the start (MyoSuite's reset is not fully seed-deterministic,
            # so each episode records what it actually faced)
            rel = opp - p[:2]
            h = math.atan2(fwd[1], fwd[0])
            self.start = {"opp_dist": round(float(np.linalg.norm(rel)), 2),
                          "opp_bearing_deg": round(math.degrees((math.atan2(rel[1], rel[0]) - h + math.pi) % (2 * math.pi) - math.pi), 1)}
        self.rec.append((d.time, p, math.atan2(fwd[1], fwd[0]), float(np.linalg.norm(p[:2] - opp))))

    def camera(self, m, d, cam):
        # overhead-ish view of the whole arena, following the pelvis a little
        root = d.body("pelvis").xpos
        cam.lookat[:] = [0.5 * root[0], 0.5 * root[1], 0.5]
        cam.distance = 11.0
        cam.azimuth = 90
        cam.elevation = -55

    def metrics(self, sim, log):
        rec = self.rec
        u = sim.u
        infos = sim.infos
        tagged = bool(infos and max(float(i.get("solved", 0.0)) for i in infos) > 0)
        t_end = float(sim.d.time)
        p = np.array([r[1] for r in rec]) if rec else np.zeros((1, 3))
        psi = np.unwrap(np.array([r[2] for r in rec])) if rec else np.zeros(1)
        seg = np.linalg.norm(np.diff(p[:, :2], axis=0), axis=1) if len(p) > 1 else np.zeros(1)
        dt = sim.u.dt
        fallen = bool(p[-1, 2] < 0.5)
        oob = bool(np.any(np.abs(p[-1, :2]) > 6.5))
        acts = np.array([row[2] for row in log]) if log else np.zeros((1, sim.n))
        return {
            "task": getattr(u, "current_task", None).name if hasattr(u, "current_task") else "CHASE",
            "opponent": u.opponent.opponent_policy,
            "score_official": round(float(sum(float(i.get("rwd_sparse", 0.0)) for i in infos)), 4),
            "tagged": tagged,
            "t_tag": round(t_end, 2) if tagged else None,
            "fallen": fallen,
            "out_of_bounds": oob,
            "distance": round(float(np.sum(seg)), 3),
            "speed": round(float(np.sum(seg)) / max(t_end, 0.01), 3),
            "yaw_rate": round(float(np.mean(np.abs(np.diff(psi)))) / dt, 3) if len(psi) > 1 else 0.0,
            "effort": round(float(np.mean(acts ** 2)), 4),
            **self.start,
            # practice shaping only: fraction of the initial distance closed
            "closed": round(1.0 - min(r[3] for r in rec) / max(rec[0][3], 1e-6), 3) if rec else 0.0,
        }

    def score(self, m):
        if "error" in m or not np.isfinite(m.get("effort", 0.0)):
            return -1e9
        # the official score, plus a shaping term for practice: survival and
        # closing distance count a little when there is no tag
        s = m.get("score_official", 0.0)
        if not m.get("tagged"):
            # CHASE_SURV_W: weight of survival time (practice on P2 terrain: stay up first)
            w = float(os.environ.get("CHASE_SURV_W", "0.01"))
            s += 0.3 * max(0.0, m.get("closed", 0.0)) + w * min(m.get("time", 0.0), 20.0)
        return s


TASK = MyoChaseTask

# (bearing in degrees, + = left of the heading; distance in m) per seed % 16
TURN_SETUPS = [(90, 2.5), (-90, 2.5), (135, 3.0), (-135, 3.0), (180, 2.5), (160, 4.0), (-160, 4.0), (40, 3.0),
               (70, 2.2), (-70, 2.2), (120, 4.5), (-120, 4.5), (180, 4.0), (-100, 3.5), (100, 3.5), (-40, 3.0)]


def muscle_constants(sim):
    """Peak force and length range of every muscle, as constant sensor blocks
    (the handshake does not carry them; MyoWalkHip needs them)."""
    fmax = sim.m.actuator_gainprm[sim.muscle_ids, 2]
    rng = sim.lr[:, 1] - sim.lr[:, 0]
    return [("muscle_fmax", fmax), ("muscle_range", rng)]
