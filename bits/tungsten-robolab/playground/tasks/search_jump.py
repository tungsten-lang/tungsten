"""Search benchmark P1: a standing broad jump (planar muscle humanoid).

Skill: lib/robolab/skills/search_jump.w (crouch, extend with a drive, flight,
land). The body is the shared planar humanoid at normal strength (no
strength or muscle-speed scaling). The jump is measured the athletics way:
from the take-off line (the toes at the start) to the nearest floor contact
made by any part of the body after landing, so sitting back or putting a
hand down behind the heels shortens the mark.

Metrics:
    mark          jump distance (m), take-off line to the nearest landing break
    takeoff       whether both feet left the floor for >= 60 ms
    flight_time   first airborne interval (s)
    com_peak      peak COM height gain over standing (m)
    takeoff_vx/vz COM velocity when the last foot left the floor (m/s)
    fallen        a non-foot body part touched the floor, or the pelvis ended
                  below 0.5 m (bridge.Sim overwrites `fell` with its own done flag)
    effort        mean squared activation
    toe_advance   how far the leading toe got past the take-off line before
                  the take-off (m); a foot stepping forward during the crouch
                  gains mark without jumping further
    foul          toe_advance above foul_advance (0.03 m; a foot sliding or
                  rolling in place stays under 0.02 m)
    inverted      the head ended below the pelvis (a jack-knifed body resting
                  on its feet, head down, which `fallen` does not see)

Score: the mark for a clean jump (landed and stayed on the feet). A fall
scores -0.5 + 0.25 x max(0, mark), so every clean landing beats every fall
(a dive that lands on the hands would otherwise measure far) while longer
falls still rank above shorter ones; without a take-off, -1 plus 0.5 x the
COM rise (so a non-jumping candidate still has a slope toward jumping).

`strict` (a task attribute, or ROBOLAB_SJ_STRICT=1; off by default, so every
stored score is unchanged) scores a foul or an inverted ending as a fall. The
arena reads the metrics, not the score: a trial enforces the same rule with
the guard {"foul": false, "inverted": false}.

`seed` (practice robustness / held-out evaluation) perturbs the standing
start: leg and spine joints N(0, noise = 0.04) rad and the pelvis pitch
N(0, pitch_noise = 0.02) rad, set at reset before the controller starts. None or 0 (the default) is the
exact standing pose.
"""

import math
import os

import mujoco
import numpy as np

from bridge import Task


