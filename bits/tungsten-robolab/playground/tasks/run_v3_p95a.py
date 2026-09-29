"""run_v3 on the full 95th-percentile body: run_v3_p95 plus the profile's
anthropometry (profiles/p95.json `anthro`: stature and every segment length
x1.066, mass x1.136 at constant BMI; joint torques and tendon stiffnesses
scale with the mass, so strength per kg is the strength part's alone).
Practised distances (COM-foot leads, clearances) were tuned on the average
skeleton, so params need re-practice here more than on run_v3_p95."""

from tasks.run_v3_p95 import RunV3P95Task


class RunV3P95ATask(RunV3P95Task):
    name = "run_v3_p95a"
    profile_parts = "all"

    def title(self):
        return "robolab: run, v3 anatomy, 95th-percentile muscles, tendons and anthropometry"


TASK = RunV3P95ATask
