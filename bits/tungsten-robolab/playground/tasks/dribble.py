"""Dribble: a stationary basketball dribble on the pivot body.

The pelvis sits on the muscle-driven yaw pivot at a knee-bent athletic height;
the legs stand on the floor, the spine leans forward, and the right hand
dribbles a size-7 basketball (0.62 kg, r = 0.12 m, hollow-shell inertia) at
the dribbler's right side. The ball bounces off the floor with a coefficient
of restitution of 0.77, calibrated to the FIBA drop test (dropped from 1.8 m,
bottom of ball, a ball must rebound to 1.035-1.085 m; this one rebounds to
1.070 m). The ball/floor contact is an explicit pair with a negative solref:
a mass-normalised spring-damper, stiffness 40000 and damping 35, whose
restitution exp(-pi * zeta) does not depend on impact speed (drop tests
from 0.5-2.0 m agree to +-0.006 at the 1 ms timestep this task uses). The
hands meet the ball through their own critically damped (non-bouncy)
contact pairs, like skin on leather.

The ball starts held in the right hand by a grip weld (fingers closed on
it); the skill lifts it, throws it down and opens the grip (`grip:r:0`)
partway through that first stroke, as a player starts a dribble. After that
nothing touches the ball but the floor and the body (no assist forces, no
kinematic playback).

Sensors added for the skill (all world frame):
  ball_pos    x y z of the ball centre
  ball_vel    vx vy vz
  ball_apex   x y z t: where the ball's next apex will be and how long until
              it gets there (ballistic flight, through a floor bounce with the
              nominal COR when the ball is falling)
  ball_touch  normal force of the ball on the right / left hand, in ball weights
  ball_floor  normal force of the floor on the ball, in ball weights
  ball_held   1 while a grip weld holds the ball
  ball_home   x y of the spot the dribble should stay on
  ball_rise   x y z vx vy vz t: the state the ball rises from after its next
              bounce (or now, if it is rising), t seconds from now; the
              bounce keeps the horizontal velocity less K_ROLL of the contact
              point's slip (measured on this contact pair)

Metrics: a dribble is a floor bounce preceded (since the previous bounce) by
a right-hand touch and landing within LOST_RADIUS of home; the run is lost at
the first bounce that is not (or when the ball stays down on the floor).
`dribbles` is the consecutive count from the first bounce, `freq_hz` their
rate, `apex_mean/std` the ball-centre height each cycle reaches, `drift_*`
the bounce spots' distance from home, `body_hits` ball contacts with any
body part but the hand, `effort` the mean squared commanded activation.
`split` says who does the work while dribbling: each muscle group's share of
the activation and effort (overall and within the upper body), the positive
muscle work and joint excursion per upper-body joint group, and the push's
(palm moving down) and recovery's work split between the upper arm's swing,
humeral rotation, elbow, wrist and fingers. `x_ok`, `x_rate`,
`trunk_share_if_dribbling` and `shoulder_work_share` are flat copies for the
arena.
`score` (the practice objective) is dribbles plus controlled time, with
shaping for strikes and penalties for drift, apex spread, an apex outside
0.75-0.95 m, a rate under 1.5 Hz and body hits.

Bodies: `DribbleTask.body_kind` v1 (default: base humanoid, rigid spread
paddle, bin/robolab_dribble) or v3 (tasks/dribble_v3.py or DRIBBLE_BODY=v3:
the v2 body with fingered hands, bin/robolab_dribble_v3, home spot
HOME_V3, front camera); v3paddle is the v2 body with the paddle (ablation).

    python playground/tasks/dribble.py --fiba          # FIBA drop test
    python playground/tasks/dribble.py --trials 10 --params params/dribble.txt \
        --out out/dribble_metrics.json                  # seeded trials (DRIBBLE_SEED)
"""

import math
import os
import sys

import mujoco
import numpy as np

_PLAYGROUND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PLAYGROUND not in sys.path:  # also runnable as a script (see main below)
    sys.path.insert(0, _PLAYGROUND)

from bridge import Task  # noqa: E402
from body import HumanoidBuilder, HumanoidV2Builder  # noqa: E402

BALL_R = 0.12
BALL_M = 0.62
BALL_I = 2.0 / 3.0 * BALL_M * BALL_R ** 2  # thin spherical shell
COR = 0.77
G = 9.81
# the right hand's bounce spot: forward and to the right of the pelvis (the
# left hand's is its mirror). The v3 body brings it in under the dribbling
# hand's elbow (the forearm pumps in a sagittal plane) and a little forward;
# the crossover V spans the two spots.
HOME = (0.48, -0.36)
HOME_V3 = (float(os.environ.get("DRIBBLE_HOME_X", "0.5")), float(os.environ.get("DRIBBLE_HOME_Y", "-0.28")))
UNDER = (0.15, 0.0)   # bounces also belong under the torso (between-the-legs passes)
ROOT = os.path.dirname(_PLAYGROUND)
Z_HOLD = 0.99         # palm height the ball is held at before the first dribble
LOST_RADIUS = 0.45    # a bounce farther than this from every zone is out of control
MOVE_NAMES = {"D": "dribble", "X": "crossover", "B": "between the legs"}
# Stance joint angles the task starts in (the skill holds the same stance).
STANCE = {
    "hip_flex": 0.57, "hip_abd": 0.10, "knee": 1.14, "ankle": -0.57,
    "spine_flex": 0.45,
}
PELVIS_HEIGHT = 0.80
# upper-body joints whose muscle work and excursion the metrics split by group
UPPER_JOINTS = ["spine_flex", "spine_lat", "spine_rot"] + [
    f"{s}_{j}" for s in "rl" for j in ("shoulder_flex", "shoulder_abd", "shoulder_rot", "elbow", "wrist_flex",
                                        "wrist_dev", "finger_mcp", "finger_pip")]


def joint_group(name):
    """trunk / shoulder / elbow / wrist / fingers for a joint or muscle name."""
    for g, key in (("trunk", "spine"), ("shoulder", "shoulder"), ("elbow", "elbow"), ("wrist", "wrist"),
                   ("fingers", "finger")):
        if key in name:
            return g
    return "legs"
PALM_Z = -0.12        # where the ball meets the hand: the finger pads, 12 cm from the wrist


class DribbleBuilder(HumanoidBuilder):
    """The stock humanoid with spread-finger hands: the stock hand box (9 x 11
    cm, a closed mitten) becomes 16 cm wide and 18 cm long from the wrist,
    about an adult hand with the fingers spread over a ball. Same mass (0.4
    kg), same palm and grip sites."""

    HAND = 'type="box" pos="0 0 -0.05" size="0.018 0.045 0.055"'
    SPREAD = 'type="box" pos="0 0 -0.09" size="0.018 0.08 0.09"'

    def _arm(self, side):
        xml = super()._arm(side)
        assert self.HAND in xml, "body.py hand geom changed; update DribbleBuilder"
        return xml.replace(self.HAND, self.SPREAD)


class DribbleFingerBuilder(HumanoidV2Builder):
    """The human-calibrated v2 body (joint speeds, damping) with the
    articulated hand (palm + two-segment finger plate on knuckle and middle
    joints), spread for the ball: the palm 12 cm wide, the finger plate
    16 cm (fingers spread over a ball), same masses."""

    SIZES = (('size="0.018 0.045 0.035"', 'size="0.018 0.06 0.035"'),
             ('size="0.011 0.043 0.022"', 'size="0.011 0.08 0.022"'),
             ('size="0.009 0.041 0.018"', 'size="0.009 0.08 0.018"'))

    def __init__(self, mode):
        super().__init__(mode, strength=1.0, wrists=True, fingers=True)

    def _arm(self, side):
        xml = super()._arm(side)
        for a, b in self.SIZES:
            assert a in xml, "body.py finger hand changed; update DribbleFingerBuilder"
            xml = xml.replace(a, b)
        return xml


