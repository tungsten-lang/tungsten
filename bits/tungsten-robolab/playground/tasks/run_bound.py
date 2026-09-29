"""Run, bounding variant: the RunSkill stride as two mirrored bounds.

Same body, scene, metrics and controller binary (bin/robolab_run) as the
run task; `gait 1` in the params file (params/run_bound.txt) switches
RunSkill to alternating bounds (l_drive, l_fly, r_drive, r_fly: four chunk
decisions per stride). The score asks for a bounding character: cadence at
or below `cadence_cap`, flights up to `flight_goal` long, and an active knee
drive (per-stride peak swing-thigh angle up to `thigh_goal`).

    .venv/bin/python playground/bridge.py run_bound --params params/run_bound.txt \\
        --video out/run_bound.mp4 --sheet out/run_bound_sheet.png
"""

import os

from tasks.run import RunTask

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class RunBoundTask(RunTask):
    name = "run_bound"
    controller = os.path.join(ROOT, "bin", "robolab_run")
    cadence_cap = 3.0
    cadence_weight = 40.0
    thigh_goal = 1.0
    thigh_weight = 30.0
    flight_goal = 0.14
    flight_weight = 150.0

    def title(self):
        return "robolab: run, alternating bounds (planar muscle humanoid)"


TASK = RunBoundTask
