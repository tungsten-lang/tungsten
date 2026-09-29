"""Hurdles: run and clear a flight of physical hurdles on the planar body.

Track: a standing start at x = 0, `count` hurdles with the top of the bar at
`height`, the first at `first` metres and `spacing` metres between them (the
110 m hurdles' 9.14 m by default), and a finish line `run_out` metres after
the last. ROBOLAB_HURDLE_HEIGHT / _COUNT / _FIRST / _SPACING / _RUNOUT
override the course; ROBOLAB_HURDLE_START (stand | stagger | flying:<v>) and
ROBOLAB_HURDLE_SEED (standing-pose noise) are practice aids;
ROBOLAB_HURDLE_METRICS=<path> writes a JSON record of the run.

Body: the shared planar humanoid at strength 1.0, with one change: muscle
shortening speed vmax = 3.0 optimal lengths/s instead of MuJoCo's default
1.5 (ROBOLAB_HURDLE_VMAX). The default caps unloaded joint speeds near half
a human's (hip 14, knee 12.6, ankle 7.5 rad/s against ~25 / 20 / 15), and
with rigid tendons nothing makes up the difference; a take-off and a knee
drive need the speed. The long-jump task makes the same change.

Each hurdle is a hinged gate, not a fixture: an upright frame (two posts and a
7 cm top board spanning 1.2 m) on a hinge at the floor under the bar, whose
L-shaped feet reach back toward the runner and carry a counterweight, like a
real rocking hurdle. The counterweight is sized so that a horizontal push of
36 N (3.6 kg-force, the World Athletics tipping force) at the top board tips
it. The board collides with every body geom (contype 1 / conaffinity 2
against the body's contype 2 / conaffinity 1); posts and feet sit at
y = +-0.6 m, outside the planar body, as a real hurdle's do. A hurdle that is
brushed rocks back; one hit hard enough falls forward and lies on the track.

Sensor block `hurdle` (4 values):
    dx_next   x of the next hurdle's bar minus the centre-of-mass x (m)
    h_next    that hurdle's bar height (m), 0 when none remain
    k_next    its index (0-based; == count when none remain)
    dx_after  x of the hurdle after it minus the COM x (99 when none)
The next hurdle is the first whose bar the pelvis has not yet passed.

Metrics. A step is a foot taking a third of body weight after 80 ms unloaded,
planting a new foremost foothold, alternating feet (a trailing foot brushing
the track is not a step). Per hurdle: passed (pelvis past the bar and a step
landed beyond it), knocked (tipped past 0.5 rad, or left leaning past 0.3),
cleared (passed, not knocked), touched (any body contact with the board),
clean (cleared untouched), clearance margin (lowest body point minus the top
of the bar while any body geom is over the bar; negative = contact), COM
clearance (COM height minus bar height as the COM crosses the bar), take-off
and landing distances (ankle to bar), steps between hurdles. Overall:
approach speed (mean over the 3 m before the first take-off zone), average
speed and time from the start to the last hurdle, time to the finish, effort
(mean squared activation), mean pelvis height and torso pitch after 1.5 s.
A fall (pelvis below 0.5 m, or the trunk tipped past ~70 degrees) ends the
run.
"""

import math
import os

import mujoco
import numpy as np

from body import HumanoidBuilder
from bridge import Task


def _env(name, default):
    v = os.environ.get(name)
    return type(default)(v) if v else default


class HurdlerBuilder(HumanoidBuilder):
    """The default humanoid with a tunable muscle shortening speed (vmax, in
    optimal lengths per second; the shared default is MuJoCo's 1.5, which
    caps unloaded joint speeds near half a human's). Strength is unchanged."""

    def __init__(self, *a, vmax=1.5, **k):
        super().__init__(*a, **k)
        self.vmax = vmax

    def actuators_xml(self):
        return super().actuators_xml().replace('vmax="1.5"', f'vmax="{self.vmax:g}"')


