"""Search benchmark P3: a FROZEN copy of the running skill (tasks/run.py and
bin/robolab_run as of 2026-09-26 02:40, copied so the benchmark does not move
while the run agent keeps editing run.w / run.py). The controller is
bin/frozen/robolab_run; the practised parameters it was tuned with are
params/search/run_frozen_init.txt. Everything below the RunTask docstring is
the original task, unchanged except `name` and `controller` (and `import os`).

Run: accelerate from a standstill into a sustained run (planar muscle humanoid).

The body starts standing still; the RunSkill leans, takes its first push,
and accelerates into a running gait with flight phases. The task records
the run at every physics step and reports:

  distance            pelvis x travelled (m)
  speed_last5         average speed over the last 5 s (m/s)
  speed_10s           average speed over the last 10 s (m/s)
  min_speed_1s        slowest 1 s window inside the last 10 s (m/s)
  time_at_3           longest stretch whose every 1 s window averages >= 3 m/s (s)
  stride_freq         left-foot touchdowns per second over the last 5 s (Hz)
  stride_length       speed_last5 / stride_freq (m)
  flight_frac         fraction of the last 5 s with neither foot on the ground
  torso_pitch         mean and max forward lean of the torso over the last 5 s (rad)
  pelvis_z            mean pelvis height over the last 5 s (m; 0.955 standing)
  thigh_peak          per-stride peak swing-thigh angle forward of vertical, mean
                      over the last 5 s (rad, world frame; 1.57 = horizontal)
  knee_lift           per-stride peak knee height above the floor, mean over the
                      last 5 s (m; knee_stand is the standing value)
  pelvis_pitch        mean forward pitch of the pelvis over the last 5 s (rad);
                      torso_pitch - pelvis_pitch is the lean taken at the spine
  com_lead            mean COM x minus stance-foot x over single support in the
                      last 5 s (m; positive = COM ahead of the foot)
  effort              mean squared muscle activation over the run
  time / fell         time without falling, and whether the run ended in a fall
  steady_speed        average speed over the last 10 strides (left touchdown to touchdown)
  t_100m              time to cover 100 m from the standing start (the run starts at x = -50)
  contact_time        mean single-foot ground contact per step over the last 5 s (s)
  flight_time         mean airborne interval over the last 5 s (s)
  peak_grf            peak summed vertical foot force over the last 5 s (body weights)
  decisions_per_cycle chunk transitions (latch decisions) per stride over the last 5 s
  scuffs_per_s        brief (< 30 ms) foot touches outside a stance per second, last 5 s (toe drag)

The body is planar (sagittal plane: root slides in x and z and pitches about
y), muscle strength 1.0 (no scaling).

A fall is honest: the pelvis dropping below 0.6 m, the torso pitching past
1.1 rad, or anything other than a foot touching the floor ends the run.
"""

import math
import os

import mujoco
import numpy as np

from bridge import Task


