"""bat_rep: the bat task on fresh continuous pitches, with aim diagnostics and a practice objective
(batting round 2, agent B, 29 Sep 2026).

A BatTask (tasks/bat.py, unchanged; athlete body) whose EVERY seed draws one fresh pitch from bat.py's FRESH_*
distribution (speed 34-40.5 m/s, crossing x -0.15..0.15 m, height 0.62-1.00 m, uniform; `FRESH_SALT + seed`, the draw
the arena's bat_power_fresh* trials use for their seeds), so a search can practise on seeds >= 3000 and a validation
set on 4000+, none of which is an arena seed (arena: 1000-1023, 1100-1123). `task.pitches` may be set to one explicit
(speed, x, z) instead (a pitch scan); BATREP_GRID=1 selects the arena's 18-pitch grid (seed mod 18, the bat_power trials' pitches). Nothing here touches the physics, the controller or the arena tasks.

Per-pitch diagnostics added to each pitch's record (read-only, computed from the state at the ball's closest
approach to the bat: a miss's closest approach, a hit's contact):

  aim_v_ms   the ball's lead over the bat along the sweet spot's velocity, in ms of the bat's own speed (+ = the ball is
             ahead of where the bat is: the bat is LATE; - = early)
  aim_n_cm   the ball's offset perpendicular to the swing plane (spanned by the bat axis and the sweet spot's velocity),
             in cm (+ = above the plane if the plane is level: it is the plane normal with a positive z component)
  aim_dz_cm  the ball's height minus the sweet spot's, cm (at the closest approach)
  aim_s      the closest point's distance along the bat from the knob (m; the barrel is 0.5-0.86)
  gap_cm     the closest approach's surface gap (`closest`), cm

score(): the practice objective, per pitch
    hit:   bat speed at contact + BATREP_FAIR * fair - BATREP_AIM * max(0, |aim_n| - BATREP_AIM_CAP)   [an aim margin]
           - BATREP_S_W * (metres of the contact beyond [BATREP_S_LO, BATREP_S_HI] along the bat)      [a timing margin]
    miss:  -BATREP_MISS - 100 * closest (m)      [smooth in the gap, so a search can see near-misses]
    - BATREP_FLOW * max(0, flow - BATREP_FLOW_CAP)   [bat_flow; a miss adds 1.0 as the arena's guard does]
Defaults BATREP_FAIR 0, BATREP_AIM 0.5 per cm beyond BATREP_AIM_CAP 3.0 cm (a hit is |aim_n| < ~7 cm), BATREP_MISS 5,
BATREP_FLOW 8, BATREP_FLOW_CAP 2.7 (the arena's bat_power_clean guard is 3.0).
Rollouts may stop early: everything scored is settled by contact + 0.8 s (pass seconds ~4.6).
"""

import os

import numpy as np

os.environ.setdefault("BAT_BODY", "athlete")

from tasks.bat import BatTask  # noqa: E402


