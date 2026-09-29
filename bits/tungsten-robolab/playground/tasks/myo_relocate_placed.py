"""Search objective for strict relocate placements (the arena's
relocate_p2_placed): same environment, skill and metrics as myo_relocate,
scored for bringing the object in over the rim.

success_lift also counts an object lifted to the rim and then carried
through the receptacle's upper wall (its walls do not reliably collide with
the randomised objects); success_placed needs the object's centre above the
1.10 m rim where it first crosses into the receptacle's footprint. The score
puts that first, and shapes toward it with the entry height (for objects
that do enter) and the height the held object reaches.
"""

import os

from tasks.myo_relocate import MyoRelocateTask


class MyoRelocatePlacedTask(MyoRelocateTask):
    name = "myo_relocate_placed"

    def __init__(self):
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        self.controller = os.path.join(root, "bin", "robolab_myo_relocate_v3")

    def score(self, metrics):
        entry = metrics.get("entry_z", 0.0)
        over = min(1.0, max(0.0, (entry - 1.0) / 0.12)) if entry > 0.0 else 0.0
        held = min(1.0, max(0.0, (metrics.get("max_held_z", 0.9) - 0.91) / 0.25))
        return (metrics.get("success_placed", 0.0) + 0.3 * metrics.get("success_lift", 0.0)
                + 0.05 * metrics.get("success", 0.0) + 0.3 * over + 0.3 * held
                + 0.2 * super().score(metrics) / 2.2)


TASK = MyoRelocatePlacedTask
