"""Long jump: approach run, take-off board, flight, landing in a sand pit.

Scene (planar muscle humanoid: the root slides in x and z and pitches about
y, so the whole body stays in the sagittal plane):

    start x=0 ─── runway (tartan) ───┤board├─ gap ─┤ sand pit (9 m) ├──
                                      foul line = board_x

The runway is a collision box flush with z = 0; the pit is a softer,
heavily damped box (feet sink a few cm and do not bounce, like sand). The
checkered floor plane stays as scenery only. The run-up (11.7 m) is the
athlete's check mark: the practised stride puts the left foot on the board.

The athlete (JumperBuilder) is the shared humanoid with two stated muscle
changes, standing in for the tendon elasticity MuJoCo's rigid tendons lack
(the stretch-shortening "catapult" that lets human legs work fast):
    vmax      3.0 optimal lengths/s instead of 1.5 (unloaded joint speeds hip
              28, knee 25, ankle 15 rad/s; with 1.5 they are about half a
              human's and the swing hip saturates at ~5 rad/s)
    strength  1.5 x the shared peak forces (e.g. knee extension 525 N m)
ROBOLAB_LJ_VMAX=1.5 ROBOLAB_LJ_STRENGTH=1.0 restore the shared body.

Sensors added for the controller:
    board   [board_x - com_x, board_x - l_toe_x, board_x - r_toe_x, board_x]
            (distance-to-board: > 0 before the foul line)
    toes    [l_toe_x, l_toe_z, r_toe_x, r_toe_z, l_heel_x, l_heel_z, r_heel_x, r_heel_z]
    pit     [pit_x - com_x, pit contact (any body part, 0/1), runway contact (0/1)]

Metrics follow athletics: `official_m` is measured from the foul line (the
board's pit-side edge) to the nearest break in the sand made by any part of
the body (0 for a foul); `effective_m` measures from the actual take-off toe.
Approach speed is the COM horizontal velocity at the take-off touchdown
(`last_step_speed`: COM average over the final step); take-off angle is the
COM velocity direction when the take-off foot leaves the board; board
contact time, peak COM height, COM travel in flight, landing quality
(feet first, no fall-back, somersault or bounce) and effort (mean squared
activation) are reported too. A bridge run with --video also writes
<video>_metrics.json, and the video plays take-off to landing at 1/4 speed.

Environment overrides: ROBOLAB_LJ_APPROACH (metres from start to foul line;
0.25 gives a standing long jump from the board), ROBOLAB_LJ_PIT_GAP (foul
line to sand, default 0.5 m), ROBOLAB_LJ_VMAX, ROBOLAB_LJ_STRENGTH.
Practice-only: ROBOLAB_LJ_SCORE=run scores the approach alone (with the
skill's `jump 0`, running 2 m past the foul line); ROBOLAB_LJ_SEED=<n>
perturbs the standing start (runway position +-0.15 m, leg joints 0-0.04
rad) for robustness.
"""

import math
import os
import re

import numpy as np

from bridge import Task
from body import HumanoidBuilder

ROOT_BIN = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "bin")

APPROACH = float(os.environ.get("ROBOLAB_LJ_APPROACH", "11.7"))
PIT_GAP = float(os.environ.get("ROBOLAB_LJ_PIT_GAP", "0.5"))
# Muscle shortening speed (optimal lengths/s). The shared humanoid uses
# MuJoCo's default 1.5, which caps unloaded joint speeds at about half of a
# human's (hip 14, knee 12.6, ankle 7.5 rad/s; human ~25, ~20, ~15): with
# rigid tendons there is no elastic recoil to make up the difference, and
# the swing hip saturates at ~5 rad/s. The jumper doubles it.
VMAX = float(os.environ.get("ROBOLAB_LJ_VMAX", "3.0"))
# Peak isometric force multiplier (1.0 = the shared human-scale strengths);
# the jumper's 1.5 stands in for the elastic return of tendons at push-off.
STRENGTH = float(os.environ.get("ROBOLAB_LJ_STRENGTH", "1.5"))
SCORE = os.environ.get("ROBOLAB_LJ_SCORE", "jump")  # jump | run (approach only) | takeoff (take-off only)
FOOT_GEOMS = ("l_foot", "r_foot", "l_toes", "r_toes")
# practice weight on distance lost behind the board (0.3 for the v1 practice;
# 1.0 scores the official distance)
BEHIND_W = float(os.environ.get("ROBOLAB_LJ_BEHIND_W", "0.3"))  # the v2 anatomy's toes are part of the foot


