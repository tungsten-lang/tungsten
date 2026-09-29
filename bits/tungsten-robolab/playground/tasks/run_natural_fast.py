"""Fast natural running (4.5-6 m/s, the long-jump approach and hurdle-race
pace): the RunNaturalSkill on the v2 anatomy, scored with run_natural's
naturalness metrics against the human reference AT THE SPEED ACTUALLY RUN.

What differs from run_natural (tasks/run_natural.py):

  reference   Reference(v) with v = the measured steady speed of the tail
              (clamped to 3.5-6.5 m/s), not the speed the skill announces, so a
              challenger cannot pick an easier reference: the swing hip and
              knee amplitudes, the arm swing and the trunk lean follow
              run_natural's human speed trends (Novacheck 1998; Hamner & Delp
              2013; Dorn et al. 2012), and the STANCE shortens with speed.
              Toe-off moves from 36 % of the cycle at 3.5 m/s to
              36 - 4.3 (v - 3.5) % (duty factor 0.375 at 3.56 m/s -> 0.30 at
              5.2 m/s in Dorn et al. 2012, J Exp Biol 215:1944: contact 0.27 ->
              0.20 s at stride frequency 1.39 -> 1.52 Hz), so the leg curves are
              time-warped piecewise linearly (stance 0-36 % of the 3.5 m/s
              curves onto 0-TO, swing onto TO-100) and the gait events move
              with them (MS at TO / 2).
  speed band  4.5-6 m/s (`in_band`, the arena guard).
  practice    run_natural's score with gait-timing windows for 4.5-6 m/s
              (human at ~5 m/s: cadence ~3.0 steps/s, step ~1.7 m, contact
              ~0.20 s, flight ~0.13 s, duty factor ~0.30; Dorn et al. 2012,
              Weyand et al. 2000, Hamner & Delp 2013).

The skill's design speed comes from its params file (`speed`, e.g. 5.0); the
ghost and the HUD use the announced speed, the metrics the measured one.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
import numpy as np  # noqa: E402

from bridge import ROOT  # noqa: E402
from tasks.run_natural import JOINTS, Reference, RunNaturalTask, naturalness  # noqa: E402

TO_REF = 36.0      # toe-off (% of cycle) of the 3.5 m/s reference curves
TO_SLOPE = 4.3     # % of cycle earlier per m/s (Dorn et al. 2012)


class FastReference(Reference):
    """run_natural's Reference at speed v with the stance shortened to
    to_pct(v) % of the cycle (piecewise-linear time warp of the leg curves)."""

    def __init__(self, speed=5.0, keyframes=None):
        super().__init__(speed, keyframes)
        self.to_pct = float(np.clip(TO_REF - TO_SLOPE * (speed - 3.5), 24.0, 40.0))

    def warp(self, p):
        """Cycle phase (%) of this speed -> phase of the 3.5 m/s curves."""
        p = np.mod(np.asarray(p, float), 100.0)
        to = self.to_pct
        return np.where(p < to, p * TO_REF / to, TO_REF + (p - to) * (100.0 - TO_REF) / (100.0 - to))

    def joint(self, name, phase):
        side, j = name[:1], name[2:]
        if j in self.leg:
            p = np.asarray(phase, float) - (0.0 if side == "r" else 50.0)
            return self.leg[j](self.warp(p))
        return super().joint(name, phase)

    def cycle_phase(self, p):
        """Inverse of warp: the measured cycle's phase of a reference phase."""
        to = self.to_pct
        return p * to / TO_REF if p < TO_REF else to + (p - TO_REF) * (100.0 - to) / (100.0 - TO_REF)

    def keyframe(self, stance, event):
        main = {"TD": 0.0, "MS": self.to_pct / 2.0, "TO": self.to_pct}
        base = main[event] if event in main and not self.kf else self.cycle_phase(self.phase_of(event))
        phase = base + (0.0 if stance == "r" else 50.0)
        out = {j: float(self.joint(j, phase)) for j in JOINTS}
        out["trunk"] = float(self.trunk(phase))
        out["pelvis"] = float(self.pelvis(phase))
        return out


