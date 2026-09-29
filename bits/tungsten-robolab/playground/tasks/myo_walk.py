"""MyoWalk: 3D walking and turning on the ChaseTag myoLeg (80 muscles, free root).

The body is the official myoChallengeChaseTagP1-v0 model and dynamics. By
default the episode starts from the official P1 reset (`reset_type="init"`:
key frame 2, mid-stride at 1.5 m/s, right leg swinging); WALK_RESET=none
starts from quiet standing (key 0) and WALK_RESET=random from the P2 reset
(key 2 or 3 with joint noise).

The task only tells the skill where to go, through the `walk_goal` sensor
block [mode, v_des, heading_des]; the skill decides how to walk. Courses
(WALK_COURSE):

  straight   hold the initial heading (the arena edge ends it after ~6 m)
  circle     a circle of radius WALK_R (default 3 m) through the start,
             turning left (pure pursuit on a point 1 m ahead)
  square     a rounded square of side 7 m
  zigzag     alternating +-60 deg headings every 3 s
  waypoints  random waypoints inside +-4.5 m, >= 2 m apart (chase-tag spawns);
             a new one when the pelvis is within 0.5 m; progress = distance
             closed, and the score adds 3 per waypoint reached
  uturn      straight for WALK_T0 s, then the target heading rotates at WALK_OMEGA_U
             (1 rad/s) to the reverse, on the WALK_DIR side;
             progress is measured along the desired heading
  turn       straight for WALK_T0 s (1.5), then turning at WALK_OMEGA rad/s (0.5):
             a ~2.8 m arc at walking pace (progress = path length)

The opponent is parked in a far corner (it is irrelevant to gait tests and
would otherwise end an episode when the walker happens to pass within
0.5 m of it). Nothing else is touched: no external forces, no qpos edits.

Metrics (human-comparable where possible):

  time / fell           survival time; fell = pelvis below 0.5 m (the env's fall rule)
  distance              path length walked by the pelvis (m)
  progress              distance along the course (m)
  speed                 mean forward speed after the first second (m/s)
  speed_last5           mean horizontal pelvis speed over the last 5 s
  cadence               steps per second (foot touchdowns / s)
  step_length           speed / cadence (m)
  turn_rate             mean |yaw rate| (rad/s) and max 1 s heading change (deg/s)
  path_err              mean distance from the course (m)
  effort                mean squared activation (all 80 muscles)
  cot_mech              positive (concentric) muscle work / (m g d): a dimensionless
                        mechanical cost of transport (not metabolic)
"""

import math
import os

import numpy as np

from myo_bridge import MyoTask, ROOT


def heading_of(sim):
    fwd = sim.d.body(sim.root).xmat.reshape(3, 3)[:, 0]
    return math.atan2(fwd[1], fwd[0])


