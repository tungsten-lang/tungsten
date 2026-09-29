"""Between-the-legs dribble on the fingered v2 body (tasks/dribble_btl.py with
DRIBBLE_BODY=v3), run by bin/robolab_dribble_btl (skills/dribble_btl.w)."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dribble_btl import DribbleBtlTask  # noqa: E402


class DribbleBtlV3Task(DribbleBtlTask):
    body_kind = "v3"


TASK = DribbleBtlV3Task
