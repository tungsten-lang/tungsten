"""Dribble v3: the dribble task on the human-calibrated v2 body with fingered
hands, run by bin/robolab_dribble_v3 (skills/dribble_v3.w: arms-only,
elbow-driven strokes, V crossovers). Same scene, sensors and metrics as
tasks/dribble.py (see its docstring); only the body, the home spot and the
camera differ."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dribble import DribbleTask  # noqa: E402


class DribbleV3Task(DribbleTask):
    body_kind = "v3"


TASK = DribbleV3Task
