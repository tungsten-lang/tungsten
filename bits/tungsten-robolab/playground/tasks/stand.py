"""Stand: bring-up task on the planar body (squat and reach loop)."""

from bridge import Task


class StandTask(Task):
    name = "stand"
    mode = "planar"
    seconds = 8.0

    def title(self):
        return "robolab: stand / squat / reach (planar muscle humanoid)"


TASK = StandTask
