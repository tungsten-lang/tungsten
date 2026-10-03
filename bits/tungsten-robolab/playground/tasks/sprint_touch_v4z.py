"""Round-5 STRESS-TEST practice task (sprint_touch_v4y plus a seeded trunk kick; with kick = 0 it is sprint_touch_v4y exactly).

Agent S5: the natural falls of the labelled beyond-human sprinter are rare (0.3-0.8 % per second of running), so a search that counts them
needs hundreds of rollouts to see a 30 % change. This task makes them common: once per rollout, at a time drawn from [kick_t0, kick_t1]
(seconds after the start of the rollout; the seed fixes the draw), the PELVIS PITCH RATE gets an impulse of `kick` rad/s with a seeded sign
(kick_sign = +1 forward only, -1 backward only, 0 either) and the rollout is judged by whether the runner is still up `kick_win` seconds later.
It is a push-recovery stress test, not an arena condition: nothing in the arena uses it. The kick is applied to the simulation state
(root_pitch velocity), in the planar root of the body; the run's own fall rule decides the outcome.

  kick       impulse (rad/s of pelvis pitch rate), 0 = off
  kick_t0/t1 window for the kick time (s)
  kick_sign  +1 forward (pitching the trunk forward), -1 backward, 0 either (seeded)
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
import numpy as np  # noqa: E402

from tasks.sprint_touch_v4y import SprintTouchV4YTask  # noqa: E402


class SprintTouchV4ZTask(SprintTouchV4YTask):
    name = "sprint_touch_v4z"
    body_note = "v4 anatomy (calibrated), planar root, 1 ms physics; trunk-margin metrics and a seeded pelvis-pitch-rate kick (stress test)"
    kick = 0.0
    kick_t0 = 1.0
    kick_t1 = 3.0
    kick_sign = 0.0

    def reset(self, m, d):
        super().reset(m, d)
        self._kick_done = self.kick == 0.0
        rng = np.random.default_rng(10007 + (0 if self.seed is None else int(self.seed)))
        self._kick_time = float(rng.uniform(self.kick_t0, self.kick_t1))
        s = float(self.kick_sign)
        self._kick_dir = s if s != 0.0 else (1.0 if rng.random() < 0.5 else -1.0)
        self._kick_dof = int(m.joint("root_pitch").dofadr[0])

    def before_step(self, m, d):
        super().before_step(m, d)
        if not self._kick_done and d.time >= self._kick_time:
            d.qvel[self._kick_dof] += self.kick * self._kick_dir
            self._kick_done = True

    def title(self):
        return "robolab: sprint practice, v4 anatomy (calibrated), round 5 (trunk kick stress test)"


TASK = SprintTouchV4ZTask
