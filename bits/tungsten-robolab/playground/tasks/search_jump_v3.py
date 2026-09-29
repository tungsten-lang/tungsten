"""Search benchmark P1 on the v3 jump controller (bin/frozen/robolab_search_jump_v3).

Identical task, scene and score as tasks/search_jump.py; the controller build
adds opt-in feedback, params-file switches that are all off by default
(lib/robolab/skills/search_jump.w): fb_push (push-off latched on the COM's
depth), fb_takeoff (the flight starts when the COM has risen above to_z, not
only when the last toe leaves the floor), fb_touch (the landing latch needs
the COM low and falling), fb_flight (trunk-pitch and take-off-speed
correction in flight), fb_land (capture-point landing correction with
co-contraction) and fb_stand (rise to a balanced crouch after landing).
Without them it replays the v1 / v2 builds' stored runs exactly (P5 in
SEARCH.md).
"""

import os

from tasks.search_jump import SearchJumpTask


class SearchJumpV3Task(SearchJumpTask):
    name = "search_jump_v3"
    controller = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "bin",
                              "frozen", "robolab_search_jump_v3")


TASK = SearchJumpV3Task
