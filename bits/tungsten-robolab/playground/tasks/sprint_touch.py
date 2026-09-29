"""Touch-only sprint: the SprintTouchSkill (lib/robolab/skills/sprint_touch.w,
bin/robolab_sprint_touch) on the v2 anatomy. One keyframe at toe-touch, the
command eased touch -> touch, phase bursts on the sprint muscles.

The scene, falls, perturbed standing starts (seed), flying start
(RUN_NATURAL_START=flying, at ref_speed) and metrics are run_natural_fast's
(tasks/run_natural_fast.py): the run task's speed and gait metrics
(steady_speed, peak_speed_1s, step_freq, step_length, contact_time,
flight_time, peak_grf, ...) plus the naturalness metrics against the human
reference at the measured speed (kin_rms, event_rms, speed, in_band, ...).

Practice objective (`objective`, a float so search.py --attrs can set it):
  0  sustained speed: the run task's practice score (distance, 1.5 per s
     survived, 20 x the slowest 1 s window, flight, upright, tall, cheap,
     no scuffs, -30 for a fall; speeds pay up to speed_cap) plus 20 x the
     steady speed (the arena's run_v2 metric) and a gait-timing term
  1  fast natural running: run_natural_fast's score (naturalness first,
     4.5-6 m/s, human gait timing)
  2  top speed: objective 0 plus 20 x the fastest 1 s window
     (sprint_top_speed's metric)
  4  top speed shaped toward the ideal-control stance (sprint_limits.py):
     objective 2 less st_w per rad that the steady tail's mean thigh angle at
     lift-off stays ahead of st_lo (default -0.6 rad: push on until the thigh
     is well behind) or at touchdown lands beyond st_td (0.55 rad ahead)
  5  objective 4 with the whole v4 ideal stance geometry (st_td both ways,
     touchdown knee st_ktd, stance knee flexion capped at st_kmax; st_kw per rad)
  3  pace (a curriculum stage): the distance covered, 20 x the steady
     speed, -fall_pen for a fall (default 10: two seconds of running, so
     running on beats surviving slowly), with the v_floor / grf_cap terms
Opt-in curriculum terms for objectives 0, 2 and 3 (attributes, off by default):
v_floor (m/s): -20 per m/s the tail speed (`speed`) falls short of it, so a
search cannot survive by slowing to a stumble; grf_cap (body weights): -3 per
body weight of peak vertical ground force above it.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
import mujoco  # noqa: E402
import numpy as np  # noqa: E402

from bridge import ROOT  # noqa: E402
from tasks.run import RunTask  # noqa: E402
from tasks.run_natural import JOINTS  # noqa: E402
from tasks.run_natural_fast import RunNaturalFastTask  # noqa: E402

# The flying start's posture (degrees, model convention): the instant before
# a right touchdown, as the run_v2 champion (the v3 tendon runner at ~4.8 m/s,
# params/run_v3.txt) reaches it: right leg landing with the shank near
# vertical, left leg trailing with its knee folding, the trunk leaning ~25 deg
# (pelvis 7.5, spine 17).
TOUCH_POSE = {"r_hip_flex": 29.0, "r_knee": 35.0, "r_ankle": 2.0, "r_toe": -6.0, "l_hip_flex": 15.0, "l_knee": 110.0,
              "l_ankle": 27.0, "l_toe": -14.0, "r_shoulder_flex": -9.0, "l_shoulder_flex": 19.0, "r_elbow": 110.0,
              "l_elbow": 110.0, "spine_flex": 17.0}
TOUCH_PELVIS = 7.5


class SprintTouchTask(RunNaturalFastTask):
    name = "sprint_touch"
    controller = os.path.join(ROOT, "bin", "robolab_sprint_touch")
    objective = 0.0
    speed_cap = 12.0
    ghost = False
    body_note = "v2 anatomy, planar root, strength 1.0"
    # flying start: 1 (default) the touchdown instant (TOUCH_POSE, right foot
    # 2 cm above the ground, falling at fly_vz); 0 run_natural's (mid-flight
    # after a left toe-off)
    fly_touch = 1.0
    # 2: a snapshot of the run_v2 champion's steady running (qpos, qvel,
    # activations; playground/cache/sprint_touch_<snap>.npz, recorded by
    # scratchpad/sprint_touch/snapshots.py) 8 ms before a right touchdown,
    # the seed choosing the snapshot and adding N(0, 0.02 rad) joint noise
    snap = "run_v2"
    # 1: the champion's acceleration instead (snapshots at 1.6-4.9 m/s,
    # sprint_touch_<snap>_acc.npz), so a stride practises every speed a
    # standing start passes through
    snap_acc = 0.0
    # snapshot set: 0 the first recordings; 1 ("_s1") the RunRI champions'
    # (P95: sprint_top_speed_p95's 6.94 m/s champion)
    snap_ver = 0.0
    fly_vz = -0.6
    v_floor = 0.0
    grf_cap = 99.0
    fall_pen = 10.0
    st_w = 40.0
    st_lo = -0.6
    st_td = 0.55
    # objective 5 (the v4 ideal stance, sprint_limits.py --pitch-free on v4:
    # thigh +0.46-0.53 and knee 0.50-0.55 at touchdown, knee at most
    # 0.57-0.69 in stance, thigh -0.67 to -0.71 at lift-off): objective 4 with
    # the touchdown thigh held to st_td both ways, less st_kw per rad the
    # touchdown knee misses st_ktd or the stance knee flexes past st_kmax
    st_kw = 40.0
    st_ktd = 0.5
    st_kmax = 0.7

    def metrics(self, m, d, log):
        out = super().metrics(m, d, log)
        out.update(self.stance_metrics())
        return out

    def stance_metrics(self):
        """Right-leg stances of the steady tail (t > half the run): the thigh's
        angle from vertical in world frame (+ = knee ahead of the hip) at
        touchdown and lift-off, stance time, mean vertical ground force (body
        weights) over the stance; contact flicker under 20 ms is merged."""
        if len(self.rec) < 100:
            return {}
        t = np.array([r[0] for r in self.rec]); rc = np.array([r[4] for r in self.rec], bool)
        th = np.array([r[9] for r in self.rec]); grf = np.array([r[7] for r in self.rec])
        runs, a = [], None
        for k in range(1, len(t)):
            if rc[k] and a is None:
                a = k
            elif not rc[k] and a is not None:
                if runs and t[a] - t[runs[-1][1]] < 0.02:
                    runs[-1] = (runs[-1][0], k)
                else:
                    runs.append((a, k))
                a = None
        runs = [(a, b) for a, b in runs if t[a] > t[-1] * 0.5 and t[b] - t[a] >= 0.03]
        if not runs:
            return {}
        out = {"thigh_td": round(float(np.mean([th[a] for a, _ in runs])), 3),
               "thigh_lo": round(float(np.mean([th[b] for _, b in runs])), 3),
               "stance_t": round(float(np.mean([t[b] - t[a] for a, b in runs])), 3),
               "stance_fz": round(float(np.mean([np.mean(grf[a:b]) for a, b in runs])), 3)}
        jrec = getattr(self, "jrec", None)
        if jrec is not None and len(jrec) == len(self.rec):
            kn = np.array([r[7 + JOINTS.index("r_knee")] for r in jrec])
            out.update({"knee_td": round(float(np.mean([kn[a] for a, _ in runs])), 3),
                        "knee_max": round(float(np.mean([np.max(kn[a:b]) for a, b in runs])), 3),
                        "knee_lo": round(float(np.mean([kn[b] for _, b in runs])), 3)})
        return out
    # ... with the landing hip retracting and the trailing hip swinging
    # forward at fly_w rad/s (a runner's leg at touchdown; with the joints
    # still the foot would strike the ground at the full running speed)
    fly_w = 4.0

    def _flying_start(self, m, d):
        if self.fly_touch < 0.5:
            return super()._flying_start(m, d)
        if self.fly_touch >= 1.5:
            return self._snapshot_start(m, d)
        rng = np.random.default_rng(self.seed) if self.seed is not None else None
        for j in JOINTS:
            q = math.radians(TOUCH_POSE.get(j, 0.0))
            if rng is not None and j.split("_", 1)[-1] in ("hip_flex", "knee", "ankle", "flex"):
                q += rng.normal(0.0, 0.04)
            lo, hi = m.jnt_range[m.joint(j).id]
            d.qpos[self.qadr[j]] = float(np.clip(q, lo, hi))
        d.qpos[self.pitch_adr] = math.radians(TOUCH_PELVIS) + (rng.normal(0.0, 0.02) if rng is not None else 0.0)
        mujoco.mj_forward(m, d)
        low = min(float(d.geom_xpos[g][2]) - 0.03 for g in (m.geom("r_foot").id, m.geom("r_toes").id))
        d.qpos[m.joint("root_z").qposadr[0]] += 0.02 - low
        v = self.ref_speed + (rng.normal(0.0, 0.2) if rng is not None else 0.0)
        d.qvel[m.joint("root_x").dofadr[0]] = v
        d.qvel[m.joint("root_z").dofadr[0]] = self.fly_vz
        d.qvel[m.joint("r_hip_flex").dofadr[0]] = -self.fly_w
        d.qvel[m.joint("l_hip_flex").dofadr[0]] = self.fly_w
        mujoco.mj_forward(m, d)

    def _snapshot_start(self, m, d):
        tag = self.snap + ("_acc" if self.snap_acc >= 0.5 else "") + (f"_s{int(self.snap_ver)}" if self.snap_ver >= 0.5 else "")
        z = np.load(os.path.join(ROOT, "playground", "cache", f"sprint_touch_{tag}.npz"))
        k = 0 if self.seed is None else int(self.seed) % len(z["qpos"])
        d.qpos[:] = z["qpos"][k]
        d.qvel[:] = z["qvel"][k]
        if m.na:
            d.act[:] = z["act"][k]
        d.qpos[m.joint("root_x").qposadr[0]] = self.start_x
        if self.seed is not None:
            rng = np.random.default_rng(self.seed)
            for j in JOINTS:
                if j.split("_", 1)[-1] in ("hip_flex", "knee", "ankle", "flex"):
                    a = self.qadr[j]
                    lo, hi = m.jnt_range[m.joint(j).id]
                    d.qpos[a] = float(np.clip(d.qpos[a] + rng.normal(0.0, 0.02), lo, hi))
        mujoco.mj_forward(m, d)

    def score(self, metrics):
        if "distance" not in metrics:
            return -1e6
        if 0.5 <= self.objective < 1.5:
            return RunNaturalFastTask.score(self, metrics)
        if self.objective >= 4.5:
            s = self._score2(metrics)
            s -= self.st_w * max(0.0, metrics.get("thigh_lo", 0.0) - self.st_lo)
            s -= self.st_w * abs(metrics.get("thigh_td", self.st_td) - self.st_td)
            s -= self.st_kw * abs(metrics.get("knee_td", self.st_ktd) - self.st_ktd)
            return s - self.st_kw * max(0.0, metrics.get("knee_max", 0.0) - self.st_kmax)
        if self.objective >= 3.5:
            s = self._score2(metrics)
            s -= self.st_w * max(0.0, metrics.get("thigh_lo", 0.0) - self.st_lo)
            return s - self.st_w * max(0.0, metrics.get("thigh_td", self.st_td) - self.st_td)
        if self.objective >= 2.5:
            s = metrics["distance"] + 20.0 * min(metrics.get("steady_speed", 0.0), self.speed_cap)
            s -= self.fall_pen if metrics.get("fell") else 0.0
            s -= 20.0 * max(0.0, self.v_floor - metrics.get("speed", 0.0))
            return s - 3.0 * max(0.0, metrics.get("peak_grf", 0.0) - self.grf_cap)
        return self._score2(metrics)

    def _score2(self, metrics):
        s = RunTask.score(self, metrics)
        s += 20.0 * min(metrics.get("steady_speed", 0.0), self.speed_cap)
        s -= 20.0 * max(0.0, self.v_floor - metrics.get("speed", 0.0))
        s -= 3.0 * max(0.0, metrics.get("peak_grf", 0.0) - self.grf_cap)
        if self.objective >= 1.5:
            s += 20.0 * min(metrics.get("peak_speed_1s", 0.0), self.speed_cap)
        return s

    def title(self):
        return "robolab: touch-only sprint (one touchdown keyframe + phase bursts, v2 anatomy)"


TASK = SprintTouchTask


if __name__ == "__main__":
    import tasks.run_natural as rn
    rn.RunNaturalTask = SprintTouchTask
    rn.main()