class HurdleTask(Task):
    name = "hurdle"
    mode = "planar"
    seconds = 20.0
    fall_height = 0.5
    start = "stand"
    # 2 physics steps of 2 ms per control tick, and the controller told so
    # (the base default 0.005 rounds to 2 substeps: 4 ms of physics per tick)
    control_dt = 0.004
    board = 0.07        # top board depth (m)
    width = 1.2         # bar span (m)
    feet = 0.7          # length of the L feet toward the runner (m)
    tip_force = 36.0    # N at the top board to tip the hurdle

    def __init__(self):
        self.strength = _env("ROBOLAB_HURDLE_STRENGTH", 1.0)
        self.vmax = _env("ROBOLAB_HURDLE_VMAX", 3.0)
        self.height = _env("ROBOLAB_HURDLE_HEIGHT", 0.45)
        self.count = _env("ROBOLAB_HURDLE_COUNT", 4)
        self.first = _env("ROBOLAB_HURDLE_FIRST", 10.0)
        self.spacing = _env("ROBOLAB_HURDLE_SPACING", 9.14)
        self.run_out = _env("ROBOLAB_HURDLE_RUNOUT", 4.0)
        self.xs = [self.first + k * self.spacing for k in range(self.count)]
        self.finish = self.xs[-1] + self.run_out if self.xs else 60.0
        self._cam_x = None

    def builder(self):
        return HurdlerBuilder(self.mode, strength=self.strength, wrists=self.wrists, vmax=self.vmax)

    def title(self):
        return f"robolab: hurdles {self.count} x {self.height:.2f} m, {self.spacing:g} m apart (planar muscle humanoid)"

    # ---- scene -----------------------------------------------------------

    def hurdle_xml(self, k, x):
        h, b, w, f = self.height, self.board, self.width / 2, self.feet
        # counterweight: m g d = F h with d = f / 2 (split across both feet)
        cw = self.tip_force * h / (9.81 * f / 2)
        hit = 'contype="1" conaffinity="2"'
        post = 'contype="1" conaffinity="2" rgba="0.2 0.2 0.22 1"'
        stripe = "0.1 0.1 0.12 1" if k % 2 else "0.9 0.15 0.12 1"
        return f"""
    <body name="hurdle{k}" pos="{x:g} 0 0">
      <joint name="hurdle{k}_tip" type="hinge" axis="0 1 0" range="0 1.65" damping="0.2" armature="0.01"/>
      <geom name="hurdle{k}_bar" type="box" pos="0 0 {h - b / 2:g}" size="0.01 {w:g} {b / 2:g}" mass="1.2" {hit} rgba="0.97 0.97 0.97 1"/>
      <geom name="hurdle{k}_stripe" type="box" pos="-0.0005 0 {h - b / 2:g}" size="0.0101 {w * 0.35:g} {b / 2 + 0.0005:g}" mass="0.001" contype="0" conaffinity="0" rgba="{stripe}"/>
      <geom name="hurdle{k}_post_l" type="capsule" fromto="0 {w:g} 0.03 0 {w:g} {h - b:g}" size="0.014" mass="0.4" {post}/>
      <geom name="hurdle{k}_post_r" type="capsule" fromto="0 {-w:g} 0.03 0 {-w:g} {h - b:g}" size="0.014" mass="0.4" {post}/>
      <geom name="hurdle{k}_foot_l" type="capsule" fromto="0 {w:g} 0.018 {-f:g} {w:g} 0.018" size="0.014" mass="0.3" {post}/>
      <geom name="hurdle{k}_foot_r" type="capsule" fromto="0 {-w:g} 0.018 {-f:g} {-w:g} 0.018" size="0.014" mass="0.3" {post}/>
      <geom name="hurdle{k}_weight_l" type="box" pos="{-f / 2:g} {w:g} 0.03" size="0.05 0.03 0.025" mass="{cw / 2:g}" {post}/>
      <geom name="hurdle{k}_weight_r" type="box" pos="{-f / 2:g} {-w:g} 0.03" size="0.05 0.03 0.025" mass="{cw / 2:g}" {post}/>
    </body>"""

    def xml_extras(self):
        world = [self.hurdle_xml(k, x) for k, x in enumerate(self.xs)]
        # lane lines, start and finish (visual only)
        mid, half = self.finish / 2 + 3, self.finish / 2 + 5  # x from -2 to finish + 8
        world.append(f'<geom name="lane_l" type="box" pos="{mid:g} 0.62 0.001" size="{half:g} 0.025 0.001" contype="0" conaffinity="0" rgba="1 1 1 1"/>')
        world.append(f'<geom name="lane_r" type="box" pos="{mid:g} -0.62 0.001" size="{half:g} 0.025 0.001" contype="0" conaffinity="0" rgba="1 1 1 1"/>')
        world.append('<geom name="start" type="box" pos="-0.25 0 0.001" size="0.025 0.62 0.001" contype="0" conaffinity="0" rgba="1 1 1 1"/>')
        world.append(f'<geom name="finish" type="box" pos="{self.finish:g} 0 0.001" size="0.025 0.62 0.001" contype="0" conaffinity="0" rgba="0.1 0.1 0.1 1"/>')
        assets = '<material name="track" rgba="0.72 0.33 0.25 1"/>'
        world.append(f'<geom name="track" type="box" pos="{mid:g} 0 0.0005" size="{half:g} 0.6 0.0005" contype="0" conaffinity="0" material="track"/>')
        return {"extra_world": "\n".join(world), "extra_assets": assets}

    # ---- run -------------------------------------------------------------

    def reset(self, m, d):
        self.tip_adr = [m.jnt_qposadr[m.joint(f"hurdle{k}_tip").id] for k in range(self.count)]
        self.bar_geom = [m.geom(f"hurdle{k}_bar").id for k in range(self.count)]
        self.body_geoms = [g for g in range(m.ngeom)
                           if m.geom_contype[g] == 2 and m.geom_bodyid[g] != 0]
        self.max_tip = [0.0] * self.count
        self.touched = [False] * self.count
        self.margin = [None] * self.count
        self.margin_part = [None] * self.count
        self.lead = [None] * self.count
        self.cross_t = [None] * self.count
        self.finish_t = None
        self.approach = []
        self.takeoff_td = [None] * self.count
        self.com_gap = [None] * self.count
        self.touchdowns = []
        self._last_on = {"l": 0.0, "r": 0.0}
        self.posture = []
        self._fell = False
        self.pelvis_id = m.body("pelvis").id
        self._cam_x = None
        self.foot_geoms = [m.geom("l_foot").id, m.geom("r_foot").id]
        self.floor_geom = m.geom("floor").id
        pel = m.body("pelvis").id
        self.weight = 9.81 * float(sum(m.body_mass[b] for b in range(m.nbody) if b == pel or self._under(m, b, pel)))
        self.plan = ""
        self.pose_start(m, d)

    # Initial posture (an initial condition, not an assist): "stand" (feet
    # together, the default body pose), "stagger" (a standing start: left
    # foot forward, right foot back), or "flying:<v>" (development only:
    # mid-stride at v m/s).
    def pose_start(self, m, d):
        start = os.environ.get("ROBOLAB_HURDLE_START", self.start)
        seed = os.environ.get("ROBOLAB_HURDLE_SEED")
        if start == "stand":
            if seed:
                # practice robustness: a few degrees of noise on the standing
                # pose (never used for the rendered run)
                rng = np.random.default_rng(int(seed))
                for j in ("l_hip_flex", "r_hip_flex", "l_knee", "r_knee", "spine_flex", "l_ankle", "r_ankle"):
                    a = m.jnt_qposadr[m.joint(j).id]
                    d.qpos[a] = float(np.clip(d.qpos[a] + rng.uniform(-0.06, 0.06), *m.jnt_range[m.joint(j).id]))
                d.qpos[2] += rng.uniform(-0.04, 0.04)
                mujoco.mj_forward(m, d)
                low = min(self._geom_bottom(m, d, g) for g in self.foot_geoms)
                d.qpos[1] -= low - 0.001
                mujoco.mj_forward(m, d)
            return
        q = {}
        if start == "stagger":
            q = {"l_hip_flex": 0.32, "l_knee": 0.32, "r_hip_flex": -0.32, "r_knee": 0.0,
                 "spine_flex": 0.15, "l_shoulder_flex": -0.3, "r_shoulder_flex": 0.4, "l_elbow": 1.2, "r_elbow": 1.2}
        elif start.startswith("flying"):
            q = {"l_hip_flex": 0.05, "l_knee": 0.45, "r_hip_flex": 0.5, "r_knee": 1.5,
                 "spine_flex": 0.12, "l_shoulder_flex": 0.4, "r_shoulder_flex": -0.4, "l_elbow": 1.4, "r_elbow": 1.4}
        for j, v in q.items():
            d.qpos[m.jnt_qposadr[m.joint(j).id]] = v
        # feet flat: ankle = hip - knee (both ankles), then drop to the floor
        for side in ("l_", "r_"):
            hip = d.qpos[m.jnt_qposadr[m.joint(side + "hip_flex").id]]
            knee = d.qpos[m.jnt_qposadr[m.joint(side + "knee").id]]
            d.qpos[m.jnt_qposadr[m.joint(side + "ankle").id]] = min(0.9, max(-0.6, hip - knee))
        mujoco.mj_forward(m, d)
        low = min(self._geom_bottom(m, d, g) for g in self.foot_geoms)
        d.qpos[1] -= low - 0.001
        if start.startswith("flying"):
            d.qpos[1] += 0.02
            d.qvel[0] = float(start.split(":")[1]) if ":" in start else 3.0
        mujoco.mj_forward(m, d)

    def _geom_bottom(self, m, d, g):
        pos = d.geom_xpos[g]
        mat = d.geom_xmat[g].reshape(3, 3)
        size = m.geom_size[g]
        return min((pos + mat @ (size * np.array([sx, sy, sz])))[2]
                   for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1))

    def on_command(self, m, d, cmd):
        if cmd.startswith("plan:"):
            _, n, step = cmd.split(":")
            self.plan = f"{n} steps of {float(step):.2f} m to take-off"

    def _next(self, x):
        for k, hx in enumerate(self.xs):
            if x < hx + 0.05:
                return k
        return self.count

    def extra_sensors(self, m, d):
        com = d.subtree_com[m.body("pelvis").id]
        k = self._next(d.body("pelvis").xpos[0])
        if k < self.count:
            dx, h = self.xs[k] - com[0], self.height
        else:
            dx, h = 99.0, 0.0
        after = self.xs[k + 1] - com[0] if k + 1 < self.count else 99.0
        return [("hurdle", [dx, h, float(k), after])]

    def _lowest_over(self, m, d, bx):
        """Lowest body point within the bar's x-extent and its geom (None if
        nothing is over it)."""
        low, part = None, None
        for g in self.body_geoms:
            pos = d.geom_xpos[g]
            mat = d.geom_xmat[g].reshape(3, 3)
            size = m.geom_size[g]
            gt = m.geom_type[g]
            if gt == mujoco.mjtGeom.mjGEOM_CAPSULE:
                ax = mat[:, 2] * size[1]
                pts = [pos + ax * s for s in np.linspace(-1, 1, 9)]
                r = size[0]
            elif gt == mujoco.mjtGeom.mjGEOM_BOX:
                pts = [pos + mat @ (size * np.array([sx, 0, sz])) for sx in (-1, 0, 1) for sz in (-1, 1)]
                r = 0.0
            elif gt == mujoco.mjtGeom.mjGEOM_SPHERE:
                pts, r = [pos], size[0]
            else:
                continue
            for p in pts:
                if abs(p[0] - bx) <= r + 0.01:
                    z = p[2] - r
                    if low is None or z < low:
                        low, part = z, g
        return low, part

    def before_step(self, m, d):
        px = float(d.body("pelvis").xpos[0])
        vx = float(d.qvel[0])
        if self.xs and self.xs[0] - 5.0 <= px <= self.xs[0] - 2.0:
            self.approach.append(vx)
        if d.time > 1.5:
            up = d.body("torso").xmat.reshape(3, 3)[:, 2]
            self.posture.append((float(d.body("pelvis").xpos[2]), math.atan2(up[0], up[2])))
        # touchdowns (a foot newly on the floor): the last one before the
        # pelvis passes a bar is the take-off step, the first one after it
        # the landing; the ones between two hurdles are the strides
        load = self._foot_load(m, d)
        for side, g in (("l", self.foot_geoms[0]), ("r", self.foot_geoms[1])):
            if load[g] > 0.3:
                # a touchdown is a foot taking a third of body weight after
                # 80 ms unloaded (toe scuffs and contact flicker do not count)
                if d.time - self._last_on[side] > 0.08:
                    self.touchdowns.append((d.time, side, float(d.body(side + "_foot").xpos[0])))
                self._last_on[side] = d.time
        com = d.subtree_com[self.pelvis_id]
        for k, hx in enumerate(self.xs):
            self.max_tip[k] = max(self.max_tip[k], float(d.qpos[self.tip_adr[k]]))
            # clearance margin while the hurdle still stands (once it tips,
            # the contact has already been counted)
            if abs(px - hx) < 1.6 and float(d.qpos[self.tip_adr[k]]) < 0.05:
                low, part = self._lowest_over(m, d, hx)
                if low is not None:
                    gap = low - self.height
                    if self.margin[k] is None or gap < self.margin[k]:
                        self.margin[k] = gap
                        self.margin_part[k] = m.geom(part).name
            if self.com_gap[k] is None and com[0] > hx:
                self.com_gap[k] = float(com[2]) - self.height
            if self.cross_t[k] is None and px > hx:
                self.cross_t[k] = d.time
                if self.touchdowns:
                    self.takeoff_td[k] = len(self.touchdowns) - 1
        for i in range(d.ncon):
            con = d.contact[i]
            for k, g in enumerate(self.bar_geom):
                if con.geom1 == g or con.geom2 == g:
                    other = con.geom2 if con.geom1 == g else con.geom1
                    if m.geom_contype[other] == 2:
                        self.touched[k] = True
        if self.finish_t is None and px > self.finish:
            self.finish_t = d.time

    def strides(self):
        """Take-off / landing distances (ankle to bar) and steps between hurdles.

        Steps are the touchdowns that plant a new foremost foothold (a
        trailing foot brushing the track behind the other one is not a step).
        The take-off is the last step short of the bar before the pelvis
        passes it; the landing the first step beyond the bar after it."""
        td = self.steps()
        take = [None] * self.count
        land = [None] * self.count
        take_i = [None] * self.count
        land_i = [None] * self.count
        for k in range(self.count):
            if self.cross_t[k] is None:
                continue
            last = max([i for i, t in enumerate(td) if t[0] <= self.cross_t[k]], default=None)
            if last is None:
                continue
            for i in range(last, -1, -1):
                if td[i][2] < self.xs[k]:
                    take_i[k] = i
                    take[k] = round(self.xs[k] - td[i][2], 3)
                    self.lead[k] = "right" if td[i][1] == "l" else "left"
                    break
            if take_i[k] is None:
                continue
            for i in range(take_i[k] + 1, len(td)):
                if td[i][2] > self.xs[k]:
                    land_i[k] = i
                    land[k] = round(td[i][2] - self.xs[k], 3)
                    break
        between = []
        for k in range(self.count - 1):
            if land_i[k] is not None and take_i[k + 1] is not None:
                between.append(take_i[k + 1] - land_i[k])
        approach = take_i[0] + 1 if self.count and take_i[0] is not None else None
        return take, land, between, approach

    @staticmethod
    def _under(m, b, root):
        while b > 0:
            if m.body_parentid[b] == root:
                return True
            b = m.body_parentid[b]
        return False

    def steps(self):
        out, front, last = [], -1e9, None
        for t, side, x in self.touchdowns:
            if x > front + 0.05 and side != last:
                out.append((t, side, x))
                front, last = x, side
        return out

    def _foot_load(self, m, d):
        """Normal force of the floor on each foot, in body weights."""
        out = {g: 0.0 for g in self.foot_geoms}
        f = np.zeros(6)
        for i in range(d.ncon):
            con = d.contact[i]
            for g in self.foot_geoms:
                if (con.geom1 == g and con.geom2 == self.floor_geom) or (con.geom2 == g and con.geom1 == self.floor_geom):
                    mujoco.mj_contactForce(m, d, i, f)
                    out[g] += abs(f[0]) / self.weight
        return out

    def _feet_down(self, m, d):
        feet = (self.foot_geoms[0], self.foot_geoms[1])
        out = []
        for i in range(d.ncon):
            con = d.contact[i]
            for g in feet:
                if (con.geom1 == g or con.geom2 == g) and g not in out:
                    other = con.geom2 if con.geom1 == g else con.geom1
                    if other == self.floor_geom:
                        out.append(g)
        return out

    def done(self, m, d):
        """Fallen: pelvis below 0.5 m or the trunk tipped past ~70 degrees."""
        up = d.body("torso").xmat.reshape(3, 3)[:, 2]
        self._fell = bool(d.body("pelvis").xpos[2] < self.fall_height or up[2] < 0.35)
        return self._fell

    def knocked(self, k, d):
        return self.max_tip[k] > 0.5 or float(d.qpos[self.tip_adr[k]]) > 0.3

    def metrics(self, m, d, log):
        px = float(d.body("pelvis").xpos[0])
        take, land, between, approach = self.strides()
        # a hurdle is passed once the pelvis is past the bar AND a foot has
        # landed beyond it (falling over a hurdle is not passing it)
        passed = [self.cross_t[k] is not None and land[k] is not None for k in range(self.count)]
        knocked = [self.knocked(k, d) for k in range(self.count)]
        cleared = sum(1 for k in range(self.count) if passed[k] and not knocked[k])
        margins = [None if v is None else round(float(v), 3) for v in self.margin]
        acts = np.array([row[2] for row in log]) if log else np.zeros((1, 1))
        out = {
            "height": self.height,
            "strength": self.strength,
            "vmax": self.vmax,
            "hurdles": self.count,
            "spacing": self.spacing,
            "passed": sum(passed),
            "cleared": cleared,
            "knocked": sum(1 for k in range(self.count) if passed[k] and knocked[k]),
            "touched": sum(1 for k in range(self.count) if self.touched[k]),
            "clean": sum(1 for k in range(self.count) if passed[k] and not self.touched[k] and not knocked[k]),
            "approach_speed": round(float(np.mean(self.approach)), 3) if self.approach else None,
            "avg_speed": None,
            "time_to_last": None,
            "time_to_finish": None if self.finish_t is None else round(self.finish_t, 3),
            "margin": margins,
            "min_margin": min([v for v in margins if v is not None], default=None),
            "margin_part": self.margin_part,
            "lead_leg": self.lead,
            "com_clearance": [None if v is None else round(v, 3) for v in self.com_gap],
            "takeoff_dist": take,
            "landing_dist": land,
            "steps_between": between,
            "approach_steps": approach,
            "max_tip": [round(v, 2) for v in self.max_tip],
            "effort": round(float(np.mean(acts ** 2)), 4),
            "pelvis_z": round(float(np.mean([p[0] for p in self.posture])), 3) if self.posture else None,
            "torso_pitch": round(float(np.mean([p[1] for p in self.posture])), 3) if self.posture else None,
            "time": round(d.time, 3),
            "x": round(px, 3),
            "fell": self._fell,
        }
        if self.cross_t and self.cross_t[-1] is not None:
            out["time_to_last"] = round(self.cross_t[-1], 3)
            out["avg_speed"] = round(self.xs[-1] / self.cross_t[-1], 3)
        path = os.environ.get("ROBOLAB_HURDLE_METRICS")
        if path:
            self.write_metrics(path, out)
        return out

    def write_metrics(self, path, out):
        """JSON record of the run: course, per-hurdle results, summary metrics."""
        import json
        rec = {
            "task": "hurdle",
            "body": {"root": self.mode, "strength": self.strength, "muscle_vmax_L0_per_s": self.vmax,
                     "height_m": 1.75, "mass_kg": 67.5,
                     "note": "planar (sagittal) body: the trail leg cannot abduct and tucks in the sagittal plane"},
            "course": {"hurdles": self.count, "height_m": self.height, "first_m": self.first,
                       "spacing_m": self.spacing, "finish_m": self.finish, "hurdle_x_m": self.xs,
                       "tip_force_N": self.tip_force},
            "metrics": {k: (bool(v) if isinstance(v, (bool, np.bool_)) else v) for k, v in out.items()},
            "steps": [{"t": round(t, 3), "foot": f, "x": round(x, 3)} for t, f, x in self.steps()],
        }
        with open(path, "w") as fh:
            json.dump(rec, fh, indent=1, default=float)

    def score(self, metrics):
        """Practice objective: distance, hurdles cleared (clean ones more),
        clearance margin (shaped, so near misses teach), finish time, no fall.
        A knocked hurdle earns nothing beyond the distance run past it."""
        if "error" in metrics:
            return -1e9
        s = min(metrics.get("x", 0.0), self.finish)
        s += 10.0 * metrics.get("cleared", 0) + 5.0 * metrics.get("clean", 0)
        for v in metrics.get("margin") or []:
            if v is not None:
                s += 10.0 * max(-0.2, min(0.1, v))
        if metrics.get("time_to_finish") is not None:
            s += 1.0 * (self.seconds - metrics["time_to_finish"])
        # run tall and upright: a crouched, hunched runner sits on the edge of
        # knee collapse and recovers badly from a landing
        if metrics.get("pelvis_z") is not None:
            s -= 60.0 * max(0.0, 0.9 - metrics["pelvis_z"])
        if metrics.get("torso_pitch") is not None:
            s -= 10.0 * max(0.0, metrics["torso_pitch"] - 0.3)
        if metrics.get("fell"):
            s -= 10.0
        return s

    # ---- view --------------------------------------------------------------

    def camera(self, m, d, cam):
        # side view tracking the athlete (critically smoothed so the frame
        # does not jerk with each stride)
        x = float(d.body("pelvis").xpos[0]) + 0.4
        self._cam_x = x if self._cam_x is None else self._cam_x + 0.1 * (x - self._cam_x)
        cam.lookat[:] = [self._cam_x, 0.0, 0.7]
        cam.distance = 4.8
        cam.azimuth = 90
        cam.elevation = -6

    def hud_text(self, m, d):
        px = float(d.body("pelvis").xpos[0])
        k = self._next(px)
        v = float(d.qvel[0])
        cl = sum(1 for j in range(self.count) if self.cross_t[j] is not None and not self.knocked(j, d))
        kn = sum(1 for j in range(self.count) if self.cross_t[j] is not None and self.knocked(j, d))
        nxt = f"next H{k + 1} in {self.xs[k] - px:4.1f} m" if k < self.count else "run-out"
        plan = f"   plan: {self.plan}" if self.plan else ""
        return f"v = {v:4.2f} m/s   {nxt}   cleared {cl}  knocked {kn}{plan}"


TASK = HurdleTask
