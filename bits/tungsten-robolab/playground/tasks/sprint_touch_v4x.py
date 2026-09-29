"""Round-2 practice task (sprint_touch_v4 plus two opt-in additions; every default reproduces sprint_touch_v4 exactly).

  objective 6   pace shaped toward the ideal stance: the distance covered + 20 x the steady speed - fall_pen for a fall (objective 3's score),
                less st_w per rad the steady tail's mean thigh angle at lift-off stays ahead of st_lo, or misses st_td at touchdown, and
                st_kw per rad the touchdown knee misses st_ktd or the stance knee flexes past st_kmax (objective 5's shaping terms).
                (Objective 5 adds them to RunTask's practice score, which pays a fall only 30 points and time and flight terms; this one
                is objective 3's plain pace so a fall costs fall_pen.)
  ROBOLAB_TRUNK_STAB="kp,kd,limit[,mode]"   DIAGNOSTIC ONLY, not an actuator the body has: an ideal external torque on the torso body
                (about the world y axis) = clip(-kp (pitch - ref) - kd pitch_rate, +-limit) N m, where ref is the torso pitch low-passed with
                time constant ROBOLAB_TRUNK_STAB_TAU (default 0.5 s, i.e. it removes the stride's rocking and leaves the mean lean to the
                controller; ROBOLAB_TRUNK_STAB_REF=<rad> holds a fixed angle instead). mode "always" (default) or "stance" (a foot loaded).
                Used to ask how much an ideal trunk actuator of a given strength would buy; nothing entered in the arena uses it.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
import mujoco  # noqa: E402
import numpy as np  # noqa: E402

from tasks.sprint_touch_v4 import SprintTouchV4Task  # noqa: E402


class SprintTouchV4XTask(SprintTouchV4Task):
    name = "sprint_touch_v4x"
    body_note = "v4 anatomy (calibrated), planar root, 1 ms physics; objective 6 and the diagnostic trunk torque are opt-in"

    def __init__(self):
        super().__init__()
        spec = os.environ.get("ROBOLAB_TRUNK_STAB", "")
        self.stab = None
        if spec:
            p = spec.split(",")
            self.stab = {"kp": float(p[0]), "kd": float(p[1]), "limit": float(p[2]), "mode": p[3] if len(p) > 3 else "always",
                         "tau": float(os.environ.get("ROBOLAB_TRUNK_STAB_TAU", "0.5")),
                         "ref": float(os.environ["ROBOLAB_TRUNK_STAB_REF"]) if os.environ.get("ROBOLAB_TRUNK_STAB_REF") else None}
        self._stab_ready = False

    def reset(self, m, d):
        super().reset(m, d)
        self._stab_ready = False
        self.stab_peak = 0.0

    def before_step(self, m, d):
        super().before_step(m, d)
        if self.stab is None:
            return
        if not self._stab_ready:
            self._tid = m.body("torso").id
            self._floor_geoms = {m.geom(n).id for n in ("l_foot", "r_foot", "l_toes", "r_toes")}
            tu = d.xmat[self._tid].reshape(3, 3)[:, 2]
            self._ref = math.atan2(tu[0], tu[2])
            self._stab_ready = True
        s = self.stab
        d.xfrc_applied[self._tid, :] = 0.0
        tu = d.xmat[self._tid].reshape(3, 3)[:, 2]
        pitch = math.atan2(tu[0], tu[2])
        vv = np.zeros(6)
        mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_BODY, self._tid, vv, 0)
        if s["ref"] is None:
            self._ref += (pitch - self._ref) * min(1.0, m.opt.timestep / s["tau"])
            ref = self._ref
        else:
            ref = s["ref"]
        if s["mode"] == "stance":
            on = any((c.geom1 in self._floor_geoms) or (c.geom2 in self._floor_geoms) for c in d.contact[:d.ncon])
            if not on:
                return
        tq = max(-s["limit"], min(s["limit"], -s["kp"] * (pitch - ref) - s["kd"] * vv[1]))
        d.xfrc_applied[self._tid, 4] = tq
        self.stab_peak = max(self.stab_peak, abs(tq))

    def metrics(self, m, d, log):
        out = super().metrics(m, d, log)
        if self.stab is not None:
            out["stab_peak"] = round(self.stab_peak, 1)
        return out

    def score(self, metrics):
        if self.objective < 5.5:
            return super().score(metrics)
        if "distance" not in metrics:
            return -1e6
        s = metrics["distance"] + 20.0 * min(metrics.get("steady_speed", 0.0), self.speed_cap)
        s -= self.fall_pen if metrics.get("fell") else 0.0
        s -= 20.0 * max(0.0, self.v_floor - metrics.get("speed", 0.0))
        s -= 3.0 * max(0.0, metrics.get("peak_grf", 0.0) - self.grf_cap)
        s -= self.st_w * max(0.0, metrics.get("thigh_lo", 0.0) - self.st_lo)
        s -= self.st_w * abs(metrics.get("thigh_td", self.st_td) - self.st_td)
        s -= self.st_kw * abs(metrics.get("knee_td", self.st_ktd) - self.st_ktd)
        return s - self.st_kw * max(0.0, metrics.get("knee_max", 0.0) - self.st_kmax)

    def title(self):
        return "robolab: sprint practice, v4 anatomy (calibrated), round 2"


TASK = SprintTouchV4XTask
