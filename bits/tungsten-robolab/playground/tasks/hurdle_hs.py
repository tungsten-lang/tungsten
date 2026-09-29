"""High-school boys' 110 m hurdles on the planar muscle humanoid.

The course of the NFHS boys' 110 m hurdles: 10 hurdles 0.991 m (39 in) high,
the first 13.72 m from the start, 9.14 m apart, 14.02 m from the last to the
finish. ROBOLAB_HURDLE_HEIGHT / _COUNT / _FIRST / _SPACING / _RUNOUT override
it (the arena's curriculum trials lower the height; practice shortens the
course). Hurdles, sensors, step detection and per-hurdle metrics are the
`hurdle` task's (tasks/hurdle.py), which is left unchanged; this task adds:

  seeds      `task.seed` (the arena sets it per rollout) perturbs the standing
             start: a few degrees of noise on the hips, knees, ankles and spine
             and on the pelvis pitch (hurdle.py's noise model). Seed 0 or None
             is the clean start.
  cleared    a hurdle is cleared when it is passed (the pelvis past the bar,
             at the end of the run too, and a step landed beyond it; as
             hurdle.py), not knocked over (as hurdle.py), and legally: no body
             point went lower than the bar's 7 cm top board while over it (a
             leg under the bar is not a clearance; clearance margin >= -0.08
             m), and it was not passed less than 1 s before a fall (crashing
             through a hurdle ends the run before the hurdle has tipped).
             `crashed` / `under` count the hurdles those two rules removed.
  hs_time    time to the finish line (s); a run that does not finish scores
             60 s + 0.3 s per metre it fell short (so every finish ranks above
             every non-finish, and a longer run above a shorter one)
  hs_score   cleared - hs_time / 100: hurdles cleared first, time second
             (a cleared hurdle is passed and not knocked over)
  rhythm     steps between hurdles (touchdowns from the landing to the take-off)
  vmargin    per hurdle, the lowest body point over the bar's original place
             minus the bar height during the whole crossing (hurdle.py's
             `margin` stops once the hurdle starts to tip)
  score      the practice objective (clearance first, shaped by the clearance
             margin at every hurdle reached, then distance and time);
             ROBOLAB_HURDLE_SCORE=air scores the first clearance alone
             (take-off and flight practice, see air_score), =jump the take-off
             alone (peak COM height and speed kept, see jump_score)
  com_peak   per hurdle, the highest COM within 1 m of the bar (m)
  cross_vx   per hurdle, the horizontal speed as the COM crosses the bar

Bodies (all planar, strength 1.0):

  hurdle_hs      v1 body with muscle vmax 3.0 L0/s (the `hurdle` task's body)
  hurdle_hs_v2   v2 anatomy (biarticulars, toes, human-calibrated joint speeds,
                 damping and armature)
  hurdle_hs_v3   v3 anatomy (v2 + series-elastic Achilles and quadriceps
                 tendons), 1 ms physics

ROBOLAB_HURDLE_HIP3D=1 frees the hips' abduction and rotation joints under
the planar root (every leg keeps hip_flex, hip_abd, hip_rot, knee, ankle), so
the trail leg can come around the side of the bar with the knee out, as a
real hurdler's does. The root still keeps the pelvis in the sagittal plane
(no roll, no yaw). Off by default: the planar body has sagittal hips only.

ROBOLAB_HURDLE_CAM=<azimuth> renders from a three-quarter view (default: the
side view).

The floor is drawn out to the finish (MuJoCo planes collide everywhere; the
default 60 m floor would only be missing from the picture).
"""

import json
import math
import os

import mujoco
import numpy as np

from body import HumanoidV2Builder, HumanoidV3Builder, settle_fibers
from bridge import ROOT
from tasks.hurdle import HurdlerBuilder, HurdleTask, _env

HIP3D = ("hip_abd", "hip_rot")


def hip3d(base):
    """`base` with the hips' abduction and rotation joints under the planar root."""
    class Hip3D(base):
        def _dof_enabled(self, dof):
            if dof in HIP3D:
                return True
            return super()._dof_enabled(dof)
    Hip3D.__name__ = base.__name__ + "Hip3D"
    return Hip3D