class DribblePaddleV2Builder(HumanoidV2Builder):
    """The v2 body with the v1 rigid spread paddle for a hand (no fingers):
    the finger comparison's control."""

    def __init__(self, mode):
        super().__init__(mode, strength=1.0, wrists=True, fingers=False)

    def _arm(self, side):
        xml = super()._arm(side)
        assert DribbleBuilder.HAND in xml, "body.py hand geom changed; update DribblePaddleV2Builder"
        return xml.replace(DribbleBuilder.HAND, DribbleBuilder.SPREAD)


# a floor bounce's horizontal velocity: v' = v - K_ROLL (v + u), u the contact
# point's velocity from spin (w x -r z). Measured on this contact pair (30
# random throws, 1.5-4.5 m/s down, +-2 m/s across, +-15 rad/s spin; rms error
# 0.007 m/s): 0.17, well short of the 0.4 a shell that reaches rolling would
# lose, since the soft floor contact slips.
K_ROLL = 0.17
SHOULDER_SHARE = 0.25  # practice target: the upper arm swing's share of the push's positive work
SHOULDER_WEIGHT = float(os.environ.get("DRIBBLE_SHOULDER_WEIGHT", "6"))  # score per unit share above it


class DribbleTask(Task):
    """`body_kind` v1 (the default): the base humanoid with a rigid
    spread-paddle hand, run by bin/robolab_dribble (skills/dribble.w). v3
    (DRIBBLE_BODY=v3, or the dribble_v3 task): the human-calibrated v2 body
    with fingered hands, run by bin/robolab_dribble_v3 (skills/dribble_v3.w)."""

    name = "dribble"
    body_kind = os.environ.get("DRIBBLE_BODY", "v1")

    @property
    def controller(self):
        return None if self.body_kind == "v1" else os.path.join(ROOT, "bin", "robolab_dribble_v3")

    @property
    def home(self):
        return HOME if self.body_kind == "v1" else HOME_V3

    @property
    def home_l(self):
        return (self.home[0], -self.home[1])

    @property
    def zones(self):
        return (self.home, self.home_l, UNDER)

    @property
    def hand_geoms(self):
        return ("hand", "fingers1", "fingers2") if self.body_kind == "v3" else ("hand",)
    mode = "pivot"
    timestep = 0.001
    control_dt = 0.005
    seconds = 15.0
    pelvis_height = PELVIS_HEIGHT

    # ---- scene -----------------------------------------------------------

    def builder(self):
        if self.body_kind == "v1":
            return DribbleBuilder(self.mode, strength=self.strength, wrists=True)
        if self.body_kind == "v3paddle":
            return DribblePaddleV2Builder(self.mode)
        return DribbleFingerBuilder(self.mode)

    def xml_extras(self):
        # Ball body placed where it sits in the right hand at the model's
        # reference pose (arm hanging), so the grip weld's relative pose is
        # "ball under the palm"; reset() moves body and ball to the stance.
        H = self.pelvis_height
        hand = np.array([0.0, -0.19, H + 0.10 + 0.42 - 0.30 - 0.26])
        ball = hand + np.array(self.grip_offset())
        world = f"""
    <body name="ball" pos="{ball[0]:.4f} {ball[1]:.4f} {ball[2]:.4f}">
      <freejoint name="ball"/>
      <inertial pos="0 0 0" mass="{BALL_M}" diaginertia="{BALL_I:.6f} {BALL_I:.6f} {BALL_I:.6f}"/>
      <geom name="ball" type="sphere" size="{BALL_R}" contype="4" conaffinity="2"
            friction="0.9 0.005 0.0005" rgba="0.85 0.42 0.12 1" material="ballskin"/>
    </body>
    <site name="home" pos="{self.home[0]} {self.home[1]} 0.001" size="0.13 0.13 0.001" type="cylinder" rgba="0.2 0.3 0.8 0.15"/>"""
        assets = ('<texture name="ballskin" type="cube" builtin="checker" rgb1="0.86 0.43 0.12" '
                  'rgb2="0.2 0.12 0.08" width="64" height="64"/>'
                  '<material name="ballskin" texture="ballskin" texuniform="false" specular="0.2"/>')
        pairs = [
            '<pair geom1="ball" geom2="floor" solref="-40000 -35" solimp="0.99 0.99 0.001 0.5 2" '
            'friction="0.8 0.8 0.005 0.0005 0.0005"/>',
        ]
        for side in "rl":
            for g in self.hand_geoms:
                pairs.append(f'<pair geom1="ball" geom2="{side}_{g}" solref="0.004 1" solimp="0.95 0.99 0.001 0.5 2" '
                             f'friction="1.0 1.0 0.005 0.0005 0.0005"/>')
        contact = "</worldbody>\n  <contact>\n    " + "\n    ".join(pairs) + "\n  </contact>\n  <worldbody>"
        equality = '<weld name="grip_r" body1="r_hand" body2="ball" solref="0.01 1"/>'
        return {"extra_world": world + contact, "extra_assets": assets, "extra_equality": equality}

    def grip_offset(self):
        """Ball centre in the right hand's frame when held: under the palm face."""
        return (-0.018 - BALL_R - 0.002, 0.0, PALM_Z)

    def perturbation(self):
        """Seeded trial perturbation (env DRIBBLE_SEED, 0 = none): the ball sits
        up to 2 cm off-centre in the hand, along and across the palm."""
        seed = getattr(self, "seed", None)  # the arena sets task.seed
        seed = int(os.environ.get("DRIBBLE_SEED", "0")) if seed is None else int(seed)
        if seed == 0:
            return np.zeros(3)
        rng = np.random.default_rng(seed)
        return np.array([0.0, rng.uniform(-0.02, 0.02), rng.uniform(-0.02, 0.02)])

    # ---- episode ---------------------------------------------------------

    def stance_qpos(self, m, d):
        for side in "lr":
            for j, v in STANCE.items():
                if j.startswith("spine"):
                    continue
                d.joint(f"{side}_{j}").qpos[0] = v
        d.joint("spine_flex").qpos[0] = STANCE["spine_flex"]
        # left arm: guard position in front of the body
        for j, v in {"shoulder_flex": 0.6, "shoulder_abd": 0.25, "elbow": 1.3}.items():
            d.joint(f"l_{j}").qpos[0] = v
        # fingers (the v3 hand): relaxed, a little cupped
        for side in "lr":
            for j, v in {"finger_mcp": 0.1, "finger_pip": 0.05}.items():
                if mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_JOINT, f"{side}_{j}") >= 0:
                    d.joint(f"{side}_{j}").qpos[0] = v
        # right arm: holding the ball over HOME at the top of the dribble
        self.solve_hold(m, d, np.array([self.home[0], self.home[1], Z_HOLD]))

    ARM = ("shoulder_flex", "shoulder_abd", "shoulder_rot", "elbow", "wrist_flex", "wrist_dev")

    def solve_hold(self, m, d, target):
        """Right-arm angles with the palm centre at `target` facing down (the
        same palm point and damped Gauss-Newton IK the skill uses), on
        MuJoCo's own kinematics."""
        seed = np.array([0.55, 0.05, -0.5, 1.4, -0.05, 0.1])
        adr = [m.jnt_qposadr[m.joint("r_" + j).id] for j in self.ARM]
        rng = [m.jnt_range[m.joint("r_" + j).id] for j in self.ARM]
        pc = np.array([-0.018, 0.0, PALM_Z])

        def res(q):
            d.qpos[adr] = q
            mujoco.mj_kinematics(m, d)
            h = d.body("r_hand")
            R = h.xmat.reshape(3, 3)
            return np.concatenate([h.xpos + R @ pc - target, 0.5 * (-R[:, 0] - np.array([0, 0, -1.0]))])

        q = seed.copy()
        for _ in range(40):
            r = res(q)
            J = np.zeros((6, 6))
            for k in range(6):
                dq = np.zeros(6)
                dq[k] = 1e-5
                J[:, k] = (res(q + dq) - r) / 1e-5
            q = q + np.linalg.solve(J.T @ J + 2e-3 * np.eye(6), -J.T @ r - 2e-3 * (q - seed))
            q = np.array([np.clip(v, lo + 0.02, hi - 0.02) for v, (lo, hi) in zip(q, rng)])
        d.qpos[adr] = q

    def reset(self, m, d):
        self.stance_qpos(m, d)
        d.eq_active[m.equality("grip_r").id] = 1
        mujoco.mj_forward(m, d)
        hand = d.body("r_hand")
        R = hand.xmat.reshape(3, 3)
        adr = m.jnt_qposadr[m.joint("ball").id]
        d.qpos[adr:adr + 3] = hand.xpos + R @ (np.array(self.grip_offset()) + self.perturbation())
        d.qpos[adr + 3:adr + 7] = hand.xquat
        mujoco.mj_forward(m, d)
        self.ball_id = m.body("ball").id
        self.ball_geom = m.geom("ball").id
        self.floor_geom = m.geom("floor").id
        self.hand_bodies = {m.body(f"{side}_{g}").id: side for side in "rl" for g in self.hand_geoms}
        self.weld = m.equality("grip_r").id
        self.ball_w = BALL_M * G
        # event log
        self.events = []        # (t, kind, x, y, z) kinds: floor, touch_r, touch_l, body, release
        self.cycle_max = 0.0
        self.apexes = []
        self.in_floor = False
        self.in_touch = {"r": False, "l": False}
        self.in_body = False
        self.released_t = None
        self.lost_t = None
        self.lost_why = ""
        self.last_floor = None
        self.touched_since_floor = True
        self.dribbles = 0
        self.dribble_times = []
        self.bounce_xy = []
        self.low_since = None
        self.release_v = []     # ball vz as the striking contact of each cycle ends
        self.struck = False
        self.ball_dof = m.jnt_dofadr[m.joint("ball").id]
        # moves the skill announces: move:<D|X|B>:<R|L> as a push starts,
        # plan:<D|X|B>:<R|L> when it picks the next one
        self.moves = []
        self.plan = None
        # joint work and excursion while dribbling (after the release, until
        # the ball is lost), per upper-body joint: muscle torque x joint speed
        self.work_joints = [j for j in UPPER_JOINTS if mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_JOINT, j) >= 0]
        self.work_dofs = np.array([m.jnt_dofadr[m.joint(j).id] for j in self.work_joints])
        self.work_pos = np.zeros(len(self.work_joints))
        self.work_abs = np.zeros(len(self.work_joints))
        self.work_path = np.zeros(len(self.work_joints))
        # the same positive work split by the stroke's direction: while that
        # arm's palm moves down (the push: swing and carry) or up (recovery)
        self.work_side = np.array([j[0] if j[1] == "_" else "" for j in self.work_joints])
        self.work_down = np.zeros(len(self.work_joints))
        self.work_up = np.zeros(len(self.work_joints))
        self.palm_z = {sd: float(d.site(sd + "_palm").xpos[2]) for sd in "rl"}

    def on_command(self, m, d, cmd):
        if cmd.startswith("move:") or cmd.startswith("plan:"):
            _, kind, hand = cmd.split(":")
            if cmd.startswith("plan:"):
                self.plan = (kind, hand)
                return
            recv = hand if kind == "D" else ("L" if hand == "R" else "R")
            self.moves.append({"type": kind, "hand": hand, "recv": recv, "t": round(d.time, 3),
                               "contact": False, "released": False, "bounces": 0, "body": 0, "outcome": None,
                               "miss": None})
            return
        if cmd.startswith("grip:r:"):
            on = cmd.endswith(":1")
            if not on and d.eq_active[self.weld]:
                self.released_t = d.time
                self.events.append((d.time, "release", 0, 0, 0))
            d.eq_active[self.weld] = 1 if on else 0

    # ---- contact forces ---------------------------------------------------

    def ball_forces(self, m, d):
        """Normal force on the ball from the floor, right hand, left hand, other body (N)."""
        out = {"floor": 0.0, "r": 0.0, "l": 0.0, "body": 0.0}
        f6 = np.zeros(6)
        for i in range(d.ncon):
            con = d.contact[i]
            if con.geom1 == self.ball_geom:
                other = con.geom2
            elif con.geom2 == self.ball_geom:
                other = con.geom1
            else:
                continue
            mujoco.mj_contactForce(m, d, i, f6)
            fn = abs(f6[0])
            if other == self.floor_geom:
                out["floor"] += fn
            else:
                side = self.hand_bodies.get(m.geom_bodyid[other])
                out[side or "body"] += fn
        return out

    def predict_apex(self, p, v, spin=None):
        """Where and when the ball's next apex is: ballistic flight, and when
        the ball is falling, a floor bounce with the nominal COR that keeps its
        horizontal velocity. (Floor friction really rolls the contact, which
        costs the ball up to 40% of its horizontal speed at a bounce; a
        spin-aware prediction aims better but the tuned passes were practised
        against this one, so changing it means practising them again.)"""
        x, y, z = p
        vx, vy, vz = v
        if vz > 0.0:
            t = vz / G
            return [x + vx * t, y + vy * t, z + vz * t - 0.5 * G * t * t, t]
        h = max(z - BALL_R, 0.0)
        tf = (vz + math.sqrt(vz * vz + 2 * G * h)) / G
        vi = math.sqrt(vz * vz + 2 * G * h)
        vo = COR * vi
        tu = vo / G
        t = tf + tu
        if spin is None:
            return [x + vx * t, y + vy * t, BALL_R + vo * vo / (2 * G), t]
        # v3: the bounce costs the horizontal velocity K_ROLL of the contact
        # point's slip (see K_ROLL)
        ux, uy = -BALL_R * spin[1], BALL_R * spin[0]
        wx, wy = vx - K_ROLL * (vx + ux), vy - K_ROLL * (vy + uy)
        return [x + vx * tf + wx * tu, y + vy * tf + wy * tu, BALL_R + vo * vo / (2 * G), t]

    def predict_rise(self, p, v, spin):
        """The ball's rising flight after its next bounce (or the one it is on):
        [x, y, z, vx, vy, vz, t] of the state it rises from, t seconds from
        now (the bounce, for a falling ball; now, for a rising one), with the
        bounce model of predict_apex (K_ROLL)."""
        x, y, z = p
        vx, vy, vz = v
        if vz > 0.0 or spin is None:
            return [x, y, z, vx, vy, vz, 0.0]
        h = max(z - BALL_R, 0.0)
        vi = math.sqrt(vz * vz + 2 * G * h)
        tf = (vz + vi) / G
        ux, uy = -BALL_R * spin[1], BALL_R * spin[0]
        return [x + vx * tf, y + vy * tf, BALL_R, vx - K_ROLL * (vx + ux), vy - K_ROLL * (vy + uy), COR * vi, tf]

    def extra_sensors(self, m, d):
        p = d.body("ball").xpos.copy()
        adr = m.jnt_dofadr[m.joint("ball").id]
        v = d.qvel[adr:adr + 3].copy()
        spin = None if self.body_kind == "v1" else d.body("ball").xmat.reshape(3, 3) @ d.qvel[adr + 3:adr + 6]
        f = self.ball_forces(m, d) if hasattr(self, "ball_geom") else {"floor": 0, "r": 0, "l": 0, "body": 0}
        w = BALL_M * G
        held = float(d.eq_active[m.equality("grip_r").id])
        return [
            ("ball_pos", p), ("ball_vel", v), ("ball_apex", self.predict_apex(p, v, spin)),
            ("ball_touch", [f["r"] / w, f["l"] / w]), ("ball_floor", [f["floor"] / w]),
            ("ball_held", [held]), ("ball_home", list(self.home)),
            ("ball_rise", self.predict_rise(p, v, spin)),
        ]

    # ---- event tracking (every physics step) -------------------------------

    def before_step(self, m, d):
        if not hasattr(self, "ball_geom"):
            return
        p = d.body(self.ball_id).xpos
        t = d.time
        f = self.ball_forces(m, d)
        w = self.ball_w
        floor = f["floor"] > 0.2 * w
        if self.released_t is not None and self.lost_t is None:
            qd = d.qvel[self.work_dofs]
            pw = d.qfrc_actuator[self.work_dofs] * qd * m.opt.timestep
            self.work_pos += np.maximum(pw, 0.0)
            for sd in "rl":
                z = float(d.site(sd + "_palm").xpos[2])
                down = (z - self.palm_z[sd]) / m.opt.timestep < -0.2
                self.palm_z[sd] = z
                mask = self.work_side == sd
                (self.work_down if down else self.work_up)[mask] += np.maximum(pw[mask], 0.0)
            self.work_abs += np.abs(pw)
            self.work_path += np.abs(qd) * m.opt.timestep
            self.cycle_max = max(self.cycle_max, float(p[2]))
            if floor and not self.in_floor:
                self.events.append((t, "floor", float(p[0]), float(p[1]), float(p[2])))
                r = min(math.hypot(p[0] - z[0], p[1] - z[1]) for z in self.zones)
                for mv in self.moves:
                    if mv["released"] and mv["outcome"] is None:
                        mv["bounces"] += 1
                        if mv["bounces"] >= 2:
                            mv["outcome"] = "fail"
                if not self.touched_since_floor:
                    self.lose(t, "two floor bounces without a touch")
                elif r > LOST_RADIUS:
                    self.lose(t, f"bounced {r:.2f} m from home")
                else:
                    if self.last_floor is not None:
                        self.apexes.append(self.cycle_max)
                        self.dribbles += 1
                        self.dribble_times.append(t)
                    self.bounce_xy.append((float(p[0]), float(p[1]), self.open_move_type()))
                    self.last_floor = t
                    self.touched_since_floor = False
                    self.struck = False
                    self.cycle_max = 0.0
            vz = float(d.qvel[self.ball_dof + 2])
            for side in "rl":
                touch = f[side] > 0.3 * w
                if touch and not self.in_touch[side]:
                    self.events.append((t, "touch_" + side, float(p[0]), float(p[1]), float(p[2])))
                    self.touched_since_floor = True
                    self.move_touch(side.upper())
                if self.in_touch[side] and not touch:
                    self.move_release(side.upper())
                if self.in_touch[side] and not touch and vz < -1.0 and not self.struck:
                    self.release_v.append(vz)
                    self.struck = True
                self.in_touch[side] = touch
            # how close the rising ball comes to the receiving palm after the
            # bounce (horizontal): a dense measure of an aimed pass
            if vz > 0.0:
                for mv in self.moves:
                    if mv["released"] and mv["outcome"] is None and mv["bounces"] >= 1:
                        palm = d.site(mv["recv"].lower() + "_palm").xpos
                        dist = float(math.hypot(p[0] - palm[0], p[1] - palm[1]))
                        mv["miss"] = dist if mv["miss"] is None else min(mv["miss"], dist)
            body = f["body"] > 0.3 * w
            if body and not self.in_body:
                self.events.append((t, "body", float(p[0]), float(p[1]), float(p[2])))
                open_moves = [mv for mv in self.moves if mv["outcome"] is None]
                if open_moves:
                    open_moves[0]["body"] += 1
            self.in_body = body
            # a bounce keeps the ball down at the floor for ~15-20 ms; rolling
            # or resting keeps it there
            if p[2] < BALL_R + 0.03:
                if self.low_since is None:
                    self.low_since = t
                elif t - self.low_since > 0.25:
                    self.lose(t, "ball stayed on the floor")
            else:
                self.low_since = None
        self.in_floor = floor

    def lose(self, t, why):
        if self.lost_t is None:
            self.lost_t = t
            self.lost_why = why
            for mv in self.moves:
                if mv["outcome"] is None and (mv["released"] or mv["contact"]):
                    mv["outcome"] = "fail"

    # A move is received at the first hand touch after its push released the
    # ball and the ball bounced: by the intended hand, a success.
    def move_touch(self, hand):
        for mv in self.moves:
            if mv["released"] and mv["outcome"] is None and mv["bounces"] >= 1:
                mv["outcome"] = "ok" if hand == mv["recv"] else "fail"
        if self.moves and not self.moves[-1]["released"] and self.moves[-1]["hand"] == hand:
            self.moves[-1]["contact"] = True

    def move_release(self, hand):
        if self.moves and self.moves[-1]["hand"] == hand and self.moves[-1]["contact"]:
            self.moves[-1]["released"] = True

    def open_move_type(self):
        for mv in self.moves:
            if mv["released"] and mv["outcome"] is None:
                return mv["type"]
        return "D"

    # ---- metrics -----------------------------------------------------------

    def metrics(self, m, d, log):
        out = {"time": round(d.time, 3)}
        n = self.dribbles
        out["dribbles"] = n
        start = self.released_t if self.released_t is not None else d.time
        end = self.lost_t if self.lost_t is not None else d.time
        out["controlled_s"] = round(max(0.0, end - start), 2)
        out["lost"] = self.lost_why or None
        if len(self.dribble_times) >= 2:
            span = self.dribble_times[-1] - self.dribble_times[0]
            out["freq_hz"] = round((len(self.dribble_times) - 1) / span, 3) if span > 0 else 0.0
        else:
            out["freq_hz"] = 0.0
        ap = np.array(self.apexes[1:] if len(self.apexes) > 2 else self.apexes)
        out["apex_mean"] = round(float(ap.mean()), 3) if len(ap) else 0.0
        out["apex_std"] = round(float(ap.std()), 3) if len(ap) else 0.0
        dxy = [b[:2] for b in self.bounce_xy if b[2] == "D"]
        if dxy:
            xy = np.array(dxy)
            hr, hl = self.home, self.home_l
            r = np.minimum(np.hypot(xy[:, 0] - hr[0], xy[:, 1] - hr[1]), np.hypot(xy[:, 0] - hl[0], xy[:, 1] - hl[1]))
            out["drift_mean"] = round(float(r.mean()), 3)
            out["drift_max"] = round(float(r.max()), 3)
            out["bounce_std_xy"] = [round(float(xy[:, 0].std()), 3), round(float(xy[:, 1].std()), 3)]
        else:
            out["drift_mean"] = out["drift_max"] = 0.0
            out["bounce_std_xy"] = [0.0, 0.0]
        out["body_hits"] = sum(1 for e in self.events if e[1] == "body")
        rv = [v for v in self.release_v if v < 0]
        out["strikes"] = len(rv)
        out["release_v"] = round(float(-np.mean(rv)), 2) if rv else 0.0
        acts = np.array([row[2] for row in log]) if log else np.zeros((1, 1))
        out["effort"] = round(float(np.mean(acts ** 2)), 4)
        out["split"] = self.split(m, log, start, end)
        # moves: success per type, consecutive successes from the start, and
        # ball-body contacts during each type (a pass that clips a leg but is
        # still received counts as a recovery, and is reported here)
        done = [mv for mv in self.moves if mv["outcome"] is not None]
        per = {}
        for k in "DXB":
            ms = [mv for mv in done if mv["type"] == k]
            ok = sum(1 for mv in ms if mv["outcome"] == "ok")
            miss = [mv["miss"] for mv in ms if mv["miss"] is not None]
            per[k] = {"attempts": len(ms), "ok": ok, "rate": round(ok / len(ms), 3) if ms else None,
                      "body_contacts": sum(1 for mv in ms if mv["body"] > 0),
                      "catch_miss": round(float(np.mean(miss)), 3) if miss else None}
        out["moves"] = per
        run = 0
        for mv in done:
            if mv["outcome"] != "ok":
                break
            run += 1
        out["moves_consecutive"] = run
        out["moves_failed"] = sum(1 for mv in done if mv["outcome"] != "ok")
        # flat copies for the arena (it keeps scalar metrics only)
        out["x_attempts"] = per["X"]["attempts"]
        out["x_ok"] = per["X"]["ok"]
        out["x_rate"] = per["X"]["rate"] if per["X"]["rate"] is not None else 0.0
        out["b_ok"] = per["B"]["ok"]
        sp = out["split"]
        trunk = sp.get("activation_share", {}).get("trunk_of_upper_body", 1.0)
        out["trunk_share_upper"] = trunk
        # arms-only trial: the trunk's share of the upper body's activation,
        # counted only for a run that keeps dribbling (>= 10 dribbles)
        out["trunk_share_if_dribbling"] = trunk if n >= 10 else 1.0
        out["shoulder_work_share"] = round(self.shoulder_share(out), 3)
        return out

    def split(self, m, log, start, end):
        """Who does the work while dribbling (from the release until the ball
        is lost): each muscle group's share of the summed activation and of
        the effort (squared activation), overall and within the upper body
        (trunk + arms); and each upper-body joint group's share of the
        positive muscle work and of the joint excursion (path length, rad)
        summed over both arms and the spine."""
        names = [m.actuator(i).name for i in range(m.nu)]
        rows = [row[2] for row in log if start <= row[0] <= end]
        out = {}
        if rows:
            acts = np.array(rows)
            groups = np.array(["arms" if joint_group(n) in ("shoulder", "elbow", "wrist", "fingers")
                               else joint_group(n) for n in names[:acts.shape[1]]])
            a1 = acts.mean(axis=0)
            a2 = (acts ** 2).mean(axis=0)
            for key, v in (("activation", a1), ("effort", a2)):
                tot = float(v.sum()) or 1.0
                up = float(v[groups != "legs"].sum()) or 1.0
                out[key + "_share"] = {g: round(float(v[groups == g].sum()) / tot, 3) for g in ("trunk", "arms", "legs")}
                out[key + "_share"]["trunk_of_upper_body"] = round(float(v[groups == "trunk"].sum()) / up, 3)
            out["trunk_mean_activation"] = round(float(a1[groups == "trunk"].mean()), 3)
        wg = {}
        for j, wp, pa in zip(self.work_joints, self.work_pos, self.work_path):
            g = joint_group(j)
            e = wg.setdefault(g, [0.0, 0.0])
            e[0] += float(wp)
            e[1] += float(pa)
        wtot = sum(v[0] for v in wg.values()) or 1.0
        ptot = sum(v[1] for g, v in wg.items() if g != "trunk") or 1.0
        out["positive_work_share"] = {g: round(v[0] / wtot, 3) for g, v in wg.items()}
        out["arm_excursion_share"] = {g: round(v[1] / ptot, 3) for g, v in wg.items() if g != "trunk"}
        # the arms' positive work on the downstroke (the push) and the
        # upstroke (recovery), by joint: shoulder flex+abd (the upper arm
        # swinging), humeral rotation, elbow, wrist, fingers
        def arm_key(j):
            if "shoulder_rot" in j:
                return "humeral_rotation"
            if "shoulder" in j:
                return "upper_arm_swing"
            return joint_group(j)
        for name, arr in (("push_work_share", self.work_down), ("recovery_work_share", self.work_up)):
            acc = {}
            for j, w in zip(self.work_joints, arr):
                if joint_group(j) != "trunk":
                    acc[arm_key(j)] = acc.get(arm_key(j), 0.0) + float(w)
            tot = sum(acc.values()) or 1.0
            out[name] = {k: round(v / tot, 3) for k, v in acc.items()}
        out["push_work_J"] = round(float(self.work_down[self.work_side != ""].sum()), 1)
        out["recovery_work_J"] = round(float(self.work_up[self.work_side != ""].sum()), 1)
        out["trunk_excursion_vs_arms"] = round(wg.get("trunk", [0, 0])[1] / ptot, 3)
        out["joints"] = {j: {"pos_work_J": round(float(wp), 2), "path_rad": round(float(pa), 2)}
                         for j, wp, pa in zip(self.work_joints, self.work_pos, self.work_path)}
        return out

    def score(self, metrics):
        mv = metrics.get("moves", {})
        if mv and (mv["X"]["attempts"] or mv["B"]["attempts"]):
            # the choreography: successful moves (passes weigh more), time in
            # control, failures and ball-body contacts
            s = mv["D"]["ok"] + 2.0 * mv["X"]["ok"] + 3.0 * mv["B"]["ok"]
            s += 0.3 * metrics.get("controlled_s", 0.0) - 2.0 * metrics.get("moves_failed", 0)
            s -= 0.5 * (mv["D"]["body_contacts"] + mv["X"]["body_contacts"] + mv["B"]["body_contacts"])
            s -= 2.0 * metrics.get("drift_mean", 0.0) + 3.0 * metrics.get("apex_std", 0.0)
            s -= self.shoulder_penalty(metrics)
            # reaching a pass counts (a run must not win by losing the ball
            # before it), and how near the rising ball comes to the receiving
            # palm grades the passes that miss
            s += 1.0 * mv["X"]["attempts"] + 1.5 * mv["B"]["attempts"]
            for k in "XB":
                if mv[k].get("catch_miss") is not None:
                    s -= 3.0 * mv[k]["catch_miss"]
            return s
        n = metrics.get("dribbles", 0)
        s = float(n) + 0.3 * metrics.get("controlled_s", 0.0)
        # shaping while the dribble is still being found: strikes that send the
        # ball down, and how hard (a waist-high dribble needs ~3.4 m/s)
        s += 0.3 * min(metrics.get("strikes", 0), 10) + 0.5 * min(metrics.get("release_v", 0.0), 4.0)
        if n >= 3:
            s -= 6.0 * metrics.get("apex_std", 0.0)
            s -= 4.0 * metrics.get("drift_mean", 0.0)
            apex = metrics.get("apex_mean", 0.0)
            s -= 4.0 * max(0.0, abs(apex - 0.85) - 0.1)
            f = metrics.get("freq_hz", 0.0)
            s -= 2.0 * max(0.0, 1.5 - f)
        s -= 2.0 * metrics.get("drift_mean", 0.0)
        s -= 0.5 * metrics.get("body_hits", 0)
        if n >= 3:
            s -= self.shoulder_penalty(metrics)
        return s

    @staticmethod
    def shoulder_share(metrics):
        """The shoulders' share of the arms' positive muscle work."""
        pw = metrics.get("split", {}).get("positive_work_share", {})
        arm = sum(pw.get(k, 0.0) for k in ("shoulder", "elbow", "wrist", "fingers"))
        return pw.get("shoulder", 0.0) / arm if arm > 0 else 0.0

    def shoulder_penalty(self, metrics):
        """v3 practice: the push should come from the elbow and wrist from a
        still upper arm, so the upper arm's swing (shoulder flexion and
        abduction) above SHOULDER_SHARE of the push's positive work costs
        score."""
        if self.body_kind == "v1":
            return 0.0
        swing = metrics.get("split", {}).get("push_work_share", {}).get("upper_arm_swing", 0.0)
        return SHOULDER_WEIGHT * max(0.0, swing - SHOULDER_SHARE)

    # ---- presentation ------------------------------------------------------

    def camera(self, m, d, cam):
        if self.body_kind == "v1":
            # nearly frontal, a little from the right: both hands, the
            # crossover lane in front and the gap between the feet in view
            cam.lookat[:] = [0.22, -0.04, 0.62]
            cam.distance = 3.4
            cam.azimuth = 160
            cam.elevation = -12
            return
        # v3: straight in front, a little above the hands: the ball's path
        # across the body (a crossover's V) lies in the picture plane
        cam.lookat[:] = [0.3, 0.0, 0.74]
        cam.distance = 3.3
        cam.azimuth = 180
        cam.elevation = -5

    def title(self):
        return "robolab: basketball dribble (pivot muscle humanoid)"

    def hud_text(self, m, d):
        state = "lost: " + self.lost_why if getattr(self, "lost_t", None) is not None else "in control"
        moves = getattr(self, "moves", [])
        kinds = {mv["type"] for mv in moves}
        if not (kinds - {"D"}):
            last = self.apexes[-1] if getattr(self, "apexes", None) else 0.0
            return f"dribbles {getattr(self, 'dribbles', 0)}   last apex {last:.2f} m   {state}"

        def name(kind, hand):
            if kind == "D":
                return f"dribble {hand}"
            return f"{MOVE_NAMES[kind]} {hand}->{'L' if hand == 'R' else 'R'}"
        now = name(moves[-1]["type"], moves[-1]["hand"]) if moves else "-"
        nxt = name(*self.plan) if self.plan else "-"
        oks = "  ".join(f"{k} {sum(1 for mv in moves if mv['type'] == k and mv['outcome'] == 'ok')}/"
                        f"{sum(1 for mv in moves if mv['type'] == k and mv['outcome'] is not None)}" for k in "DXB")
        return f"move {len(moves)}: {now}   next: {nxt}   ok {oks}   {state}"


