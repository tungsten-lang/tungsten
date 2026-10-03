"""Round-5 practice task (sprint_touch_v4x plus trunk-margin metrics; every score and every default reproduces sprint_touch_v4x exactly).

Agent S5 (fall-free labelled beyond-human sprinter): a fall / no-fall outcome carries one bit per rollout, so a search on a few dozen
starts cannot tell a 2 % gain in the fall rate from luck. The metrics added here measure HOW CLOSE a surviving run came to falling, from the
per-tick record the task already keeps:

  p_max    max |torso pitch| (rad) over t >= margin_t0 (default 2.5 s: after the stand / lean phase); a fall ends at 1.1 rad
  p_sd     standard deviation of the torso pitch over the same window
  p_late   max |torso pitch| over the last `margin_tail` seconds of the run (default 6 s)

The practice score is unchanged (sprint_touch_v4x's `score`); a search that wants the margin subtracts its own weight times one of these
metrics from the rollout score (scratchpad/sprint5/rses.py `--margin`). Nothing here is used by the arena.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
import numpy as np  # noqa: E402

from tasks.sprint_touch_v4x import SprintTouchV4XTask  # noqa: E402


class SprintTouchV4YTask(SprintTouchV4XTask):
    name = "sprint_touch_v4y"
    body_note = "v4 anatomy (calibrated), planar root, 1 ms physics; trunk-margin metrics p_max / p_sd / p_late added"
    margin_t0 = 2.5
    margin_tail = 6.0

    def metrics(self, m, d, log):
        out = super().metrics(m, d, log)
        if len(self.rec) > 50:
            t = np.array([r[0] for r in self.rec])
            p = np.array([r[5] for r in self.rec])
            w = t >= self.margin_t0
            if int(w.sum()) > 10:
                out["p_max"] = round(float(np.abs(p[w]).max()), 4)
                out["p_sd"] = round(float(p[w].std()), 4)
            lt = t >= t[-1] - self.margin_tail
            if int(lt.sum()) > 10:
                out["p_late"] = round(float(np.abs(p[lt]).max()), 4)
        return out

    def title(self):
        return "robolab: sprint practice, v4 anatomy (calibrated), round 5 (trunk margin)"


TASK = SprintTouchV4YTask
