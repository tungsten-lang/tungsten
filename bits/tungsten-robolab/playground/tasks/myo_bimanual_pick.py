"""Stage 1 of myo_bimanual, for search: the myoArm's pick and carry.

Same environment and controller as myo_bimanual, cut to 3.5 s (enough to
pick the box, lift it and hold it at the handover point). Scores the myo
hand's contact frames, the height the box reaches while the myo hand holds
it, and how close the held box ends to the handover point.
"""

import os

import numpy as np

from tasks.myo_bimanual import MyoBimanualTask, episode_store


class MyoBimanualPickTask(MyoBimanualTask):
    name = "myo_bimanual_pick"
    env_kwargs = {"max_episode_steps": 350}

    def __init__(self):
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        self.controller = os.path.join(root, "bin", "robolab_myo_bimanual")

    def metrics(self, sim, log):
        out = super().metrics(sim, log)
        ep = episode_store(sim)
        held = ep.get("held_pos", [])
        hx = sim.params.get("hx", -0.12)
        hy = sim.params.get("hy", -0.32)
        hz = sim.params.get("hz", 1.28)
        if held:
            last = held[-1]
            out["hand_dist"] = round(float(np.linalg.norm(last - np.array([hx, hy, hz - 0.06]))), 4)
        else:
            out["hand_dist"] = 1.0
        return out

    def score(self, metrics):
        s = 0.3 * min(1.0, metrics.get("myo_frames", 0) / 100.0)
        s += 0.5 * min(1.0, max(0.0, metrics.get("held_z", 1.1) - 1.12) / 0.12)
        s += 0.5 * max(0.0, 1.0 - metrics.get("hand_dist", 1.0) / 0.3)
        s -= 0.2 * min(1.0, metrics.get("env_frames", 0) / 10.0)
        return s


TASK = MyoBimanualPickTask
