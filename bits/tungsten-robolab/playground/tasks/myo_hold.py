"""Bring-up: hold the reference posture on a MyoSuite body (chase-tag myoLeg)."""

from myo_bridge import MyoTask


class MyoHoldTask(MyoTask):
    name = "myo_hold"
    env_id = "myoChallengeChaseTagP1-v0"
    seconds = 4.0

    def metrics(self, sim, log):
        return {"pelvis_z": round(float(sim.d.body(sim.root).xpos[2]), 3)}

    def score(self, metrics):
        return metrics.get("time", 0.0) + metrics.get("pelvis_z", 0.0)


TASK = MyoHoldTask