class JumperBuilder(HumanoidBuilder):
    """The shared humanoid with a tunable muscle shortening speed (vmax, in
    optimal lengths per second; the shared default is MuJoCo's 1.5); the
    strength multiplier is the shared builder's own."""

    def __init__(self, *a, vmax=1.5, **k):
        super().__init__(*a, **k)
        self.vmax = vmax

    def actuators_xml(self):
        return super().actuators_xml().replace('vmax="1.5"', f'vmax="{self.vmax:g}"')


class LongJumpTask(Task):
    name = "long_jump"
    mode = "planar"
    strength = STRENGTH
    seconds = 8.0
    # 2 physics steps of 2 ms per control tick, and the controller is told so
    # (the base default 0.005 also runs 2 substeps, i.e. 4 ms, while the
    # controller integrates its springs and filters with DT = 5 ms)
    control_dt = 0.004
    board_x = APPROACH  # foul line (pit-side edge of the board)
    board_w = 0.20
    pit_gap = PIT_GAP   # foul line to the near edge of the sand
    pit_len = 9.0

    # ---- scene -----------------------------------------------------------

    vmax = VMAX

    def builder(self):
        return JumperBuilder(self.mode, strength=self.strength, wrists=self.wrists, vmax=self.vmax)

    @property
    def pit_x(self):
        return self.board_x + self.pit_gap

    def xml(self, builder):
        xml = super().xml(builder)
        # The checkered plane becomes scenery (lowered a hair, no collisions);
        # the runway and the pit below carry the physics.
        return re.sub(r'<geom name="floor"([^>]*?)contype="1" conaffinity="31"',
                      r'<geom name="floor" pos="0 0 -0.004"\1contype="0" conaffinity="0"', xml, count=1)

    def xml_extras(self):
        bx, px, pl = self.board_x, self.pit_x, self.pit_len
        run_lo, run_hi = -30.0, px
        far_lo, far_hi = px + pl, px + pl + 30.0
        sand_solid = 'solref="0.08 2" solimp="0.2 0.9 0.08" friction="0.8 0.02 0.002"'
        world = f"""
    <geom name="runway" type="box" pos="{(run_lo + run_hi) / 2:g} 0 -0.1" size="{(run_hi - run_lo) / 2:g} 0.61 0.1"
          rgba="0.72 0.3 0.24 1" contype="1" conaffinity="31" friction="1.0 0.02 0.002"/>
    <geom name="far_ground" type="box" pos="{(far_lo + far_hi) / 2:g} 0 -0.1" size="{(far_hi - far_lo) / 2:g} 1.6 0.1"
          rgba="0.45 0.6 0.35 1" contype="1" conaffinity="31"/>
    <geom name="pit" type="box" pos="{px + pl / 2:g} 0 -0.15" size="{pl / 2:g} 1.4 0.15"
          rgba="0.9 0.8 0.55 1" contype="1" conaffinity="31" {sand_solid}/>
    <geom name="pit_rim_near" type="box" pos="{px - 0.03:g} 0 0.004" size="0.03 1.43 0.006" rgba="0.95 0.95 0.95 1" contype="0" conaffinity="0"/>
    <geom name="board" type="box" pos="{bx - self.board_w / 2:g} 0 0.001" size="{self.board_w / 2:g} 0.61 0.0015"
          rgba="0.97 0.97 0.97 1" contype="0" conaffinity="0"/>
    <geom name="plasticine" type="box" pos="{bx + 0.05:g} 0 0.001" size="0.05 0.61 0.0015"
          rgba="0.35 0.55 0.3 1" contype="0" conaffinity="0"/>
    <geom name="lane_l" type="box" pos="{(run_lo + bx) / 2:g} 0.6 0.001" size="{(bx - run_lo) / 2:g} 0.025 0.001" rgba="1 1 1 1" contype="0" conaffinity="0"/>
    <geom name="lane_r" type="box" pos="{(run_lo + bx) / 2:g} -0.6 0.001" size="{(bx - run_lo) / 2:g} 0.025 0.001" rgba="1 1 1 1" contype="0" conaffinity="0"/>"""
        for k in range(1, int(pl) + 1):
            x = bx + k
            if x < px + pl:
                world += (f'\n    <geom name="mark_{k}" type="box" pos="{x:g} 1.43 0.01" size="0.01 0.03 0.01" '
                          f'rgba="0.2 0.2 0.2 1" contype="0" conaffinity="0"/>')
        return {"extra_world": world}

    # ---- run state -------------------------------------------------------

    def reset(self, m, d):
        import mujoco
        seed = os.environ.get("ROBOLAB_LJ_SEED")  # practice robustness: perturb the start (off by default)
        if seed:
            # a different, still standing start: shifted along the runway and
            # with the leg joints a little off their zero angles (initial
            # state only; nothing is touched once the controller runs)
            rng = np.random.default_rng(int(seed))
            d.joint("root_x").qpos = rng.uniform(-0.15, 0.15)
            for j in ("l_hip_flex", "r_hip_flex", "l_knee", "r_knee", "l_ankle", "r_ankle", "spine_flex"):
                d.joint(j).qpos = rng.uniform(0.0, 0.04)
            mujoco.mj_forward(m, d)
        self.gid = {n: mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_GEOM, n) for n in ("runway", "pit", "far_ground")}
        self.ground = {self.gid["runway"]: "runway", self.gid["pit"]: "pit", self.gid["far_ground"]: "far"}
        self.body_geoms = set(g for g in range(m.ngeom) if m.geom_bodyid[g] != 0)
        # every geom of each foot (the v2 anatomy adds a toe segment)
        self.foot_geoms = {g: n[0] for g in range(m.ngeom)
                           for n in [mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_GEOM, g) or ""]
                           if n in ("l_foot", "r_foot", "l_toes", "r_toes")}
        self.geom_name = {g: mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_GEOM, g) for g in self.body_geoms}
        self.pelvis_id = m.body("pelvis").id
        self.state = "approach"
        self.last_runway = None      # snapshot at the last runway contact tick (the take-off candidate)
        self.takeoff = None
        self.landing = None
        self.marks = []              # (x, geom name, time, surface) of every sand contact after landing
        self.runway_after_landing = False
        self.max_pitch_after = 0.0
        self.takeoff_cmd_t = None    # when the skill announced its take-off
        self.last_ground_t = 0.0
        self.rebound = False
        self.peak_com_z = 0.0
        self.fell = False
        self.pit_contact = 0.0
        self.runway_contact = 0.0
        self.foot_last = {"l": -1.0, "r": -1.0}   # last time each foot touched the runway
        self.foot_touch = {"l": None, "r": None}  # current contact period of each foot
        self.touchdowns = []         # (foot, time, toe x - board_x, com vx) per runway touchdown
        self.at_board = None         # COM state when it passes 1 m before the foul line
        self.at_split = None         # time the COM passes 5 m before the foul line
        self.final_pitch = []        # pelvis pitch samples over the last 3 m of the approach
        self.peak_vz_board = 0.0     # highest COM vertical velocity around the board
        self.max_com_x = 0.0

    def _contacts(self, m, d):
        feet = {}      # foot -> furthest-forward runway contact x (the toe)
        hits = []      # (x, body geom name, surface) of every body-ground contact
        for i in range(d.ncon):
            con = d.contact[i]
            for a, b in ((con.geom1, con.geom2), (con.geom2, con.geom1)):
                if a in self.body_geoms and b in self.ground:
                    x = float(con.pos[0])
                    hits.append((x, self.geom_name[a], self.ground[b]))
                    if b == self.gid["runway"] and a in self.foot_geoms:
                        f = self.foot_geoms[a]
                        feet[f] = max(feet.get(f, -1e9), x)
        return feet, hits

    def before_step(self, m, d):
        import mujoco
        mujoco.mj_subtreeVel(m, d)
        feet, hits = self._contacts(m, d)
        runway = any(h[2] == "runway" for h in hits)
        pit = any(h[2] != "runway" for h in hits)
        self.runway_contact = 1.0 if runway else 0.0
        self.pit_contact = 1.0 if pit else 0.0
        com = d.subtree_com[self.pelvis_id].copy()
        comv = d.subtree_linvel[self.pelvis_id].copy()
        t = d.time
        self.max_com_x = max(self.max_com_x, float(com[0]))
        if self.at_board is None and com[0] > self.board_x - 1.0:
            self.at_board = {"t": t, "vx": float(comv[0]), "pitch": self._pitch(d)}
        if self.at_split is None and com[0] > self.board_x - 5.0:
            self.at_split = t
        if self.state == "approach" and self.board_x - 3.0 < com[0] < self.board_x - 0.3:
            self.final_pitch.append(self._pitch(d))
        if self.board_x - 0.5 < com[0] < self.board_x + 1.5:
            self.peak_vz_board = max(self.peak_vz_board, float(comv[2]))
        for f, x in feet.items():
            if t - self.foot_last[f] > 0.03:  # a new touchdown (contact chatter is shorter)
                self.foot_touch[f] = {"t": t, "foot": f, "vx": float(comv[0]), "toe_x": x, "com_x": float(com[0])}
                self.touchdowns.append((f, round(t, 3), round(x - self.board_x, 3), round(float(comv[0]), 2),
                                        float(com[0])))
            self.foot_last[f] = t
        if self.state == "approach":
            if feet:
                f = max(feet, key=feet.get)
                self.last_runway = {"t": t, "foot": f, "toe_x": feet[f], "com": com, "comv": comv,
                                    "touch": dict(self.foot_touch[f])}
            if hits:
                self.peak_com_z = float(com[2])
            else:
                self.peak_com_z = max(self.peak_com_z, float(com[2]))
            if self.last_runway is not None and SCORE != "run":
                # The jump is measured athletics-style: the take-off is the
                # last runway contact before the body reaches the sand. A jump
                # that falls short of the sand counts too, once the skill has
                # announced its take-off (`jump:takeoff` command) and the body
                # has flown at least 0.15 s (running strides fly ~0.1 s).
                announced = self.takeoff_cmd_t is not None and self.last_runway["t"] >= self.takeoff_cmd_t - 0.05
                if pit or (not hits and announced and t - self.last_runway["t"] >= 0.15):
                    self.state = "flight"
                    self.takeoff = self.last_runway
        if self.state == "flight":
            self.peak_com_z = max(self.peak_com_z, float(com[2]))
            if hits:
                # first contact after take-off: normally the sand; a jump that
                # falls short lands on the runway and is measured there
                self.state = "landed"
                self.landing = {"t": t, "com": com, "comv": comv, "surface": "pit" if pit else "runway"}
                self.last_ground_t = t
        if self.state == "landed":
            self.max_pitch_after = max(self.max_pitch_after, abs(self._pitch(d)))
            if hits:
                self.last_ground_t = t
            elif t - self.last_ground_t > 0.1:
                self.rebound = True  # airborne again after landing: a bounce, not a recovery
            for x, g, surf in hits:
                if surf == "runway" and self.landing["surface"] == "pit":
                    self.runway_after_landing = True  # e.g. a trailing foot dragging behind the pit
                else:
                    self.marks.append((x, g, t, surf))

    def on_command(self, m, d, cmd):
        if cmd == "jump:takeoff" and self.takeoff_cmd_t is None:
            self.takeoff_cmd_t = d.time
        # `dbg:...` tokens from the controller (skill param `debug`), echoed with ROBOLAB_LJ_DEBUG=1
        if cmd.startswith("dbg:") and os.environ.get("ROBOLAB_LJ_DEBUG"):
            print(f"{d.time:6.3f} {cmd}")

    # ---- sensors -----------------------------------------------------------

    def extra_sensors(self, m, d):
        pel = d.body("pelvis").id
        com_x = float(d.subtree_com[pel][0])
        lt, rt = d.site("l_toe").xpos, d.site("r_toe").xpos
        lh, rh = d.site("l_heel").xpos, d.site("r_heel").xpos
        bx = self.board_x
        pit_c = getattr(self, "pit_contact", 0.0)
        run_c = getattr(self, "runway_contact", 0.0)
        return [
            ("board", [bx - com_x, bx - lt[0], bx - rt[0], bx]),
            ("toes", [lt[0], lt[2], rt[0], rt[2], lh[0], lh[2], rh[0], rh[2]]),
            ("pit", [self.pit_x - com_x, pit_c, run_c]),
        ]

    # ---- termination, metrics, score -----------------------------------------

    def _pitch(self, d):
        up = d.body("pelvis").xmat.reshape(3, 3)[:, 2]
        return math.atan2(up[0], up[2])

    def done(self, m, d):
        z = d.body("pelvis").xpos[2]
        if self.state == "approach" and (z < 0.5 or abs(self._pitch(d)) > 1.3):
            self.fell = True
            return True
        if SCORE == "run" and float(d.subtree_com[self.pelvis_id][0]) > self.board_x + 2.0:
            return True  # the approach practice runs through the take-off zone (skill param jump = 0)
        # a landed jump runs on to `seconds` (the recovery is part of the
        # skill), so the bridge's `fell` flag keeps meaning a real fall
        return False

    def metrics(self, m, d, log):
        com = d.subtree_com[self.pelvis_id]
        out = {"time": round(d.time, 3), "state": self.state, "com_x": round(float(com[0]), 3),
               "fell_approach": self.fell}
        if self.takeoff is not None:
            to = self.takeoff
            v = to["comv"]
            out["takeoff_toe_x"] = round(float(to["toe_x"]), 3) if to["toe_x"] is not None else None
            out["takeoff_foot"] = to["foot"]
            out["board_offset_m"] = (round(float(to["toe_x"] - self.board_x), 3)
                                     if to["toe_x"] is not None else None)  # < 0 behind the foul line
            out["foul"] = bool(to["toe_x"] is not None and to["toe_x"] > self.board_x)
            out["approach_speed"] = round(float(to["touch"]["vx"]), 3) if to["touch"] else None
            # last-step speed: COM average over the final step (previous
            # touchdown of the other foot to the take-off touchdown)
            prev = [k for k in self.touchdowns if k[1] < to["touch"]["t"] - 1e-9 and k[0] != to["foot"]]
            if prev and to["touch"]["t"] > prev[-1][1]:
                out["last_step_speed"] = round((to["touch"]["com_x"] - prev[-1][4]) / (to["touch"]["t"] - prev[-1][1]), 3)
            out["takeoff_vx"] = round(float(v[0]), 3)
            out["takeoff_vz"] = round(float(v[2]), 3)
            out["takeoff_angle_deg"] = round(math.degrees(math.atan2(float(v[2]), float(v[0]))), 1)
            out["takeoff_com_z"] = round(float(to["com"][2]), 3)
            out["contact_time_s"] = round(float(to["t"] - to["touch"]["t"]), 3) if to["touch"] else None
            out["peak_com_z"] = round(self.peak_com_z, 3)
            # the distance the take-off alone earns: toe to COM at take-off plus
            # the COM's ballistic flight down to a landing height of 0.55 m
            # (independent of how far the legs reach forward for the landing)
            g, h = 9.81, float(to["com"][2]) - 0.55
            vz = float(v[2])
            t_air = (vz + math.sqrt(max(0.0, vz * vz + 2 * g * h))) / g if h > 0 else 0.0
            out["ballistic_m"] = round(float(to["com"][0] - to["toe_x"]) + float(v[0]) * t_air, 3)
        if self.landing is not None and self.marks:
            near = min(self.marks, key=lambda k: k[0])
            first = self.landing
            out["flight_s"] = round(float(first["t"] - self.takeoff["t"]), 3)
            out["nearest_mark_x"] = round(near[0], 3)
            out["nearest_mark_by"] = near[1]
            short = first["surface"] != "pit"
            out["landed_short"] = short  # came down on the runway before the sand: not a valid jump
            out["official_m"] = round(near[0] - self.board_x, 3) if not (out.get("foul") or short) else 0.0
            out["effective_m"] = round(near[0] - float(self.takeoff["toe_x"]), 3)
            out["com_travel_m"] = round(float(first["com"][0] - self.takeoff["com"][0]), 3)
            first_marks = [k for k in self.marks if k[2] <= first["t"] + 0.05]
            out["first_mark_x"] = round(min(k[0] for k in first_marks), 3) if first_marks else None
            out["landed_on"] = first["surface"]
            out["touched_runway_after_landing"] = self.runway_after_landing
            feet_marks = [k[0] for k in self.marks if k[1] in FOOT_GEOMS]
            heel = min(feet_marks) if feet_marks else near[0]
            # fell back: a hand, the seat or the back broke the sand behind the heels
            out["fell_back"] = bool(near[1] not in FOOT_GEOMS and near[0] < heel - 0.02)
            out["landing_com_vx"] = round(float(first["comv"][0]), 3)
            # a clean landing: feet first, no body part behind the heels, no
            # somersault (pelvis pitch within 1.7 rad) and no bounce afterwards
            out["max_pitch_after_landing"] = round(self.max_pitch_after, 3)
            out["flipped"] = self.max_pitch_after > 1.7
            out["rebound"] = self.rebound
            out["clean_landing"] = bool(near[1] in FOOT_GEOMS and not out["fell_back"]
                                        and not out["flipped"] and not short and not self.rebound)
            out["final_pelvis_z"] = round(float(d.body("pelvis").xpos[2]), 3)
            # recovered: ends crouching, sitting or standing, not lying in the sand
            out["recovered"] = bool(d.body("pelvis").xpos[2] > 0.45 and abs(self._pitch(d)) < 0.9)
        out["touchdowns"] = [(k[0], k[2], k[3]) for k in self.touchdowns[-6:]]  # (foot, toe - foul line, COM vx)
        out["steps"] = len(self.touchdowns)
        out["peak_vz_board"] = round(self.peak_vz_board, 3)
        out["max_com_x"] = round(self.max_com_x, 3)
        if self.at_board is not None:
            out["speed_at_board"] = round(self.at_board["vx"], 3)  # COM vx 1 m before the foul line
            out["t_at_board"] = round(self.at_board["t"], 3)
            if self.final_pitch:
                out["final_pelvis_pitch"] = round(float(np.mean(self.final_pitch)), 3)  # rad, + = forward
            if self.at_split is not None and self.at_board["t"] > self.at_split:
                out["mean_speed_last4m"] = round(4.0 / (self.at_board["t"] - self.at_split), 3)
        if log:
            acts = np.array([row[2] for row in log])
            out["effort_msa"] = round(float(np.mean(acts ** 2)), 4)  # mean squared activation, whole run
            if self.takeoff is not None:
                t_to = self.takeoff["t"]
                run = acts[[i for i, row in enumerate(log) if row[0] <= t_to]]
                if len(run):
                    out["effort_msa_approach"] = round(float(np.mean(run ** 2)), 4)
        return out

    def score(self, mt):
        """Practice objective: effective distance landed, clean and legal.
        With ROBOLAB_LJ_SCORE=run: reach the board upright and fast."""
        if mt.get("error"):
            return -1e9
        if SCORE == "takeoff" and "ballistic_m" in mt:
            # take-off practice: the flight the take-off earns, legal and on the board
            s = mt["ballistic_m"]
            off = mt.get("board_offset_m") or 0.0
            if off > 0:
                s -= 1.0 + 4.0 * off
            else:
                s -= 0.5 * max(0.0, -off - 0.2)
            return s
        if SCORE == "run":
            if mt.get("max_com_x", 0.0) > self.board_x + 2.0 and not mt.get("fell_approach"):
                # fast, economical, and running tall into the board
                return (4.0 + mt.get("mean_speed_last4m", 0.0) + 0.25 * mt["speed_at_board"]
                        - 1.0 * mt.get("effort_msa", 0.0)
                        - 3.0 * max(0.0, mt.get("final_pelvis_pitch", 0.0) - 0.3))
            s = 3.0 * min(1.0, mt.get("max_com_x", 0.0) / (self.board_x + 2.0))
            return s - (1.0 if mt.get("fell_approach") else 0.0)
        if "effective_m" not in mt:
            # no jump: reward progress toward and past the board, and any
            # upward pop at the board (a gradient toward a real take-off)
            s = min(mt.get("max_com_x", 0.0), self.board_x + 2.0) * 0.2 - 6.0
            s += 0.5 * max(0.0, mt.get("peak_vz_board", 0.0))
            if mt.get("fell_approach"):
                s -= 2.0
            return s
        s = mt["effective_m"]
        off = mt.get("board_offset_m") or 0.0
        # toe on the board is the ideal; far behind wastes distance (the
        # official jump loses all of it; BEHIND_W weighs it), beyond is a foul
        if off > 0:
            s -= 1.0 + 4.0 * off
        else:
            s -= BEHIND_W * max(0.0, -off - 0.3 * (1.0 - BEHIND_W))
        if mt.get("fell_back"):
            s -= 0.3
        if mt.get("landed_short"):
            s -= 0.3
        if mt.get("flipped"):
            s -= 0.7
        if mt.get("rebound"):
            s -= 1.0
        if "recovered" in mt and not mt["recovered"]:
            s -= 0.3
        if mt.get("flight_s", 0.0) < 0.15:
            s -= 2.0  # stepped or fell into the sand: no flight, no jump
        return s

    # ---- presentation ----------------------------------------------------

    slow_factor = 4  # take-off, flight and landing play at 1/4 speed in the video

    def slow_motion(self, m, d):
        """Playback slow-down for the frame about to be captured: from 1.5 m
        before the board until 0.7 s after the first sand contact."""
        com_x = float(d.subtree_com[self.pelvis_id][0])
        if self.state == "approach":
            return self.slow_factor if com_x > self.board_x - 1.5 else 1
        if self.state == "flight":
            return self.slow_factor
        if self.state == "landed" and d.time - self.landing["t"] < 0.7:
            return self.slow_factor
        return 1

    def camera(self, m, d, cam):
        p = d.body("pelvis").xpos
        cam.lookat[:] = [p[0] + 0.5, 0.0, 0.8]
        cam.distance = 5.2
        cam.azimuth = 90
        cam.elevation = -5

    def title(self):
        return "robolab: long jump (planar muscle humanoid, sagittal plane)"

    def hud_text(self, m, d):
        pel = d.body("pelvis").id
        com = d.subtree_com[pel]
        comv = d.subtree_linvel[pel]
        s = f"board {self.board_x - com[0]:6.2f} m   vx {comv[0]:5.2f} m/s   COM z {com[2]:4.2f}"
        if self.takeoff is not None and self.state == "landed":
            v = self.takeoff["comv"]
            s += f"   take-off {v[0]:.2f} m/s @ {math.degrees(math.atan2(v[2], v[0])):.0f} deg"
        if self.landing is not None and self.marks:
            near = min(k[0] for k in self.marks)
            s += f"   jump {near - float(self.takeoff['toe_x']):4.2f} m"
        if self.slow_motion(m, d) > 1:
            s += f"   [slow motion x{self.slow_factor}]"
        return s


