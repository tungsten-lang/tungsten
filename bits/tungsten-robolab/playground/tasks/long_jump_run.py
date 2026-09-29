"""Long jump with a sprinter's run-up (LongJumpRunSkill), average v3 body.

The scene, sensors and metrics are long_jump's (tasks/long_jump.py: runway,
board, 0.5 m to the sand, a 9 m pit), on the v3 anatomy of long_jump_v3
(series-elastic Achilles and quadriceps tendons, strength 1.0, 1 ms physics,
seeded starts: task.seed perturbs the standing start, runway position
+-0.15 m and leg joints 0-0.04 rad). What changes:

  run-up     the athlete's check mark, default 35.6 m (ROBOLAB_LJ_APPROACH
             overrides it, as for every long-jump task): a sprinter needs
             ~25-35 m to reach speed. World Athletics TR 29.1: the runway is
             at least 40 m, 45 m where conditions permit, so a check mark
             up to ~45 m is available on a standard runway.
  seconds    long enough for the run-up, the jump and >= 2 s after the
             landing (the metrics cover the whole rollout, so a fall back or
             a step out of the pit after the landing still counts).
  rules      stricter than long_jump's metrics, after World Athletics TR 29-30
             (Competition and Technical Rules, 2026 edition):
             30.1.1 a foul is the take-off foot's FRONT breaking the vertical
                 plane of the take-off line at any tick of its last stance
                 (the rule since November 2020; long_jump checks only the
                 contact point at the last tick), or any runway contact beyond
                 the line (a touch after the take-off, TR 30.1.4);
             30.1.4 landing short of the sand (a runway contact after the
                 take-off) is a failure (long_jump already);
             30.1.5 touching the runway (outside the landing area, closer to
                 the take-off line than the sand) after landing is a failure;
             30.1.3 no somersault: the torso pitching past 120 deg from
                 vertical (head well below the hips, rolling over) at any time
                 after the take-off fails the jump (`somersault`);
             TR 29.9: the mark is the nearest break in the sand made by ANY
             part of the body at any time after the landing (hands, seat, a
             fall back), measured perpendicular to the take-off line
             (long_jump already).
             `official_m` applies all of them (0 for a failed jump); the
             original, laxer values stay as `official_lj_m` / `foul_lj`.

Extra metrics: `plant_angle_deg` (the take-off leg's angle to the ground at
touchdown, hip joint to ankle joint; human plants ~60 deg), `plant_foot_ahead_m`
(ankle ahead of the COM then), `foul_max_x` (the take-off foot's front, or any runway
contact, at its furthest in the take-off stance, relative to the line, m;
< 0 = behind), `peak_speed_1s_run` (the fastest 1 s COM
window of the approach), `speed_5m` (COM mean over the last 5 m before the
take-off touchdown), `speed_loss` (COM vx at the take-off touchdown minus at
take-off), `pen_step_m` / `last_step_m` (the last two step lengths, toe to
toe), `com_drop_m` (COM height at the take-off touchdown relative to the
approach's mean over the 4 m before it).

`long_jump_p95` is this task on the 95th-percentile body.
"""

import math
import os

import numpy as np

from body import HumanoidV2Builder, HumanoidV3Builder
from tasks.long_jump import ROOT_BIN
from tasks.long_jump_v3 import RIGID, TENDON_SCALE, LongJumpV3Task

CHECK_MARK_RUN = float(os.environ.get("ROBOLAB_LJ_APPROACH", "35.6"))
# TR 30.1.3 (somersault): torso pitch from vertical beyond 120 deg after the
# take-off, in the air or while landing, fails the jump
SOMERSAULT_RAD = 2.1


