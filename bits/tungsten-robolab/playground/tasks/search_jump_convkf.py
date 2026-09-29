"""Search benchmark P6 on the convolutional-keyframe jump controller
(bin/frozen/robolab_search_jump_convkf).

Identical task, scene and score as tasks/search_jump.py; the controller build
adds two opt-in params-file switches to the v3 jump (lib/robolab/skills/
search_jump.w): `kf_knots` (quintic Hermite keyframes: an end velocity and
acceleration per muscle at the crouch, extend and flight keyframes) and `tcn`
(a residual causal TCN on proprioception, lib/robolab/tcn.w). Without them,
and with zero knots and a zero last TCN layer, it replays the arena's jump
champions exactly (P6 in SEARCH.md; playground/convkf.py).
"""

import os

from tasks.search_jump import SearchJumpTask


class SearchJumpConvKFTask(SearchJumpTask):
    name = "search_jump_convkf"
    controller = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "bin",
                              "frozen", "robolab_search_jump_convkf")


TASK = SearchJumpConvKFTask