TASK = DribbleTask


# ---- reproducible checks: FIBA drop test and seeded trials -------------------
#
#   python playground/tasks/dribble.py --fiba
#   python playground/tasks/dribble.py --trials 10 --params params/dribble.txt \
#       --out out/dribble_metrics.json
#   python playground/tasks/dribble.py --practice --seeds 0,1,2,3 --seconds 8 \
#       --gens 45 --sigma 0.08 --init params/dribble.txt --out params/new.txt

def fiba_drop(drop=1.8):
    """Drop the ball from `drop` m (bottom of ball) onto this task's floor pair
    and return the rebound height of the bottom of the ball (FIBA: 1.035-1.085 m
    from 1.8 m)."""
    task = DribbleTask()
    m = mujoco.MjModel.from_xml_string(task.xml(task.builder()))
    d = mujoco.MjData(m)
    task.reset(m, d)
    d.eq_active[:] = 0
    adr = m.jnt_qposadr[m.joint("ball").id]
    dof = m.jnt_dofadr[m.joint("ball").id]
    d.qpos[adr:adr + 3] = [3.0, 3.0, drop + BALL_R]
    d.qvel[dof:dof + 6] = 0.0
    mujoco.mj_forward(m, d)
    prev = 0.0
    while d.time < 3.0:
        mujoco.mj_step(m, d)
        vz = d.qvel[dof + 2]
        if prev > 0.0 >= vz:
            return float(d.qpos[adr + 2] - BALL_R)
        prev = vz
    return 0.0