TASK = LongJumpTask


# ---- recorder: slow motion around the jump, a GIF under 6 MB -----------------
# bridge.main() imports render.Recorder after importing this task module, so
# installing the subclass here gives `bridge.py long_jump --video ...` its
# slow-motion segment without touching the shared renderer.
# (Proposed SDK addition: an optional Task.slow_motion(m, d) hook in render.py.)

try:
    import render as _render

    class LongJumpRecorder(_render.Recorder):
        gif_limit = 6_000_000

        def maybe_capture(self, sim):
            if sim.d.time + 1e-9 < self.next_t:
                return
            slow = getattr(sim.task, "slow_motion", lambda m, d: 1)(sim.m, sim.d)
            self.next_t += 1.0 / (self.fps * slow)
            self.capture(sim)

        def write_mp4(self, path):
            super().write_mp4(path)
            # the run's metrics beside the video: out/x.mp4 -> out/x_metrics.json
            import json
            sim = self.sim
            mt = sim.task.metrics(sim.m, sim.d, sim.log)
            mt["params"] = dict(sim.params)
            mt["body"] = {"mode": sim.task.mode, "strength": sim.task.strength, "vmax": sim.task.vmax,
                          "note": "planar root: the body is constrained to the sagittal plane"}
            out = os.path.splitext(path)[0] + "_metrics.json"
            with open(out, "w") as f:
                json.dump(mt, f, indent=2, default=float)
            print("wrote", out)

        def write_sheet(self, path, count=16, cols=4, scale=0.4):
            super().write_sheet(path, count=count, cols=cols, scale=scale)

        def write_gif(self, path, scale=0.5, every=2):
            from PIL import Image
            for scale, every in ((0.5, 2), (0.45, 3), (0.4, 3), (0.36, 4), (0.3, 5)):
                frames = [Image.fromarray(f).resize((int(self.width * scale), int(self.height * scale)))
                          for f in self.frames[::every]]
                if not frames:
                    return
                frames = [f.quantize(colors=128, method=Image.Quantize.MEDIANCUT) for f in frames]
                frames[0].save(path, save_all=True, append_images=frames[1:], loop=0,
                               duration=int(1000 * every / self.fps), optimize=True)
                if os.path.getsize(path) <= self.gif_limit:
                    break
            print("wrote", path, len(frames), "frames", os.path.getsize(path), "bytes")

    _render.Recorder = LongJumpRecorder
except ImportError:  # rendering stack absent (headless practice workers)
    pass
