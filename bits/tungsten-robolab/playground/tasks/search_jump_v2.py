"""Search benchmark P1 on the v2 jump controller (bin/frozen/robolab_search_jump_v2).

Identical task, scene and score as tasks/search_jump.py; the controller build
adds the keyframe representations (rep 4: a per-muscle contraction vector
and a duration per chunk; rep 5: a contraction vector and a speed) and the
`loop` gait mode. Representations 0-3 behave exactly as on the first build
(checked by replaying stored runs).
"""

import os

from tasks.search_jump import SearchJumpTask


class SearchJumpV2Task(SearchJumpTask):
    name = "search_jump_v2"
    controller = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "bin",
                              "frozen", "robolab_search_jump_v2")


TASK = SearchJumpV2Task