class LongJumpRunTask(LongJumpV3Task):
    name = "long_jump_run"
    controller = os.path.join(ROOT_BIN, "robolab_long_jump_run")
    board_x = CHECK_MARK_RUN
    profile = None          # body_profile.py profile (None: the builder's own / env default)
    profile_parts = None
    run_speed = 4.6         # a conservative mean approach speed (m/s), for the rollout length

    @property
    def seconds(self):
        # standing start ~1.5 s, the run-up at run_speed, then the jump and
        # at least 2 s of landing and recovery
        return round(1.5 + self.board_x / self.run_speed + 3.5, 1)

    def builder(self):
        kw = dict(strength=self.strength, wrists=self.wrists)
        if self.profile:
            kw.update(profile=self.profile, profile_parts=self.profile_parts)
        if RIGID:
            return HumanoidV2Builder(self.mode, **kw)
        return HumanoidV3Builder(self.mode, stiffness_scale=TENDON_SCALE, **kw)

    def reset(self, m, d):
        super().reset(m, d)
        self.foul_max_x = -1e9       # furthest runway contact x (any body part) since the take-off touchdown
        self.contact_max = {}        # foot -> furthest runway contact x in its current contact period
        self.run_trace = []          # (t, com x, com vx, com z) every 10 ms of the approach
        self._next_trace = 0.0
        self.after_landing_runway = False
        self.pitch_hist = []         # (t, torso pitch rad, + = forward) every step from 3 m before the line on

    def _torso_pitch(self, d):
        up = d.body("torso").xmat.reshape(3, 3)[:, 2]
        return math.atan2(up[0], up[2])

    def before_step(self, m, d):
        super().before_step(m, d)
        if self.state != "approach" or float(d.subtree_com[self.pelvis_id][0]) > self.board_x - 3.0:
            # the torso's pitch from vertical, for TR 30.1.3 (no somersault;
            # see metrics)
            # (subtree_angmom is filled by long_jump's mj_subtreeVel this step)
            self.pitch_hist.append((d.time, self._torso_pitch(d), float(d.subtree_angmom[self.pelvis_id][1])))
        if self.state == "approach":
            feet, hits = self._contacts(m, d)
            t = d.time
            for f, x in feet.items():
                tch = self.foot_touch.get(f)
                if tch is not None and tch["t"] == t and "leg_angle" not in tch:
                    # the leg's angle to the ground at touchdown: hip joint to
                    # ankle joint, measured on the side the foot is on (90 =
                    # vertical; human take-off plants ~60 deg)
                    hip = d.xpos[m.body(f + "_thigh").id]
                    ank = d.xpos[m.body(f + "_foot").id]
                    tch["leg_angle"] = math.degrees(math.atan2(hip[2] - ank[2], abs(ank[0] - hip[0])))
                    tch["foot_ahead"] = float(ank[0] - d.subtree_com[self.pelvis_id][0])
                # the front of the foot (its toe box's forward-most corner):
                # TR 30.1.1 fouls a take-off foot whose front breaks the
                # vertical plane of the take-off line
                x = max(x, self._foot_front(m, d, f))
                t0 = self.foot_touch[f]["t"]  # this contact period's touchdown (set by long_jump)
                cur = self.contact_max.get(f)
                if cur is None or cur[0] != t0:
                    cur = (t0, x)
                self.contact_max[f] = (t0, max(cur[1], x))
            # any body part on the runway beyond the line (a foul whenever it
            # happens before the take-off)
            for x, g, surf in hits:
                if surf == "runway" and x > self.board_x:
                    self.foul_max_x = max(self.foul_max_x, x)
            if t >= self._next_trace:
                self._next_trace = t + 0.01
                pel = self.pelvis_id
                self.run_trace.append((t, float(d.subtree_com[pel][0]), float(d.subtree_linvel[pel][0]),
                                       float(d.subtree_com[pel][2])))

    def _foot_front(self, m, d, foot):
        """World x of the forward-most point of a foot's box geoms."""
        best = -1e9
        for g, f in self.foot_geoms.items():
            if f != foot or m.geom_type[g] != 6:  # mjGEOM_BOX
                continue
            R = d.geom_xmat[g].reshape(3, 3)
            h = m.geom_size[g]
            best = max(best, float(d.geom_xpos[g][0] + abs(R[0, 0]) * h[0] + abs(R[0, 1]) * h[1] + abs(R[0, 2]) * h[2]))
        return best

    def metrics(self, m, d, log):
        out = super().metrics(m, d, log)
        out["official_lj_m"] = out.get("official_m", 0.0)
        out["foul_lj"] = out.get("foul", False)
        to = self.takeoff
        if to is None:
            out["official_m"] = 0.0
            return out
        tch = to["touch"]
        cm = self.contact_max.get(to["foot"])
        stance_max = cm[1] if cm is not None and tch and abs(cm[0] - tch["t"]) < 1e-9 else float(to["toe_x"])
        max_x = max(stance_max, self.foul_max_x)
        out["foul_max_x"] = round(max_x - self.board_x, 3)
        if tch and "leg_angle" in tch:
            out["plant_angle_deg"] = round(tch["leg_angle"], 1)
            out["plant_foot_ahead_m"] = round(tch["foot_ahead"], 3)
        foul = max_x > self.board_x
        out["foul"] = bool(foul)
        # TR 30.1.3, no somersault: past SOMERSAULT_RAD from vertical at any
        # time after the take-off the head is well below the hips, rolling
        # over (lying face down in the sand is ~1.6 rad)
        ph = np.array(self.pitch_hist) if self.pitch_hist else np.zeros((0, 3))
        t_to = float(to["t"])
        t_land = float(self.landing["t"]) if self.landing is not None else float("inf")
        after = ph[ph[:, 0] >= t_to - 1e-9] if len(ph) else ph
        air = after[after[:, 0] <= t_land] if len(after) else after
        max_after = float(np.abs(after[:, 1]).max()) if len(after) else 0.0
        out["max_torso_pitch_after"] = round(max_after, 3)
        out["torso_pitch_takeoff"] = round(float(after[0, 1]), 3) if len(after) else None
        # whole-body angular momentum about the COM at the take-off (y: + =
        # forward somersault), and at the take-off foot's touchdown
        out["L_takeoff"] = round(float(after[0, 2]), 2) if len(after) else None
        if tch and len(ph):
            k = int(np.argmin(np.abs(ph[:, 0] - float(tch["t"]))))
            out["L_touchdown"] = round(float(ph[k, 2]), 2)
        out["max_torso_flight"] = round(float(air[:, 1].max()), 3) if len(air) else None
        land = after[after[:, 0] >= t_land] if len(after) else after
        out["torso_pitch_landing"] = round(float(land[0, 1]), 3) if len(land) else None
        somersault = max_after > SOMERSAULT_RAD
        out["somersault"] = bool(somersault)
        failed = (foul or somersault or out.get("landed_short", False)
                  or out.get("touched_runway_after_landing", False))
        if "official_m" in out:
            out["official_m"] = 0.0 if failed else out["official_m"]
        else:
            out["official_m"] = 0.0
        out["failed"] = bool(failed)
        # the approach
        tr = np.array(self.run_trace) if self.run_trace else np.zeros((0, 4))
        if len(tr) > 100 and tch:
            t_td = tch["t"]
            run = tr[tr[:, 0] <= t_td]
            if len(run) > 100:
                # fastest 1 s window of the approach (COM displacement / 1 s)
                x = run[:, 1]
                k = 100
                v1 = (x[k:] - x[:-k]) / (run[k:, 0] - run[:-k, 0])
                out["peak_speed_1s_run"] = round(float(v1.max()), 3)
                x_td = float(tch["com_x"])
                sel = run[run[:, 1] >= x_td - 5.0]
                if len(sel) > 5:
                    out["speed_5m"] = round(float((sel[-1, 1] - sel[0, 1]) / max(1e-6, sel[-1, 0] - sel[0, 0])), 3)
                sel = run[(run[:, 1] >= x_td - 5.0) & (run[:, 1] <= x_td - 1.0)]
                if len(sel) > 5:
                    out["com_drop_m"] = round(float(self._com_z_at(t_td)) - float(sel[:, 3].mean()), 3)
            out["speed_loss"] = round(float(tch["vx"]) - float(to["comv"][0]), 3)
        tds = [k for k in self.touchdowns if tch and k[1] <= tch["t"] + 1e-9]
        if len(tds) >= 3:
            out["last_step_m"] = round(tds[-1][2] - tds[-2][2], 3)
            out["pen_step_m"] = round(tds[-2][2] - tds[-3][2], 3)
        return out

    def score(self, mt):
        """Practice objective. ROBOLAB_LJR_SCORE=jump (default): the jump
        itself, effective distance from the take-off toe, with a light cost
        for taking off far behind the line (ROBOLAB_LJ_BEHIND_W, default 0.3
        per m beyond 0.1 m) and a graded cost for a foul; =official: the
        arena's legal distance, graded below zero for fouls. Both: a fall,
        a landing short of the sand, a touch outside the pit after the
        landing or a step into the pit (flight < 0.3 s) costs extra."""
        if mt.get("error"):
            return -1e9
        mode = os.environ.get("ROBOLAB_LJR_SCORE", "jump")
        behind_w = float(os.environ.get("ROBOLAB_LJ_BEHIND_W", "0.3"))
        if "effective_m" not in mt or self.takeoff is None:
            s = min(mt.get("max_com_x", 0.0), self.board_x + 2.0) / max(1.0, self.board_x) * 2.0 - 6.0
            s += 0.5 * max(0.0, mt.get("peak_vz_board", 0.0))
            return s - (2.0 if mt.get("fell_approach") else 0.0)
        off = mt.get("board_offset_m") or 0.0
        fmx = mt.get("foul_max_x", off)
        if mode == "official":
            s = mt.get("official_m", 0.0)
            if mt.get("foul"):
                s = -0.5 - 4.0 * max(0.0, fmx)
        else:
            s = mt["effective_m"] - behind_w * max(0.0, -off - 0.1)
            if mt.get("foul"):
                s -= 0.5 + 4.0 * max(0.0, fmx)
        if mt.get("somersault"):
            # graded by the forward rotation already reached in the air (the
            # pitch after the landing saturates at pi for any full roll)
            s = min(s, 0.0) - 1.0 - max(0.0, mt.get("max_torso_flight") or 2.0)
        if mt.get("landed_short"):
            s -= 0.5
        if mt.get("touched_runway_after_landing"):
            s -= 0.5
        if mt.get("flight_s", 0.0) < 0.3:
            s -= 2.0
        if "recovered" in mt and not mt["recovered"]:
            s -= 0.1
        return s

    def _com_z_at(self, t):
        best = None
        for row in self.run_trace:
            if row[0] <= t + 1e-9:
                best = row
        return best[3] if best else float("nan")

    def title(self):
        return "robolab: long jump with a sprint run-up (v3 anatomy, average body)"


TASK = LongJumpRunTask