class BatRepTask(BatTask):
    fresh_pitch = True
    fair_w = float(os.environ.get("BATREP_FAIR", "0"))
    miss_w = float(os.environ.get("BATREP_MISS", "5"))
    aim_w = float(os.environ.get("BATREP_AIM", "0.5"))
    aim_cap = float(os.environ.get("BATREP_AIM_CAP", "3.0"))
    # contact position along the bat (aim_s, m from the knob; the barrel is 0.5-0.86, the sweet spot 0.71): a hit near either end is
    # a near-miss of the swing's TIMING (aim_n only sees the offset from the swing plane); penalty BATREP_S_W per m beyond [S_LO, S_HI]
    s_lo = float(os.environ.get("BATREP_S_LO", "0.50"))
    s_hi = float(os.environ.get("BATREP_S_HI", "0.80"))
    s_w = float(os.environ.get("BATREP_S_W", "8"))
    # ball quality: a hit launched more than BATREP_LAUNCH_CAP degrees from 20 deg costs BATREP_LAUNCH per degree (0 = off; the
    # arena's bat_quality scores a fair ball at 20 deg as 1, falling to 0 at 20 +- 30 deg; 0.033 m/s per degree = 1 m/s per quality point)
    launch_w = float(os.environ.get("BATREP_LAUNCH", "0"))
    launch_cap = float(os.environ.get("BATREP_LAUNCH_CAP", "10"))
    flow_w = float(os.environ.get("BATREP_FLOW", "8"))
    flow_cap = float(os.environ.get("BATREP_FLOW_CAP", "2.7"))

    def reset(self, m, d):
        self.fresh_pitch = True
        if os.environ.get("BATREP_GRID") == "1":     # the arena's 18-pitch grid instead (seed mod 18; bat_power's pitches)
            self.fresh_pitch = False
            self.seeded_pitch = True
        explicit = getattr(self, "explicit_pitch", None)
        keep = list(self.pitches)
        super().reset(m, d)
        if explicit is not None:
            self.pitches = [tuple(explicit)]
        elif self.seed is None:
            self.pitches = keep

    def track(self, m, d):
        cur = self.cur
        super().track(m, d)
        # the closest-approach record is rewritten on the substeps where the gap shrinks
        if cur is not None and not cur.get("hit") and cur.get("t_closest") == d.time:
            self.aim_record(m, d, cur)
        elif cur is not None and cur.get("hit") and "aim_v_ms" not in cur and cur.get("t_contact") is not None:
            self.aim_record(m, d, cur)

    def aim_record(self, m, d, cur):
        bp = d.qpos[self.ball_q:self.ball_q + 3]
        sweet = d.site_xpos[self.site["bat_sweet"]]
        knob = d.site_xpos[self.site["bat_knob"]]
        tip = d.site_xpos[self.site["bat_tip"]]
        sv = self.site_vel(m, d, self.site["bat_sweet"])
        axis = tip - knob
        axis = axis / np.linalg.norm(axis)
        rel = bp - sweet
        s = float(np.dot(bp - knob, axis))
        perp = (bp - knob) - s * axis                       # bat axis -> ball, perpendicular to the axis
        sp = float(np.linalg.norm(sv))
        if sp > 1e-6:
            ev = sv / sp
            evp = ev - np.dot(ev, axis) * axis
            nv = np.linalg.norm(evp)
            evp = evp / nv if nv > 1e-9 else ev
            nrm = np.cross(axis, evp)
            nrm = nrm if nrm[2] >= 0 else -nrm
            cur["aim_v_ms"] = round(1000.0 * float(np.dot(perp, evp)) / sp, 2)
            cur["aim_n_cm"] = round(100.0 * float(np.dot(perp, nrm)), 2)
        cur["aim_dz_cm"] = round(100.0 * float(rel[2]), 2)
        cur["aim_s"] = round(s, 3)
        cur["gap_cm"] = round(100.0 * float(cur.get("closest", 0.0)), 2)

    def score(self, metrics):
        res = metrics.get("pitches", [])
        if not res:
            return -20.0
        total = 0.0
        for r in res:
            if r["hit"]:
                total += r.get("bat_speed", 0.0) + self.fair_w * (1.0 if r.get("fair") else 0.0)
                total -= self.aim_w * max(0.0, abs(r.get("aim_n_cm", 0.0)) - self.aim_cap)
                if self.launch_w:
                    total -= self.launch_w * max(0.0, abs(r.get("launch_deg", 20.0) - 20.0) - self.launch_cap)
                sb = r.get("aim_s", 0.7)
                total -= self.s_w * (max(0.0, sb - self.s_hi) + max(0.0, self.s_lo - sb))
            else:
                total -= self.miss_w + 100.0 * max(0.0, r.get("closest", 0.5))
            flow = r.get("flow")
            flow = 9.0 if flow is None else flow + (0.0 if r["hit"] else 1.0)
            total -= self.flow_w * max(0.0, flow - self.flow_cap)
        total -= 20.0 * (len(self.pitches) - len(res))
        return total / len(res)


TASK = BatRepTask