class SearchJumpTask(Task):
    name = "search_jump"
    # a frozen build (./build.sh <skill> then copy to bin/frozen/), so a rebuild of every
    # skill mid-benchmark cannot swap the controller under a running comparison
    controller = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "bin", "frozen", "robolab_search_jump")
    mode = "planar"
    seconds = 3.0
    control_dt = 0.004  # 2 physics steps of 2 ms per tick, and the controller is told so
    seed = None
    # perturbed start: joint noise sd and pelvis pitch noise sd (rad);
    # ROBOLAB_SJ_NOISE / ROBOLAB_SJ_PITCH_NOISE override them (arena trials)
    noise = float(os.environ.get("ROBOLAB_SJ_NOISE", "0.04"))
    pitch_noise = float(os.environ.get("ROBOLAB_SJ_PITCH_NOISE", "0.02"))
    strict = os.environ.get("ROBOLAB_SJ_STRICT", "0") == "1"
    foul_advance = 0.03

    def reset(self, m, d):
        if self.seed:  # None or 0: the exact standing pose
            rng = np.random.default_rng(self.seed)
            for j in ("l_hip_flex", "r_hip_flex", "l_knee", "r_knee", "l_ankle", "r_ankle", "spine_flex"):
                a = m.joint(j).qposadr[0]
                lo, hi = m.jnt_range[m.joint(j).id]
                d.qpos[a] = float(np.clip(d.qpos[a] + rng.normal(0.0, self.noise), lo, hi))
            d.qpos[m.joint("root_pitch").qposadr[0]] += rng.normal(0.0, self.pitch_noise)
        mujoco.mj_forward(m, d)
        self.floor = m.geom("floor").id
        self.feet = {m.geom("l_foot").id, m.geom("r_foot").id}
        self.pelvis = m.body("pelvis").id
        self.start_x = float(max(d.site("l_toe").xpos[0], d.site("r_toe").xpos[0]))
        self.com0 = d.subtree_com[self.pelvis].copy()
        self.rec = []      # (t, any foot on floor, com x, com z, com vx, com vz)
        self.touches = []  # (t, x of contact, is foot)
        self.force = np.zeros(6)
        self.toes = []     # (t, leading toe x)
        self.head = m.geom("head").id

    def before_step(self, m, d):
        foot = False
        for i in range(d.ncon):
            con = d.contact[i]
            if con.geom1 != self.floor and con.geom2 != self.floor:
                continue
            other = con.geom2 if con.geom1 == self.floor else con.geom1
            is_foot = other in self.feet
            foot = foot or is_foot
            self.touches.append((d.time, float(con.pos[0]), is_foot))
        com = d.subtree_com[self.pelvis]
        v = d.subtree_linvel[self.pelvis]
        self.rec.append((d.time, foot, float(com[0]), float(com[2]), float(v[0]), float(v[2])))
        self.toes.append((d.time, float(max(d.site("l_toe").xpos[0], d.site("r_toe").xpos[0]))))

    def done(self, m, d):
        return False

    def metrics(self, m, d, log):
        out = {"time": round(d.time, 3)}
        if len(self.rec) < 10:
            out.update(mark=0.0, takeoff=False)
            return out
        r = np.array([(t, float(f), x, z, vx, vz) for t, f, x, z, vx, vz in self.rec])
        t, on = r[:, 0], r[:, 1] > 0.5
        # take-off: the first run of >= 60 ms with no foot on the floor (after the set)
        t_off = t_land = None
        k = 0
        while k < len(t):
            if not on[k] and t[k] > 0.4:
                j = k
                while j < len(t) and not on[j]:
                    j += 1
                if j >= len(t) or t[j] - t[k] >= 0.06:
                    t_off = t[k]
                    t_land = t[j] if j < len(t) else None
                    kv = max(k - 1, 0)
                    out["takeoff_vx"] = round(float(r[kv, 4]), 3)
                    out["takeoff_vz"] = round(float(r[kv, 5]), 3)
                    break
                k = j
            k += 1
        out["takeoff"] = t_off is not None
        out["flight_time"] = round(float((t_land if t_land is not None else t[-1]) - t_off), 3) if t_off is not None else 0.0
        out["com_peak"] = round(float(np.max(r[:, 3]) - self.com0[2]), 3)
        out["com_dx"] = round(float(r[-1, 2] - self.com0[0]), 3)
        if t_land is not None:
            xs = [x for tt, x, _ in self.touches if tt >= t_land]
            out["mark"] = round(float(min(xs) - self.start_x), 3) if xs else 0.0
        else:
            out["mark"] = 0.0
        out["fallen"] = any(not f for _, _, f in self.touches) or float(d.body("pelvis").xpos[2]) < 0.5
        before = [x for tt, x in self.toes if t_off is None or tt < t_off]
        out["toe_advance"] = round(float(max(before) - self.start_x), 3) if before else 0.0
        out["foul"] = out["toe_advance"] > self.foul_advance
        out["inverted"] = float(d.geom_xpos[self.head][2]) < float(d.body("pelvis").xpos[2])
        acts = np.array([row[2] for row in log]) if log else np.zeros((1, 1))
        out["effort"] = round(float(np.mean(acts ** 2)), 4)
        return out

    def score(self, metrics):
        if "error" in metrics:
            return -1e9
        if not metrics.get("takeoff"):
            return -1.0 + 0.5 * max(0.0, metrics.get("com_peak", 0.0))
        s = metrics.get("mark", 0.0)
        if metrics.get("fallen") or (self.strict and (metrics.get("foul") or metrics.get("inverted"))):
            return -0.5 + 0.25 * max(0.0, s)
        return s

    def camera(self, m, d, cam):
        p = d.body("pelvis").xpos
        cam.lookat[:] = [p[0] + 0.3, 0.0, 0.8]
        cam.distance = 4.0
        cam.azimuth = 90
        cam.elevation = -6

    def title(self):
        return "robolab: standing broad jump (search benchmark P1)"


TASK = SearchJumpTask