def wrap(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


class Course:
    def __init__(self, kind, p0, psi0, radius=3.0, direction=1, seed=0):
        self.kind, self.p0, self.psi0, self.r = kind, np.array(p0[:2], float), psi0, radius
        self.dir = direction  # circle / turn: +1 turns left (CCW), -1 right (CW)
        self.omega = float(os.environ.get("WALK_OMEGA", "0.5"))
        self.t0 = float(os.environ.get("WALK_T0", "1.5"))
        self.omega_u = float(os.environ.get("WALK_OMEGA_U", "1.0"))  # uturn: target rotation rate
        f = np.array([math.cos(psi0), math.sin(psi0)])
        left = np.array([-f[1], f[0]])
        self.f, self.left = f, left
        self.center = self.p0 + left * radius * direction
        self.reached = 0
        if kind == "waypoints":
            self.rng = np.random.default_rng(1000 + seed)
            self.wp = self._new_wp(self.p0)

    def _new_wp(self, p):
        """A waypoint in the arena interior, at least 2 m away (like a chase-tag spawn)."""
        while True:
            q = self.rng.uniform(-4.5, 4.5, size=2)
            if np.linalg.norm(q - p) >= 2.0:
                return q

    def heading(self, p, t):
        """Desired heading at pelvis position p (world xy) and time t."""
        if self.kind == "straight":
            return self.psi0
        if self.kind == "waypoints":
            if t < 0.6:
                return self.psi0  # the reset is mid-stride: settle first (as MyoChaseSkill)
            if np.linalg.norm(self.wp - p) < 0.5:
                self.reached += 1
                self.wp = self._new_wp(p)
            d = self.wp - p
            return math.atan2(d[1], d[0])
        if self.kind == "uturn":
            # straight for t0 seconds, then the heading reverses (the skill's
            # rate limit shapes the turn; dir picks the side)
            return self.psi0 + self.dir * min(math.pi, self.omega_u * max(0.0, t - self.t0))
        if self.kind == "turn":
            # straight for t0 seconds, then a constant turning rate
            return self.psi0 + self.dir * self.omega * max(0.0, t - self.t0)
        if self.kind == "zigzag":
            k = int(t // 3.0)
            return self.psi0 + (0.0 if k == 0 else (1.05 if k % 2 else -1.05))
        if self.kind == "circle":
            rel = p - self.center
            ang = math.atan2(rel[1], rel[0])
            look = ang + self.dir / self.r  # a point ~1 m further along
            tgt = self.center + self.r * np.array([math.cos(look), math.sin(look)])
            d = tgt - p
            return math.atan2(d[1], d[0])
        if self.kind == "square":
            # rounded square: go straight 3.5 m, turn left, repeat (pure pursuit
            # on waypoints at the corners of a 7 m square centred to the left)
            c = self.p0 + self.left * 3.5
            pts = [c + self.f * 3.5 * sx + self.left * 3.5 * sy for sx, sy in ((1, -1), (1, 1), (-1, 1), (-1, -1))]
            k = self._leg(p, pts)
            d = pts[k] - p
            return math.atan2(d[1], d[0])
        return self.psi0

    def _leg(self, p, pts):
        if not hasattr(self, "k"):
            self.k = 0
        if np.linalg.norm(pts[self.k] - p) < 1.2:
            self.k = (self.k + 1) % len(pts)
        return self.k

    def error(self, p):
        if self.kind == "circle":
            return abs(np.linalg.norm(p - self.center) - self.r)
        if self.kind == "straight":
            return abs(float((p - self.p0) @ self.left))
        return 0.0

    def progress(self, p, prev_p):
        """Distance advanced along the course between two pelvis positions."""
        step = p - prev_p
        if self.kind == "circle":
            rel = prev_p - self.center
            tang = self.dir * np.array([-rel[1], rel[0]]) / max(np.linalg.norm(rel), 1e-6)
            return float(step @ tang)
        if self.kind == "straight":
            return float(step @ self.f)
        if self.kind == "waypoints":
            # distance closed toward the current waypoint
            return float(np.linalg.norm(self.wp - prev_p) - np.linalg.norm(self.wp - p))
        if self.kind == "uturn":
            # progress along the desired heading: out, then back
            h = self.heading(prev_p, self.t_now)
            return float(step @ np.array([math.cos(h), math.sin(h)]))
        return float(np.linalg.norm(step))


class MyoWalkTask(MyoTask):
    name = "myo_walk"
    env_id = "myoChallengeChaseTagP1-v0"
    controller = os.path.join(ROOT, "bin", "robolab_myo_walk")
    coupled_geometry = True
    # MYO_GEOM_PAIRS=1: exact joint-pair length corrections (MPAIR); default off (the v1 params)
    geometry_pairs = os.environ.get("MYO_GEOM_PAIRS", "0") == "1"
    # MYO_GEOM_REF=<key>: sample the muscle geometry at that key frame (0 = quiet standing,
    # symmetric) instead of the reset posture; default: the reset posture (the v1 params)
    geometry_ref_key = int(os.environ["MYO_GEOM_REF"]) if os.environ.get("MYO_GEOM_REF") else None
    seconds = 20.0
    mode = 1.0

    def set_seed_reset(self, seed):
        self.wp_seed = seed
        """WALK_RESET=mixed: seed 0 is the official P1 reset, other seeds the randomized (P2-style) one."""
        if os.environ.get("WALK_RESET") == "mixed":
            self.env_kwargs = {"reset_type": "init" if not seed else "random"}
        if os.environ.get("WALK_DIR") == "seed":
            self.direction = 1 if seed % 2 == 0 else -1
        if os.environ.get("WALK_COURSE") == "multi_stride":
            # the walk_stride arena trial: straight from the official P1 reset to the
            # arena edge at v_des 1.1, 1.15, ..., 1.45 (seed % 8)
            self.course_kind = "straight"
            self.v_des = 1.1 + 0.05 * (seed % 8)
        if os.environ.get("WALK_COURSE") == "multi4":
            # gait practice: straight (to the arena edge) and a circle (R = 2.8 m: inside the arena) each way
            self.course_kind = ["straight", "circle", "circle"][seed % 3]
            self.direction = [1, 1, -1][seed % 3]
            self.radius = 2.8
        if os.environ.get("WALK_COURSE") == "multi3":
            # U-turn practice: reverse left, reverse right, circle left, straight
            self.course_kind = ["uturn", "uturn", "circle", "straight"][seed % 4]
            self.direction = [1, -1, 1, 1][seed % 4]
        if os.environ.get("WALK_COURSE") == "multi2":
            # turning practice that stays inside the arena: circles both ways and straight
            self.course_kind = ["circle", "circle", "straight"][seed % 3]
            self.direction = [1, -1, 1][seed % 3]
            if os.environ.get("WALK_VARY", "0") == "1":
                self.v_des = [1.2, 1.2, 1.3][seed % 3]
        if os.environ.get("WALK_COURSE") == "multi":
            # robustness practice: seed % 3 picks straight, turn left, turn right
            self.course_kind = ["straight", "turn", "turn"][seed % 3]
            self.direction = [1, 1, -1][seed % 3]
            if os.environ.get("WALK_VARY", "0") == "1":
                # and a speed per condition: the gait must not hinge on one v_des
                self.v_des = [1.3, 1.15, 1.45][seed % 3]

    def __init__(self):
        reset = os.environ.get("WALK_RESET", "init")
        if reset == "mixed":
            reset = "init"
        self.env_kwargs = {"reset_type": reset}
        self.course_kind = os.environ.get("WALK_COURSE", "circle")
        self.radius = float(os.environ.get("WALK_R", "3.0"))
        self.direction = int(os.environ.get("WALK_DIR", "1")) if os.environ.get("WALK_DIR", "1") != "seed" else 1
        self.v_des = float(os.environ.get("WALK_V", "1.3"))
        self.mode = float(os.environ.get("WALK_MODE", "1"))
        self.course = None
        self.wp_seed = int(os.environ.get("WALK_WP_SEED", "0"))
        self.rec = []
        self.pushes = []
        self.parked = False

    def _course(self, sim):
        if self.course is None:
            if os.environ.get("WALK_COURSE", "").startswith("multi"):
                self.set_seed_reset(sim.seed)  # the course mixtures pick by seed (search.py sets only task.seed)
            p = sim.d.body("pelvis").xpos[:2].copy()
            self.course = Course(self.course_kind, p, heading_of(sim), self.radius, self.direction, self.wp_seed)
            self.prev = p
            self.prog = 0.0
        return self.course

    def extra_sensors(self, sim):
        c = self._course(sim)
        p = sim.d.body("pelvis").xpos[:2]
        return [("walk_goal", [self.mode, self.v_des, c.heading(p, sim.d.time)]),
                ("l_toe_pos", sim.d.body("toes_l").xpos), ("r_toe_pos", sim.d.body("toes_r").xpos)] + muscle_constants(sim)

    def camera(self, m, d, cam):
        # side view from the walker's left, following the pelvis
        root = d.body("pelvis").xpos
        fwd = d.body("root").xmat.reshape(3, 3)[:, 0]
        psi = math.atan2(fwd[1], fwd[0])
        cam.lookat[:] = [root[0], root[1], 0.75]
        cam.distance = float(os.environ.get("WALK_CAM_DIST", "2.6"))
        cam.azimuth = math.degrees(psi - math.pi / 2) + float(os.environ.get("WALK_CAM_AZ", "0"))
        cam.elevation = -8

    def park_opponent(self, sim):
        opp = sim.u.opponent
        opp.opponent_policy = "stationary"
        opp.set_opponent_pose([5.9, 5.9, 0.0])

    def apply_push(self, sim):
        """WALK_PUSH=N: robustness test (never in official runs): a horizontal push of N newtons
        for WALK_PUSH_T s (0.2) at 2, 4, 6, ... s, cycling left, forward, right, backward
        relative to the pelvis heading. MyoSuite steps the robot's own MjData, so the force
        goes there (sim.d is a synced copy)."""
        push = float(os.environ.get("WALK_PUSH", "0"))
        rid = sim.m.body(sim.root).id
        xf = sim.u.robot.mj_data.xfrc_applied
        xf[rid, :] = 0.0
        if push <= 0:
            return
        dur = float(os.environ.get("WALK_PUSH_T", "0.2"))
        k = int(sim.d.time // 2.0)
        if k >= 1 and sim.d.time - 2.0 * k < dur:
            psi = heading_of(sim) + [math.pi / 2, 0.0, -math.pi / 2, math.pi][(k - 1) % 4]
            xf[rid, 0] = push * math.cos(psi)
            xf[rid, 1] = push * math.sin(psi)
            if not self.pushes or self.pushes[-1] != k:
                self.pushes.append(k)

    def on_step(self, sim, obs, reward, info):
        if not self.parked:
            self.park_opponent(sim)
            self.parked = True
        self.apply_push(sim)
        d = sim.d
        c = self._course(sim)
        p = d.body("pelvis").xpos[:2].copy()
        c.t_now = d.time
        self.prog += c.progress(p, self.prev)
        self.prev = p
        ct = sim.foot_contacts()
        vel = d.subtree_linvel[sim.m.body(sim.root).id].copy()
        # muscle mechanical power (actuator force times actuator velocity: a
        # tension F < 0 while shortening v < 0 delivers positive work); positive
        # (concentric) work only
        power = d.actuator_force[sim.muscle_ids] * d.actuator_velocity[sim.muscle_ids]
        self.rec.append((d.time, p, float(d.body("pelvis").xpos[2]), heading_of(sim), vel.copy(),
                         ct["l"], ct["r"], c.error(p), float(np.sum(np.maximum(power, 0.0)))))

    def metrics(self, sim, log):
        rec = self.rec
        if len(rec) < 3:
            return {"distance": 0.0, "progress": 0.0}
        t = np.array([r[0] for r in rec])
        p = np.array([r[1] for r in rec])
        z = np.array([r[2] for r in rec])
        psi = np.unwrap(np.array([r[3] for r in rec]))
        v = np.array([r[4] for r in rec])
        cl = np.array([r[5] for r in rec])
        cr = np.array([r[6] for r in rec])
        err = np.array([r[7] for r in rec])
        pw = np.array([r[8] for r in rec])
        dt = float(np.median(np.diff(t)))
        seg = np.linalg.norm(np.diff(p, axis=0), axis=1)
        dist = float(np.sum(seg))
        after1 = t >= t[0] + 1.0
        fwd = np.stack([np.cos(psi), np.sin(psi)], axis=1)
        vf = np.sum(v[:, :2] * fwd, axis=1)
        speed = float(np.mean(vf[after1])) if after1.any() else 0.0
        last5 = t >= t[-1] - 5.0
        hs = np.linalg.norm(v[last5, :2], axis=1)
        # steps = entries into a stance chunk (the controller's own touchdown latch)
        labels = [row[1] for row in log]
        steps = 0
        for side in ("l", "r"):
            tag = f"{side}:{side}_stance"
            ttag = f"{side}:{side}_tstance"  # the turning loop's stance (turn_gait = 1)
            was = False
            for lab in labels:
                now = tag in lab or ttag in lab
                steps += int(now and not was)
                was = now
        dur = t[-1] - t[0]
        cadence = steps / dur if dur > 0 else 0.0
        yaw_rate = np.abs(np.diff(psi)) / dt
        # pelvis heading relative to the direction of motion (a yawing trunk)
        moving = np.linalg.norm(v[:, :2], axis=1) > 0.3
        vdir = np.arctan2(v[:, 1], v[:, 0])
        ydev = np.abs((psi - vdir + np.pi) % (2 * np.pi) - np.pi)
        yaw_dev = float(np.mean(ydev[moving])) if moving.any() else 0.0
        k = max(1, int(round(1.0 / dt)))
        turn1 = np.abs(psi[k:] - psi[:-k]) if len(psi) > k else np.array([0.0])
        mass = float(sim.m.body_subtreemass[sim.m.body(sim.root).id])
        work = float(np.sum(pw) * dt)
        acts = np.array([row[2] for row in log]) if log else np.zeros((1, sim.n))
        return {
            "distance": round(dist, 3),
            "progress": round(self.prog, 3),
            "speed": round(speed, 3),
            "speed_last5": round(float(np.mean(hs)), 3),
            "cadence": round(cadence, 3),
            "step_length": round(speed / cadence, 3) if cadence > 0 else 0.0,
            "turn_rate": round(float(np.mean(yaw_rate)), 3),
            "yaw_dev": round(yaw_dev, 3),
            "turn_max_deg_s": round(float(np.degrees(np.max(turn1))), 1),
            "path_err": round(float(np.mean(err)), 3),
            "pelvis_z": round(float(np.mean(z)), 3),
            "pelvis_z_min": round(float(np.min(z)), 3),
            "effort": round(float(np.mean(acts ** 2)), 4),
            "cot_mech": round(work / (mass * 9.81 * max(dist, 0.1)), 3),
            "fallen": bool(z[-1] < 0.5),
            "out_of_bounds": bool(np.any(np.abs(p[-1]) > 6.5)),
            "pushes": len(self.pushes),
            "reached": self.course.reached if self.course is not None else 0,
        }

    def score(self, m):
        if "error" in m or not np.isfinite(m.get("effort", 0.0)):
            return -1e9
        prog = m.get("progress", 0.0)
        t = m.get("time", 0.0)
        if m.get("out_of_bounds") and not m.get("fallen") and self.course_kind in ("straight", "turn"):
            t = self.seconds  # walked out of the arena upright: full survival (open courses only)
        s = t + 2.0 * prog + 3.0 * m.get("reached", 0) - 3.0 * m.get("path_err", 0.0) - 5.0 * m.get("effort", 0.0)
        # walking pace: pay progress but penalise running away from v_des
        s -= 2.0 * abs(m.get("speed", 0.0) - self.v_des) * m.get("time", 0.0) / 20.0
        s -= float(os.environ.get("WALK_YAW_W", "0")) * m.get("yaw_dev", 0.0)
        # WALK_SPEED_W: hold the pace (an absolute penalty on |speed - v_des|, so a longer
        # step cannot be bought by walking slower)
        s -= float(os.environ.get("WALK_SPEED_W", "0")) * abs(m.get("speed", 0.0) - self.v_des)
        # WALK_STEP_W: longer, human steps (penalise cadence above WALK_CADENCE steps/s while upright)
        # WALK_STEP_REWARD: pay step length directly (m) while upright
        if not m.get("fallen"):
            s += float(os.environ.get("WALK_STEP_REWARD", "0")) * max(0.0, m.get("step_length", 0.0))
        w = float(os.environ.get("WALK_STEP_W", "0"))
        if w > 0 and not m.get("fallen"):
            s -= w * max(0.0, m.get("cadence", 0.0) - float(os.environ.get("WALK_CADENCE", "2.0")))
        return s


TASK = MyoWalkTask


def muscle_constants(sim):
    """Peak force and length range of every muscle, as constant sensor blocks
    (the handshake does not carry them; MyoWalkHip needs them)."""
    fmax = sim.m.actuator_gainprm[sim.muscle_ids, 2]
    rng = sim.lr[:, 1] - sim.lr[:, 0]
    return [("muscle_fmax", fmax), ("muscle_range", rng)]
