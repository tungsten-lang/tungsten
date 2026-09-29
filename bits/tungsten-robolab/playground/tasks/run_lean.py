"""Run, forward-lean variant: the RunSkill gait as a "caught fall".

Same body, scene, metrics and controller binary (bin/robolab_run) as the
run task; the practised params (params/run_lean.txt) switch on RunSkill's
fall_lean / fall_ankle / knee_lift / heel_tuck terms. The score asks for the
variant's shape: mean torso lean inside `lean_band` (whole body tilted
forward, the centre of mass carried ahead of the stance foot) and high knees
(per-stride peak swing-thigh angle up to `thigh_goal`, near horizontal).

    .venv/bin/python playground/bridge.py run_lean --params params/run_lean.txt \\
        --video out/run_lean.mp4 --sheet out/run_lean_sheet.png
"""

import os

from tasks.run import RunTask

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class RunLeanTask(RunTask):
    name = "run_lean"
    controller = os.path.join(ROOT, "bin", "robolab_run")
    lean_band = (0.2, 0.38)
    lean_weight = 100.0
    thigh_goal = 1.2
    thigh_weight = 40.0

    def title(self):
        return "robolab: run, forward-lean variant (planar muscle humanoid)"


TASK = RunLeanTask
