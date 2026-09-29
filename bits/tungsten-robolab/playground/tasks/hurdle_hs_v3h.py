"""High-school 110 m hurdles on the v3 anatomy with 3D hips: the hips' abduction
and rotation joints are free under the planar root (as ROBOLAB_HURDLE_HIP3D=1,
but fixed in the task so an arena trial reproduces it without the env), so the
trail leg can come around the side of the bar. See tasks/hurdle_hs.py."""

from tasks.hurdle_hs import HurdleHSV3Task


class HurdleHSV3HipTask(HurdleHSV3Task):
    name = "hurdle_hs_v3h"

    def __init__(self):
        super().__init__()
        self.hip3d = True


TASK = HurdleHSV3HipTask