def _trial(job):
    seed, params, seconds = job[:3]
    body, controller = job[3] if len(job) > 3 else None, job[4] if len(job) > 4 else None
    os.environ["DRIBBLE_SEED"] = str(seed)
    from bridge import Sim
    task = DribbleTask()
    if body:
        task.body_kind = body
    sim = Sim(task, params=params, controller=controller)
    res = sim.run(seconds)
    res["seed"] = seed
    return res


def trials(params, n=10, seconds=15.0, workers=3, body=None, controller=None):
    """Run seed 0 (the unperturbed start) and seeds 1..n-1 (ball up to 2 cm
    off-centre in the hand) and summarise. `body` / `controller` override
    the task's body kind and controller binary."""
    from multiprocessing import Pool
    jobs = [(k, params, seconds, body, controller) for k in range(n)]
    with Pool(workers) as pool:
        runs = pool.map(_trial, jobs)
    drib = np.array([r["dribbles"] for r in runs])
    ok = [r for r in runs if r["dribbles"] >= 3]

    def mean(key):
        return round(float(np.mean([r[key] for r in ok])), 3) if ok else None

    moves = {}
    for k in "DXB":
        att = sum(r["moves"][k]["attempts"] for r in runs)
        ok_ = sum(r["moves"][k]["ok"] for r in runs)
        moves[MOVE_NAMES[k]] = {"attempts": att, "ok": ok_, "success_rate": round(ok_ / att, 3) if att else None,
                                "moves_with_ball_body_contact": sum(r["moves"][k]["body_contacts"] for r in runs)}
    cons = np.array([r["moves_consecutive"] for r in runs])

    def split_mean(*path):
        vals = []
        for r in runs:
            v = r.get("split", {})
            for k in path:
                v = v.get(k, {}) if isinstance(v, dict) else {}
            if isinstance(v, (int, float)):
                vals.append(float(v))
        return round(float(np.mean(vals)), 3) if vals else None
    split = {
        "trunk_share_of_activation": split_mean("activation_share", "trunk"),
        "trunk_share_of_upper_body_activation": split_mean("activation_share", "trunk_of_upper_body"),
        "trunk_share_of_effort": split_mean("effort_share", "trunk"),
        "trunk_share_of_upper_body_effort": split_mean("effort_share", "trunk_of_upper_body"),
        "trunk_mean_activation": split_mean("trunk_mean_activation"),
        "positive_work_share": {g: split_mean("positive_work_share", g)
                                for g in ("trunk", "shoulder", "elbow", "wrist", "fingers")},
        "arm_excursion_share": {g: split_mean("arm_excursion_share", g) for g in ("shoulder", "elbow", "wrist", "fingers")},
        "shoulder_share_of_arm_work": round(float(np.mean([DribbleTask.shoulder_share(r) for r in runs])), 3),
    }
    return {
        "trials": n, "seconds": seconds,
        "dribbles_median": float(np.median(drib)), "dribbles_max": int(drib.max()),
        "dribbles_min": int(drib.min()), "dribbles_mean": round(float(drib.mean()), 2),
        "moves": moves,
        "moves_consecutive_median": float(np.median(cons)), "moves_consecutive_max": int(cons.max()),
        "moves_consecutive_min": int(cons.min()),
        "freq_hz_mean": mean("freq_hz"), "apex_mean": mean("apex_mean"), "apex_std_mean": mean("apex_std"),
        "drift_mean": mean("drift_mean"), "effort_mean_sq_activation": mean("effort"),
        "ball_body_contacts_total": int(sum(r["body_hits"] for r in runs)),
        "split": split,
        "runs": runs,
    }