def tail_speed(jrec, tail_s):
    """Mean pelvis speed over the tail window naturalness() measures."""
    if len(jrec) < 100:
        return 0.0
    t = np.array([row[0] for row in jrec], float)
    px = np.array([row[6] for row in jrec], float)
    T = t[-1]
    t0 = max(T - tail_s, T * 0.5)
    return float((px[-1] - np.interp(t0, t, px)) / max(T - t0, 1e-6))


class RunNaturalFastTask(RunNaturalTask):
    name = "run_natural_fast"
    # the skill binary is run_natural's (ROBOLAB_CONTROLLER or --controller overrides)
    controller = os.path.join(ROOT, "bin", "robolab_run_natural")
    ref_speed = 5.0
    speed_band = (4.5, 6.0)
    # human gait timing at 4.5-6 m/s (practice score windows; scalars, so a
    # search can move one with --attrs, e.g. cad_lo=3.2 for a high-cadence
    # challenger)
    cad_lo, cad_hi = 2.85, 3.3
    ct_lo, ct_hi = 0.16, 0.24
    df_lo, df_hi = 0.25, 0.36
    osc_lo, osc_hi = 0.05, 0.09
    lean_lo, lean_hi = 3.0, 14.0
    # the practice score's speed band (the arena guard is speed_band): a
    # search can demand a margin, e.g. --attrs v_lo=4.7 (practice drifts to
    # the floor of its band)
    v_lo, v_hi = 4.5, 6.0

    def reference(self):
        return FastReference(self.ref_speed, self.keyframes)

    def metrics(self, m, d, log):
        out = super().metrics(m, d, log)
        v = float(np.clip(tail_speed(self.jrec, self.tail_s), 3.5, 6.5))
        out.update(naturalness(self.jrec, FastReference(v, self.keyframes), self.tail_s))
        out["ref_speed_scored"] = round(v, 3)
        lo, hi = self.speed_band
        out["in_band"] = bool(lo <= out.get("speed", 0.0) <= hi)
        return out

    def title(self):
        return "robolab: fast natural run (human keyframes at speed, v2 anatomy)"

    def score(self, metrics):
        """run_natural's practice score (naturalness first, sustained running
        essential) with the speed band and gait-timing windows of 4.5-6 m/s."""
        if "distance" not in metrics:
            return -1e6
        T = metrics.get("time", 0.0)
        s = 2.0 * T - (40.0 if metrics.get("fell") else 0.0)
        s -= 1.0 * metrics.get("kin_rms", 60.0) + 0.5 * metrics.get("event_rms", 60.0)
        s -= 0.5 * np.mean([metrics.get("kin_" + g, 60.0) for g in ("hip", "knee", "ankle")])
        s -= 3.0 * max(0.0, metrics.get("peak_grf", 0.0) - 4.0)
        v = metrics.get("speed", 0.0)
        s -= 20.0 * max(0.0, self.v_lo - v) + 10.0 * max(0.0, v - self.v_hi)

        def outside(key, lo, hi):
            x = metrics.get(key, 0.0)
            return max(0.0, lo - x) + max(0.0, x - hi)
        s -= 20.0 * outside("cadence", self.cad_lo, self.cad_hi)
        s -= 150.0 * outside("contact_time", self.ct_lo, self.ct_hi)
        s -= 100.0 * outside("duty_factor", self.df_lo, self.df_hi)
        s -= 100.0 * outside("v_osc", self.osc_lo, self.osc_hi)
        s -= 0.5 * outside("trunk_lean", self.lean_lo, self.lean_hi)
        s -= 10.0 * metrics.get("effort", 0.0) + 1.0 * metrics.get("scuffs_per_s", 0.0)
        return s


TASK = RunNaturalFastTask


if __name__ == "__main__":
    # the same eval / render CLI as run_natural (python playground/tasks/run_natural_fast.py -h)
    import tasks.run_natural as rn
    rn.RunNaturalTask = RunNaturalFastTask
    rn.main()