class HurdleHSTask(HurdleTask):
    name = "hurdle_hs"
    controller = os.path.join(ROOT, "bin", "robolab_hurdle_hs")
    seconds = 45.0
    seed = None
    body_kind = "v1"
    CRASH_S = 1.0  # a hurdle passed this soon before a fall is not cleared
    UNDER_M = -0.08  # clearance margin below this: a body point went under the top board

    def __init__(self):
        self.strength = _env("ROBOLAB_HURDLE_STRENGTH", 1.0)
        self.vmax = _env("ROBOLAB_HURDLE_VMAX", 3.0)
        self.height = _env("ROBOLAB_HURDLE_HEIGHT", 0.991)
        self.count = _env("ROBOLAB_HURDLE_COUNT", 10)
        self.first = _env("ROBOLAB_HURDLE_FIRST", 13.72)
        self.spacing = _env("ROBOLAB_HURDLE_SPACING", 9.14)
        self.run_out = _env("ROBOLAB_HURDLE_RUNOUT", 14.02)
        self.hip3d = os.environ.get("ROBOLAB_HURDLE_HIP3D", "") not in ("", "0")
        self.xs = [self.first + k * self.spacing for k in range(self.count)]
        self.finish = self.xs[-1] + self.run_out if self.xs else 60.0
        self._cam_x = None
        self._write_now = False

    def builder(self):
        cls = hip3d(HurdlerBuilder) if self.hip3d else HurdlerBuilder
        return cls(self.mode, strength=self.strength, wrists=self.wrists, vmax=self.vmax)

    def title(self):
        hip = ", 3D hips" if self.hip3d else ""
        return (f"robolab: high-school 110 m hurdles, {self.count} x {self.height:.3f} m "
                f"({self.body_kind} planar body{hip})")

    def camera(self, m, d, cam):
        """The side view (hurdle.py); ROBOLAB_HURDLE_CAM=<azimuth deg> turns it
        to a three-quarter view (e.g. 55: from the front-left, which shows the
        trail leg coming around the side), a little higher and further out."""
        super().camera(m, d, cam)
        az = os.environ.get("ROBOLAB_HURDLE_CAM")
        if az:
            cam.azimuth = float(az)
            cam.elevation = -14
            cam.distance = 5.6

    def xml_extras(self):
        out = super().xml_extras()
        out["floor_size"] = max(60, int(self.finish) + 20)
        return out

    # ---- start -------------------------------------------------------------

    def pose_start(self, m, d):
        """Standing start; a non-zero seed adds hurdle.py's standing-pose noise."""
        if not self.seed:
            return
        rng = np.random.default_rng(int(self.seed))
        for j in ("l_hip_flex", "r_hip_flex", "l_knee", "r_knee", "spine_flex", "l_ankle", "r_ankle"):
            a = m.jnt_qposadr[m.joint(j).id]
            d.qpos[a] = float(np.clip(d.qpos[a] + rng.uniform(-0.06, 0.06), *m.jnt_range[m.joint(j).id]))
        d.qpos[m.jnt_qposadr[m.joint("root_pitch").id]] += rng.uniform(-0.04, 0.04)
        mujoco.mj_forward(m, d)
        low = min(self._geom_bottom(m, d, g) for g in self._sole_geoms(m))
        d.qpos[m.jnt_qposadr[m.joint("root_z").id]] -= low - 0.001
        mujoco.mj_forward(m, d)

    def reset(self, m, d):
        super().reset(m, d)
        self.vmargin = [None] * self.count
        self.vmargin_part = [None] * self.count
        self.com_peak = [None] * self.count   # highest COM within 1 m of each bar
        self.cross_vx = [None] * self.count   # COM speed as it crosses each bar

    def before_step(self, m, d):
        super().before_step(m, d)
        # virtual margin: the lowest body point over the bar's original place,
        # whatever the hurdle does (hurdle.py's margin stops once it tips)
        px = float(d.body("pelvis").xpos[0])
        com = d.subtree_com[self.pelvis_id]
        for k, hx in enumerate(self.xs):
            if abs(com[0] - hx) < 1.0 and (self.com_peak[k] is None or com[2] > self.com_peak[k]):
                self.com_peak[k] = float(com[2])
            if self.cross_vx[k] is None and com[0] > hx:
                self.cross_vx[k] = float(d.qvel[0])
            if abs(px - hx) < 1.6:
                low, part = self._lowest_over(m, d, hx)
                if low is not None:
                    gap = low - self.height
                    if self.vmargin[k] is None or gap < self.vmargin[k]:
                        self.vmargin[k] = gap
                        self.vmargin_part[k] = m.geom(part).name

    def _lowest_over(self, m, d, bx):
        """Lowest body point within the bar's x-extent and its geom (None if
        nothing is over it). As hurdle.py, but a box is sampled at all eight
        corners (and its edge midpoints), not only in its y = 0 plane: with 3D
        hips a foot turns out and its corners drop below that plane."""
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
                pts = [pos + mat @ (size * np.array([sx, sy, sz]))
                       for sx in (-1, 0, 1) for sy in (-1, 1) for sz in (-1, 1)]
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

    def _sole_geoms(self, m):
        out = []
        for side in ("l", "r"):
            for part in ("foot", "toes"):
                g = mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_GEOM, f"{side}_{part}")
                if g >= 0:
                    out.append(g)
        return out

    def _foot_load(self, m, d):
        """Normal force of the floor on each foot (sole + toes), in body weights,
        keyed by the foot geom."""
        if not hasattr(self, "_toe_of"):
            self._toe_of = {}
            for side, g in (("l", self.foot_geoms[0]), ("r", self.foot_geoms[1])):
                t = mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_GEOM, f"{side}_toes")
                self._toe_of[g] = g
                if t >= 0:
                    self._toe_of[t] = g
        out = {g: 0.0 for g in self.foot_geoms}
        f = np.zeros(6)
        for i in range(d.ncon):
            con = d.contact[i]
            if con.geom1 == self.floor_geom:
                other = con.geom2
            elif con.geom2 == self.floor_geom:
                other = con.geom1
            else:
                continue
            g = self._toe_of.get(other)
            if g is not None:
                mujoco.mj_contactForce(m, d, i, f)
                out[g] += abs(f[0]) / self.weight
        return out

    # ---- metrics -------------------------------------------------------------

    def metrics(self, m, d, log):
        out = super().metrics(m, d, log)
        # A hurdle passed less than CRASH_S before a fall is not cleared: a
        # runner who crashes through a hurdle and falls just beyond it ends the
        # run before the hurdle has had time to tip over (hurdle.py would count
        # it as cleared, since it was passed and has not yet fallen).
        # A body point deeper than the top board went under the bar.
        take, land, _, _ = self.strides()
        px = float(d.body("pelvis").xpos[0])
        passed = [self.cross_t[k] is not None and land[k] is not None and px > self.xs[k] and not self.knocked(k, d)
                  for k in range(self.count)]
        crashed = [k for k in range(self.count)
                   if self._fell and self.cross_t[k] is not None and d.time - self.cross_t[k] < self.CRASH_S]
        under = [k for k in range(self.count) if self.margin[k] is not None and self.margin[k] < self.UNDER_M]
        ok = [passed[k] and k not in crashed and k not in under for k in range(self.count)]
        out["vmargin"] = [None if v is None else round(float(v), 3) for v in self.vmargin]
        out["vmargin_part"] = list(self.vmargin_part)
        out["com_peak"] = [None if v is None else round(v, 3) for v in self.com_peak]
        out["cross_vx"] = [None if v is None else round(v, 3) for v in self.cross_vx]
        out["crashed"] = sum(1 for k in crashed if passed[k])
        out["under"] = sum(1 for k in under if passed[k] and k not in crashed)
        out["cleared"] = sum(ok)
        out["clean"] = sum(1 for k in range(self.count) if ok[k] and not self.touched[k])
        finished = out.get("time_to_finish") is not None
        if finished:
            t = out["time_to_finish"]
        else:
            t = min(99.9, 60.0 + 0.3 * max(0.0, self.finish - out.get("x", 0.0)))
        out["finished"] = finished
        out["hs_time"] = round(float(t), 3)
        out["hs_score"] = round(out["cleared"] - t / 100.0, 5)
        between = out.get("steps_between") or []
        out["rhythm"] = max(set(between), key=between.count) if between else None
        out["body"] = self.body_kind + ("+hip3d" if self.hip3d else "")
        path = os.environ.get("ROBOLAB_HURDLE_METRICS")
        if path:
            self._write_now = True
            self.write_metrics(path, out)
        return out

    def write_metrics(self, path, out):
        if not self._write_now:  # the base metrics() call; written once, complete
            return
        self._write_now = False
        rec = {
            "task": self.name,
            "body": {"kind": self.body_kind, "root": self.mode, "strength": self.strength,
                     "hip3d": self.hip3d, "height_m": 1.75, "mass_kg": 67.5,
                     "muscle_vmax_L0_per_s": self.vmax if self.body_kind == "v1" else "v2 calibrated per joint"},
            "course": {"hurdles": self.count, "height_m": self.height, "first_m": self.first,
                       "spacing_m": self.spacing, "finish_m": self.finish, "hurdle_x_m": self.xs,
                       "tip_force_N": self.tip_force},
            "seed": self.seed,
            "metrics": {k: (bool(v) if isinstance(v, (bool, np.bool_)) else v) for k, v in out.items()},
            "steps": [{"t": round(t, 3), "foot": f, "x": round(x, 3)} for t, f, x in self.steps()],
        }
        with open(path, "w") as fh:
            json.dump(rec, fh, indent=1, default=float)

    def score(self, metrics):
        """Practice objective, ordered like hs_score: hurdles cleared first (30
        each, clean ones 5 more), shaped by the clearance margin and the COM
        height over every bar reached (so near misses teach); then reaching the
        finish upright (10) and beating a 4 m/s pace (1 per second), distance
        (0.2 per metre), and an upright run. A knocked hurdle earns only its
        shaping and the distance run past it."""
        if "error" in metrics:
            return -1e9
        if os.environ.get("ROBOLAB_HURDLE_SCORE") == "air":
            return self.air_score(metrics)
        if os.environ.get("ROBOLAB_HURDLE_SCORE") == "jump":
            return self.jump_score(metrics)
        s = 0.2 * min(metrics.get("x", 0.0), self.finish)
        s += 30.0 * metrics.get("cleared", 0) + 5.0 * metrics.get("clean", 0)
        for v in metrics.get("margin") or []:
            if v is not None:
                s += 20.0 * max(-0.3, min(0.08, v))
        for v in metrics.get("com_clearance") or []:
            if v is not None:
                s += 5.0 * max(-0.2, min(0.35, v))
        if metrics.get("time_to_finish") is not None:
            s += 10.0 + (self.finish / 4.0 - metrics["time_to_finish"])
        if metrics.get("pelvis_z") is not None:
            s -= 60.0 * max(0.0, 0.85 - metrics["pelvis_z"])
        if metrics.get("fell"):
            s -= 10.0
        return s


    def jump_score(self, metrics):
        """Practice objective for the take-off alone (ROBOLAB_HURDLE_SCORE=
        jump; end the rollout just after the first bar): the highest COM within
        1 m of the first bar (m, x 20) plus the horizontal speed kept as the COM
        crosses it (m/s, x 2); a take-off that never reaches the bar scores -10."""
        peak = (metrics.get("com_peak") or [None])[0]
        vx = (metrics.get("cross_vx") or [None])[0]
        if peak is None or vx is None:
            return -10.0
        return 20.0 * peak + 2.0 * vx

    def air_score(self, metrics):
        """Practice objective for the take-off and flight alone
        (ROBOLAB_HURDLE_SCORE=air; run the rollout only until just after the
        first landing): the first hurdle's clearance margin and COM height over
        it, and 20 for going over it untouched (a fall after the landing does
        not count against it)."""
        com = (metrics.get("com_clearance") or [None])[0]
        if com is None:  # the COM never crossed the bar
            return -16.0
        # the virtual margin (lowest body point over the bar's original place
        # during the whole crossing) keeps a gradient even when the bar is hit
        vm = (metrics.get("vmargin") or [None])[0]
        vm = -0.3 if vm is None else vm
        # a crossing cut short (the run fell before the pelvis was 0.5 m past
        # the bar, so the trail leg never crossed) counts as a -0.2 m miss
        if metrics.get("x", 0.0) < self.xs[0] + 0.5:
            vm = min(vm, -0.2)
        s = 40.0 * max(-0.3, min(0.08, vm))
        s += 5.0 * max(-0.2, min(0.35, com))
        land = (metrics.get("landing_dist") or [None])[0]
        if land is not None and metrics.get("touched", 0) == 0 and metrics.get("knocked", 0) == 0:
            s += 20.0
        return s


class HurdleHSV2Task(HurdleHSTask):
    name = "hurdle_hs_v2"
    body_kind = "v2"

    def builder(self):
        cls = hip3d(HumanoidV2Builder) if self.hip3d else HumanoidV2Builder
        return cls(self.mode, strength=self.strength, wrists=self.wrists)


class HurdleHSV3Task(HurdleHSTask):
    name = "hurdle_hs_v3"
    body_kind = "v3"
    timestep = float(os.environ.get("ROBOLAB_V3_TIMESTEP", "0.001"))

    def builder(self):
        cls = hip3d(HumanoidV3Builder) if self.hip3d else HumanoidV3Builder
        return cls(self.mode, strength=self.strength, wrists=self.wrists)

    def reset(self, m, d):
        super().reset(m, d)
        settle_fibers(m, d)


TASK = HurdleHSTask