def render(params, seed, seconds, prefix, gif_mb=6.0):
    """One seeded run rendered: <prefix>.mp4, <prefix>.gif (shrunk until it fits
    gif_mb), <prefix>_sheet.png (12 frames evenly spaced) and
    <prefix>_moves_sheet.png (frames just after the first pushes of each move
    type, so every move is on the sheet)."""
    from PIL import Image, ImageDraw
    from bridge import Sim
    from render import Recorder
    os.environ["DRIBBLE_SEED"] = str(seed)
    task = DribbleTask()
    sim = Sim(task, params=params)
    rec = Recorder(sim)
    res = sim.run(seconds, recorder=rec)
    rec.write_mp4(prefix + ".mp4")
    for scale, every in ((0.5, 2), (0.42, 3), (0.36, 3), (0.32, 4), (0.28, 4), (0.25, 5)):
        rec.write_gif(prefix + ".gif", scale=scale, every=every)
        if os.path.getsize(prefix + ".gif") <= gif_mb * 1e6:
            break
    rec.write_sheet(prefix + "_sheet.png")
    picks, seen = [], {}
    for mv in task.moves:
        k = mv["type"] + mv["hand"]
        if seen.get(k, 0) < (2 if mv["type"] != "D" else 1):
            seen[k] = seen.get(k, 0) + 1
            picks.append((mv["t"] + (0.12 if mv["type"] == "D" else 0.2), f"{MOVE_NAMES[mv['type']]} {mv['hand']}"
                          + ("" if mv["type"] == "D" else f"->{'L' if mv['hand'] == 'R' else 'R'}") + f" ({mv['outcome']})"))
    picks = sorted(picks)[:12]
    w, h = int(rec.width * 0.4), int(rec.height * 0.4)
    cols = 4
    sheet = Image.new("RGB", (cols * w, ((len(picks) + cols - 1) // cols) * h), (255, 255, 255))
    for k, (t, label) in enumerate(picks):
        i = min(len(rec.frames) - 1, int(round(t * rec.fps)))
        im = Image.fromarray(rec.frames[i]).resize((w, h))
        ImageDraw.Draw(im).text((8, h - 60), label, fill=(200, 20, 20))
        sheet.paste(im, ((k % cols) * w, (k // cols) * h))
    sheet.save(prefix + "_moves_sheet.png")
    return res


def suite_v3(params, n=10, before_ctl=None, variants=True):
    """Before (the round-1 skill on the v1 body) against v3 (the arms-only
    skill on the fingered v2 body), with the effort split, per mode; and the
    v3 ablations (a rigid paddle hand instead of fingers, chunked strokes
    instead of via points)."""
    def load(path, **over):
        ps = {}
        for line in open(os.path.join(ROOT, path)):
            parts = line.split()
            if len(parts) >= 2 and not line.startswith("#"):
                ps[parts[0]] = float(parts[1])
        ps.update(over)
        return ps

    def slim(t):
        t = dict(t)
        t["runs"] = [{k: r.get(k) for k in ("seed", "dribbles", "moves_consecutive", "lost", "freq_hz", "apex_mean",
                                             "apex_std", "effort", "body_hits", "x_ok", "x_attempts")} for r in t["runs"]]
        return t
    out = {}
    if before_ctl:
        out["before"] = {
            "skill": "round 1: skills/dribble.w (trunk pump, IK strokes), frozen as " + os.path.relpath(before_ctl, ROOT),
            "body": "v1: base humanoid, rigid spread paddle",
            "right_hand_only": slim(trials(load("params/dribble.txt", mode=0.0), n, 15.0, body="v1",
                                           controller=before_ctl)),
            "crossover_every_bounce": slim(trials(load("params/dribble_moves.txt", mode=2.0), n, 15.0, body="v1",
                                                  controller=before_ctl)),
        }
    ctl = os.path.join(ROOT, "bin", "robolab_dribble_v3")
    after = {"skill": "skills/dribble_v3.w (quiet trunk, elbow-and-wrist strokes, via-chained cycle, V crossovers)",
             "body": "v3: human-calibrated v2 body, fingered hands (palm + two-segment finger plate)"}
    after["right_hand_only"] = slim(trials(dict(params, mode=0.0), n, 15.0, body="v3", controller=ctl))
    after["crossover_every_bounce"] = slim(trials(dict(params, mode=2.0), n, 15.0, body="v3", controller=ctl))
    after["crossover_runs"] = slim(trials(dict(params, mode=5.0), n, 20.0, body="v3", controller=ctl))
    out["after"] = after
    if variants:
        out["ablations"] = {
            "paddle_hand_crossover_every_bounce": slim(trials(dict(params, mode=2.0), n, 15.0, body="v3paddle",
                                                              controller=ctl)),
            "chunked_not_via_crossover_every_bounce": slim(trials(dict(params, mode=2.0, use_via=0.0), n, 15.0,
                                                                  body="v3", controller=ctl)),
        }
    return out


def move_label(kind, hand):
    if kind == "D":
        return f"dribble {hand}"
    return f"{MOVE_NAMES[kind]} {hand} -> {'L' if hand == 'R' else 'R'}"


def render_v3(params, seed, seconds, prefix, gif_mb=6.0):
    """The v3 video: front camera, 960 x 720, the ball's last 0.8 s drawn as a
    fading trail (orange while a crossover is in flight) and the move in
    progress named in large type. Writes <prefix>.mp4, <prefix>.gif (shrunk
    until it fits gif_mb) and <prefix>_sheet.png: the first two consecutive
    successful crossovers, six frames each from the push to the catch."""
    from collections import deque
    from PIL import Image, ImageDraw, ImageFont
    from bridge import Sim
    from render import Recorder
    try:
        big = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 34)
        small = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 18)
    except OSError:
        big = small = ImageFont.load_default()
    os.environ["DRIBBLE_SEED"] = str(seed)
    task = DribbleTask()
    task.body_kind = os.environ.get("DRIBBLE_BODY", "v3")
    sim = Sim(task, params=params)
    colors = {"D": (0.95, 0.95, 0.95), "X": (1.0, 0.55, 0.1), "B": (0.3, 0.6, 1.0)}

    class TrailRecorder(Recorder):
        def __init__(self, sim):
            super().__init__(sim, width=960, height=720)
            self.trail = deque()
            self.labels = []
            base = self.renderer.update_scene

            def update_scene(data, camera, scene_option=None):
                if scene_option is None:
                    base(data, camera)
                else:
                    base(data, camera, scene_option=scene_option)
                self.add_trail()
            self.renderer.update_scene = update_scene

        def maybe_capture(self, sim):
            if getattr(task, "released_t", None) is not None:
                self.trail.append((sim.d.time, sim.d.body("ball").xpos.copy(), task.open_move_type()))
            while self.trail and sim.d.time - self.trail[0][0] > 0.8:
                self.trail.popleft()
            super().maybe_capture(sim)

        def add_trail(self):
            scn = self.renderer.scene
            now = self.sim.d.time
            for t, p, kind in list(self.trail)[::3]:
                if scn.ngeom >= scn.maxgeom:
                    break
                a = max(0.0, 1.0 - (now - t) / 0.8)
                rgba = np.array([*colors.get(kind, colors["D"]), 0.15 + 0.6 * a], dtype=np.float32)
                mujoco.mjv_initGeom(scn.geoms[scn.ngeom], mujoco.mjtGeom.mjGEOM_SPHERE, np.array([0.025, 0, 0]),
                                    p.astype(np.float64), np.eye(3).flatten(), rgba)
                scn.ngeom += 1

        def capture(self, sim):
            super().capture(sim)
            moves = task.moves
            label = move_label(moves[-1]["type"], moves[-1]["hand"]) if moves else "starting the dribble"
            kind = moves[-1]["type"] if moves else "D"
            done = [mv for mv in moves if mv["outcome"] is not None]
            tally = "   ".join(f"{MOVE_NAMES[k]}s {sum(1 for mv in done if mv['type'] == k and mv['outcome'] == 'ok')}"
                               f"/{sum(1 for mv in done if mv['type'] == k)}" for k in "XD" if any(mv["type"] == k for mv in moves))
            im = Image.fromarray(self.frames[-1])
            dr = ImageDraw.Draw(im, "RGBA")
            col = tuple(int(255 * c) for c in colors.get(kind, colors["D"]))
            dr.rectangle([8, 96, 560, 176], fill=(15, 18, 24, 150))
            dr.text((20, 100), label.upper(), font=big, fill=col + (255,))
            dr.text((20, 146), tally, font=small, fill=(225, 230, 238, 255))
            self.frames[-1] = np.asarray(im)
            self.labels.append((sim.d.time, label))

    rec = TrailRecorder(sim)
    res = sim.run(seconds, recorder=rec)
    rec.write_mp4(prefix + ".mp4")
    for scale, every in ((0.5, 2), (0.42, 3), (0.36, 3), (0.32, 4), (0.28, 4), (0.25, 5)):
        rec.write_gif(prefix + ".gif", scale=scale, every=every)
        if os.path.getsize(prefix + ".gif") <= gif_mb * 1e6:
            break
    # the sheet: two consecutive successful crossovers, push to catch
    ms = task.moves
    pick = None
    for i in range(len(ms) - 2):
        if ms[i]["type"] == "X" and ms[i + 1]["type"] == "X" and ms[i]["outcome"] == "ok" and ms[i + 1]["outcome"] == "ok":
            pick = i
            break
    if pick is None:
        pick = next((i for i, mv in enumerate(ms[:-1]) if mv["type"] == "X"), None)
    if pick is not None:
        w, h = int(rec.width * 0.4), int(rec.height * 0.4)
        cols, shots = 6, []
        for j in (pick, pick + 1):
            t0, t1 = ms[j]["t"] - 0.04, ms[j + 1]["t"] if j + 1 < len(ms) else ms[j]["t"] + 0.5
            for k in range(cols):
                t = t0 + (t1 - t0) * k / (cols - 1)
                shots.append((t, f"{move_label(ms[j]['type'], ms[j]['hand'])}  t={t:.2f}s"))
        sheet = Image.new("RGB", (cols * w, 2 * h), (255, 255, 255))
        for k, (t, label) in enumerate(shots):
            i = min(len(rec.frames) - 1, int(round(t * rec.fps)))
            im = Image.fromarray(rec.frames[i]).resize((w, h))
            ImageDraw.Draw(im).text((8, h - 64), label, font=small, fill=(20, 20, 20))
            sheet.paste(im, ((k % cols) * w, (k // cols) * h))
        sheet.save(prefix + "_sheet.png")
        print("wrote", prefix + "_sheet.png")
    return res


def _scored(job):
    seed, params, seconds = job
    res = _trial(job)
    return DribbleTask().score(res), res


def practice(a):
    """practice.py's CMA-ES and tunable discovery, but each candidate is scored
    as the mean over several seeded starts, so the search cannot win by
    fitting one chaotic trajectory. Writes the best in practice.py's format."""
    import time
    from multiprocessing import Pool
    import practice as pr
    seeds = [int(x) for x in a.seeds.split(",")]
    tun = pr.describe("dribble")
    init = pr.read_params(a.init)
    fixed = dict(init)
    if a.only:
        keep = set(a.only.split(","))
        tun = [t for t in tun if t[0] in keep]
    names = [t[0] for t in tun]
    lo = np.array([t[2] for t in tun])
    hi = np.array([t[3] for t in tun])
    x0 = np.array([(init.get(t[0], t[1]) - t[2]) / (t[3] - t[2]) for t in tun]).clip(0, 1)

    def to_params(x):
        p = dict(fixed)
        p.update({n: float(l + (h - l) * v) for n, l, h, v in zip(names, lo, hi, np.clip(x, 0, 1))})
        return p

    # --modes scores every candidate on each (mode, seed) pair
    modes = [float(v) for v in a.modes.split(",")] if a.modes else [None]

    def with_mode(p, md):
        return p if md is None else dict(p, mode=md)

    def score_all(pool, xs):
        res = pool.map(_scored, [(s, with_mode(to_params(x), md), a.seconds) for x in xs for md in modes for s in seeds])
        k = len(seeds) * len(modes)
        return [(float(np.mean([r[0] for r in res[i * k:(i + 1) * k]])), [r[1]["dribbles"] for r in res[i * k:(i + 1) * k]])
                for i in range(len(xs))]

    es = pr.CMA(x0, a.sigma, None, seed=7)
    t0 = time.time()
    with Pool(a.workers) as pool:
        base = score_all(pool, [x0])[0]
        best = (base[0], x0.copy(), base[1])
        print(f"gen 0 mean score {base[0]:.3f} dribbles {base[1]}", flush=True)
        for g in range(a.gens):
            xs = es.ask()
            res = score_all(pool, xs)
            scores = [r[0] for r in res]
            es.tell(xs, [sc - 10.0 * float(np.sum(np.maximum(0, x - 1) + np.maximum(0, -x))) for sc, x in zip(scores, xs)])
            k = int(np.argmax(scores))
            if scores[k] > best[0]:
                best = (scores[k], np.clip(xs[k], 0, 1), res[k][1])
                pr.write(a.out, "dribble", to_params(best[1]), best[0], {"seeds": seeds, "dribbles": best[2]})
            print(f"gen {g + 1} best {best[0]:.3f} {best[2]} gen-best {scores[k]:.3f} {res[k][1]} "
                  f"sigma {es.sigma:.3f} ({time.time() - t0:.0f}s)", flush=True)


def main():
    import argparse
    import json
    ap = argparse.ArgumentParser(description="dribble task checks and multi-seed practice")
    ap.add_argument("--fiba", action="store_true", help="FIBA drop test of the ball/floor contact")
    ap.add_argument("--trials", type=int, default=0)
    ap.add_argument("--params")
    ap.add_argument("--seconds", type=float, default=15.0)
    ap.add_argument("--out")
    ap.add_argument("--practice", action="store_true", help="multi-seed CMA-ES (see practice())")
    ap.add_argument("--render", help="render one run to <prefix>.mp4/.gif/_sheet.png/_moves_sheet.png")
    ap.add_argument("--render-v3", help="the v3 front-view render (trail, move label, crossover sheet)")
    ap.add_argument("--suite-v3", action="store_true", help="before/after metrics for v3 (--params: the v3 params)")
    ap.add_argument("--before", help="frozen round-1 controller for --suite-v3's before runs")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--set", default="", help="k=v,... parameter overrides")
    ap.add_argument("--suite", nargs=2, metavar=("DRIBBLE_PARAMS", "MOVES_PARAMS"),
                    help="the full metrics: right hand only (mode 0) and the moves (modes 1-3)")
    ap.add_argument("--seeds", default="0,1,2,3")
    ap.add_argument("--gens", type=int, default=40)
    ap.add_argument("--sigma", type=float, default=0.1)
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--init")
    ap.add_argument("--only")
    ap.add_argument("--modes", help="practice: score each candidate over these modes (e.g. 0,2) x --seeds")
    a = ap.parse_args()
    if a.practice:
        return practice(a)
    params = {}
    if a.params:
        for line in open(a.params):
            parts = line.split()
            if len(parts) >= 2 and not line.startswith("#"):
                params[parts[0]] = float(parts[1])
    for kv in filter(None, a.set.split(",")):
        k, v = kv.split("=")
        params[k] = float(v)
    if a.render:
        print(render(params, a.seed, a.seconds, a.render))
        return
    if a.render_v3:
        print(render_v3(params, a.seed, a.seconds, a.render_v3))
        return
    if a.suite_v3:
        res = suite_v3(params, a.trials or 10, a.before)
        text = json.dumps(res, indent=1)
        if a.out:
            with open(a.out, "w") as f:
                f.write(text + "\n")
        print(text[:4000])
        return
    out = {}
    rebound = fiba_drop()
    out["fiba_drop"] = {"drop_m": 1.8, "rebound_m": round(rebound, 3), "spec_m": [1.035, 1.085],
                        "restitution": round(math.sqrt(rebound / 1.8), 3)}
    out["body"] = ("pivot root: the pelvis is held at a fixed height (%.2f m) on a muscle-driven vertical yaw "
                   "hinge; legs stand on the floor (and step) but do not carry the body weight. Hands: the stock "
                   "9 x 11 cm hand box widened to a spread-finger 16 x 18 cm (same 0.4 kg); the ball meets the "
                   "finger pads 12 cm from the wrist" % PELVIS_HEIGHT)
    if a.trials and not a.suite:
        out["trials"] = trials(params, a.trials, a.seconds)
    if a.suite:
        def load(path, **over):
            ps = {}
            for line in open(path):
                parts = line.split()
                if len(parts) >= 2 and not line.startswith("#"):
                    ps[parts[0]] = float(parts[1])
            ps.update(over)
            return ps
        n = a.trials or 10

        def slim(t):
            t = dict(t)
            t["runs"] = [{k: r[k] for k in ("seed", "dribbles", "moves_consecutive", "lost", "freq_hz", "apex_mean",
                                            "apex_std", "effort", "body_hits")} for r in t["runs"]]
            return t
        out["right_hand_only"] = slim(trials(load(a.suite[0], mode=0.0), n, 15.0))
        out["choreography"] = slim(trials(load(a.suite[1], mode=1.0), n, 30.0))
        out["crossover_every_bounce"] = slim(trials(load(a.suite[1], mode=2.0), n, 15.0))
        out["between_the_legs_both_ways"] = slim(trials(load(a.suite[1], mode=3.0), n, 20.0))
    text = json.dumps(out, indent=2)
    print(text)
    if a.out:
        with open(a.out, "w") as f:
            f.write(text + "\n")


if __name__ == "__main__":
    main()