class RunTask(Task):
    name = "search_run"
    controller = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "bin", "frozen", "robolab_run")
    mode = "planar"
    seconds = 20.0
    # 2 physics steps of 2 ms per control tick: the controller's DT must match
    # (the base default 0.005 rounds to 2 substeps = 4 ms of physics per tick).
    control_dt = 0.004
    fall_height = 0.6
    target_speed = 3.0  # time_at_3 counts 1 s windows at or above this
    speed_cap = 3.6     # the score stops paying for sustained speed above this
    lean_band = (-0.3, 0.3)  # mean torso pitch outside this band is penalised
    lean_weight = 10.0       # ... by this much per rad
    thigh_goal = 0.0    # the score pays thigh_weight per rad of thigh_peak up to this
    thigh_weight = 10.0
    cadence_cap = 99.0  # steps/s above this are penalised by cadence_weight per step/s
    cadence_weight = 0.0
    start_x = -50.0  # the floor spans x in [-60, 60]: room for a 100 m dash
    # Practice robustness: a seed perturbs the initial standing pose (joint
    # angles and pelvis pitch, a few degrees). None (the default, and every
    # rendered run) starts from the exact standing pose.
    seed = None

    # ---- scene -------------------------------------------------------------

    def xml_extras(self):
        # distance markers every 5 m along the track (visual only, no collision)
        marks = []
        for i in range(-50, 61, 5):
            rgba = "0.9 0.4 0.2 1" if i % 10 == 0 else "0.3 0.35 0.45 1"
            marks.append(f'<geom name="mark{i + 50}" type="box" pos="{i} 0.6 0.002" size="0.03 0.35 0.002" '
                         f'rgba="{rgba}" contype="0" conaffinity="0"/>')
        return {"extra_world": "\n    ".join(marks)}

    def reset(self, m, d):
        d.qpos[m.joint("root_x").qposadr[0]] = self.start_x
        if self.seed is not None:
            rng = np.random.default_rng(self.seed)
            for j in ("l_hip_flex", "r_hip_flex", "l_knee", "r_knee", "l_ankle", "r_ankle", "spine_flex"):
                a = m.joint(j).qposadr[0]
                lo, hi = m.jnt_range[m.joint(j).id]
                d.qpos[a] = float(np.clip(d.qpos[a] + rng.normal(0.0, 0.04), lo, hi))
            d.qpos[m.joint("root_pitch").qposadr[0]] += rng.normal(0.0, 0.02)
        self.weight = float(sum(m.body_mass[1:])) * 9.81
        self.force = np.zeros(6)
        self.floor = m.geom("floor").id
        self.feet = {m.geom("l_foot").id, m.geom("r_foot").id}
        self.l_foot = m.geom("l_foot").id
        self.r_foot = m.geom("r_foot").id
        self.pelvis = m.body("pelvis").id
        self.torso = m.body("torso").id
        self.hips = (m.body("l_thigh").id, m.body("r_thigh").id)
        self.knees = (m.body("l_shin").id, m.body("r_shin").id)
        self.act_ids = list(range(m.nu))
        self.rec = []
        self.bad_contact = False
        self.cam_x = None

    # ---- recording and falls -----------------------------------------------

    def before_step(self, m, d):
        lc = rc = False
        grf = 0.0
        for i in range(d.ncon):
            con = d.contact[i]
            g1, g2 = con.geom1, con.geom2
            if g1 != self.floor and g2 != self.floor:
                continue
            other = g2 if g1 == self.floor else g1
            if other == self.l_foot or other == self.r_foot:
                mujoco.mj_contactForce(m, d, i, self.force)
                grf += abs(self.force[0])
                if other == self.l_foot:
                    lc = True
                else:
                    rc = True
            elif m.geom_bodyid[other] != 0:
                self.bad_contact = True
        tu = d.xmat[self.torso].reshape(3, 3)[:, 2]
        pitch = math.atan2(tu[0], tu[2])
        act = d.act[m.actuator_actadr[0]:] if m.na else d.ctrl
        pu = d.xmat[self.pelvis].reshape(3, 3)[:, 2]
        com_x = float(d.subtree_com[self.pelvis][0])
        feet_x = (float(d.geom_xpos[self.l_foot][0]), float(d.geom_xpos[self.r_foot][0]))
        legs = []
        for h, k in zip(self.hips, self.knees):
            v = d.xpos[k] - d.xpos[h]
            legs.append((math.atan2(v[0], -v[2]), float(d.xpos[k][2])))
        self.rec.append((d.time, float(d.xpos[self.pelvis][0]), float(d.xpos[self.pelvis][2]),
                         lc, rc, pitch, float(np.mean(np.square(act))), grf / self.weight,
                         legs[0][0], legs[1][0], legs[0][1], legs[1][1],
                         math.atan2(pu[0], pu[2]), com_x, feet_x[0], feet_x[1]))

    def done(self, m, d):
        if d.body("pelvis").xpos[2] < self.fall_height or self.bad_contact:
            return True
        tu = d.xmat[self.torso].reshape(3, 3)[:, 2]
        return abs(math.atan2(tu[0], tu[2])) > 1.1

    # ---- metrics -----------------------------------------------------------

    def metrics(self, m, d, log):
        out = {"time": round(d.time, 3)}
        if len(self.rec) < 10:
            out["distance"] = 0.0
            return out
        r = np.array([(t, x, z, float(lc), float(rc), p, e, g, *legs) for t, x, z, lc, rc, p, e, g, *legs in self.rec])
        t, x, lc, rc, pitch, eff, grf = r[:, 0], r[:, 1], r[:, 3] > 0.5, r[:, 4] > 0.5, r[:, 5], r[:, 6], r[:, 7]
        T = t[-1]
        out["distance"] = round(float(x[-1] - x[0]), 3)

        def x_at(tt):
            return float(np.interp(tt, t, x))

        def window_speed(a, b):
            return (x_at(b) - x_at(a)) / max(b - a, 1e-6)

        last5 = max(0.0, T - 5.0)
        out["speed_last5"] = round(window_speed(last5, T), 3) if T >= 5.0 else 0.0
        out["speed_10s"] = round(window_speed(T - 10.0, T), 3) if T >= 10.0 else 0.0
        # 1-second window speeds sampled every 0.1 s
        ws = [(a, window_speed(a, a + 1.0)) for a in np.arange(0.0, T - 1.0 + 1e-9, 0.1)]
        tail = [s for a, s in ws if a >= T - 10.0]
        out["min_speed_1s"] = round(min(tail), 3) if T >= 10.0 and tail else 0.0
        out["peak_speed_1s"] = round(max(s for _, s in ws), 3) if ws else 0.0
        best = run = 0.0
        prev = None
        for a, s in ws:
            if s >= self.target_speed:
                run = run + 0.1 if prev is not None and prev >= self.target_speed else 1.0
            else:
                run = 0.0
            best = max(best, run)
            prev = s
        out["time_at_3"] = round(best, 2)

        tail = t >= last5
        span = T - last5

        def intervals(mask, bridge=0.02):
            """(start, end) of runs where mask holds inside the tail window;
            runs separated by gaps shorter than `bridge` (contact flicker)
            are merged."""
            out, a = [], None
            for k in np.nonzero(tail)[0]:
                if mask[k] and a is None:
                    a = t[k]
                elif not mask[k] and a is not None:
                    if out and a - out[-1][1] < bridge:
                        out[-1] = (out[-1][0], t[k])
                    else:
                        out.append((a, t[k]))
                    a = None
            return out

        def touchdowns(c, window=True, scuffs=False):
            """Times a foot loads after >= 40 ms off the ground and stays loaded
            >= 30 ms (a real step); with scuffs=True, the brief touches instead
            (a swing foot's toe dragging)."""
            idx = np.nonzero(tail)[0] if window else np.arange(len(t))
            out, off_since, on_at = [], None, None
            for k in idx:
                if c[k]:
                    if on_at is None:
                        on_at = t[k]
                        lifted = off_since is not None and t[k] - off_since >= 0.04
                    off_since = None
                else:
                    if on_at is not None:
                        long_enough = t[k] - on_at >= 0.03
                        if lifted and long_enough and not scuffs:
                            out.append(on_at)
                        if not long_enough and scuffs:
                            out.append(on_at)
                        on_at = None
                    if off_since is None:
                        off_since = t[k]
            return out

        ltd, rtd = touchdowns(lc), touchdowns(rc)
        out["stride_freq"] = round(len(ltd) / span, 3) if span > 0 else 0.0
        out["step_freq"] = round((len(ltd) + len(rtd)) / span, 3) if span > 0 else 0.0
        out["stride_length"] = round(out["speed_last5"] / out["stride_freq"], 3) if out["stride_freq"] > 0 else 0.0
        out["step_length"] = round(out["speed_last5"] / out["step_freq"], 3) if out["step_freq"] > 0 else 0.0
        out["flight_frac"] = round(float(np.mean(~lc[tail] & ~rc[tail])), 3)
        # a scuff is a brief touch that is not part of a stance (the foot box
        # rocking heel to toe splits a stance into intervals a few ms apart,
        # so intervals are merged across 20 ms gaps first)
        brief = [b - a for a, b in intervals(lc) + intervals(rc) if b - a < 0.03]
        out["scuffs_per_s"] = round(len(brief) / span, 2) if span > 0 else 0.0
        contacts = [b - a for a, b in intervals(lc) + intervals(rc) if b - a >= 0.03]
        flights = [b - a for a, b in intervals(~lc & ~rc, bridge=0.0) if b - a > 0.01]
        out["contact_time"] = round(float(np.mean(contacts)), 3) if contacts else 0.0
        out["flight_time"] = round(float(np.mean(flights)), 3) if flights else 0.0
        out["peak_grf"] = round(float(np.max(grf[tail])), 2)
        out["pelvis_z"] = round(float(np.mean(r[tail, 2])), 3)
        # swing peaks: one per stride of each leg, between its touchdowns
        peaks_th, peaks_kz = [], []
        for tds, th_col, kz_col in ((ltd, 8, 10), (rtd, 9, 11)):
            for a, b in zip(tds, tds[1:]):
                w = (t >= a) & (t < b)
                if np.any(w):
                    peaks_th.append(float(np.max(r[w, th_col])))
                    peaks_kz.append(float(np.max(r[w, kz_col])))
        out["thigh_peak"] = round(float(np.mean(peaks_th)), 3) if peaks_th else 0.0
        out["knee_lift"] = round(float(np.mean(peaks_kz)), 3) if peaks_kz else 0.0
        out["knee_stand"] = round(float(r[0, 10]), 3)
        out["pelvis_pitch"] = round(float(np.mean(r[tail, 12])), 3)
        single_l = tail & lc & ~rc
        single_r = tail & rc & ~lc
        lead = np.concatenate([r[single_l, 13] - r[single_l, 14], r[single_r, 13] - r[single_r, 15]])
        out["com_lead"] = round(float(np.mean(lead)), 3) if len(lead) else 0.0
        out["torso_pitch"] = round(float(np.mean(pitch[tail])), 3)
        out["torso_pitch_max"] = round(float(np.max(np.abs(pitch[tail]))), 3)
        out["effort"] = round(float(np.mean(eff)), 4)
        # steady speed over the last 10 strides (11 left touchdowns)
        all_ltd = touchdowns(lc, window=False)
        if len(all_ltd) >= 11:
            a, b = all_ltd[-11], all_ltd[-1]
            out["steady_speed"] = round(window_speed(a, b), 3)
        else:
            out["steady_speed"] = 0.0
        out["strides"] = len(all_ltd)
        k100 = np.nonzero(x - x[0] >= 100.0)[0]
        out["t_100m"] = round(float(t[k100[0]]), 2) if len(k100) else None
        # chunk transitions per stride over the tail
        labels = [(lt, lb) for lt, lb, *_ in log if lt >= last5]
        changes = sum(1 for i in range(1, len(labels)) if labels[i][1] != labels[i - 1][1])
        out["decisions_per_cycle"] = round(changes / len(ltd), 2) if ltd else 0.0
        return out

    def score(self, metrics):
        """Practice objective: go far and fast, never fall, run tall and upright,
        fly, and do it cheaply (mean squared activation)."""
        if "distance" not in metrics:
            return -1e6
        T = metrics.get("time", 0.0)
        s = metrics["distance"] + 1.5 * T
        s += 20.0 * min(metrics.get("min_speed_1s", 0.0), self.speed_cap)
        s += 10.0 * min(metrics.get("flight_frac", 0.0), 0.25)
        lo, hi = self.lean_band
        tp = metrics.get("torso_pitch", 0.0)
        s -= self.lean_weight * (max(0.0, lo - tp) + max(0.0, tp - hi))
        s += self.thigh_weight * min(metrics.get("thigh_peak", 0.0), self.thigh_goal)
        s -= self.cadence_weight * max(0.0, metrics.get("step_freq", 0.0) - self.cadence_cap)
        s -= 100.0 * max(0.0, 0.88 - metrics.get("pelvis_z", 0.88))
        s -= 15.0 * metrics.get("effort", 0.0)
        s -= 2.0 * metrics.get("scuffs_per_s", 0.0)
        if metrics.get("fell"):
            s -= 30.0
        return s

    # ---- presentation --------------------------------------------------------

    def camera(self, m, d, cam):
        px = float(d.body("pelvis").xpos[0])
        self.cam_x = px if self.cam_x is None else self.cam_x + 0.15 * (px - self.cam_x)
        cam.lookat[:] = [self.cam_x + 0.3, 0.0, 0.85]
        cam.distance = 4.6
        cam.azimuth = 90
        cam.elevation = -6

    def hud_text(self, m, d):
        if len(self.rec) < 2:
            return ""
        t, x = self.rec[-1][0], self.rec[-1][1]
        k = max(0, len(self.rec) - 500)  # ~1 s at 2 ms steps
        t0, x0 = self.rec[k][0], self.rec[k][1]
        v = (x - x0) / max(t - t0, 1e-6)
        return f"speed {v:4.2f} m/s (1 s avg)   distance {x - self.rec[0][1]:5.1f} m"

    def title(self):
        return "robolab: run (planar muscle humanoid, SIMBICON-style chunks)"


TASK = RunTask
