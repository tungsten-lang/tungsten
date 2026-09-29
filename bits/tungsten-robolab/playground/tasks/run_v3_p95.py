"""run_v3 on the 95th-percentile body (body_profile.py, profiles/p95.json):
the v3 anatomy with P95 muscle strength per kg, P95 muscle shortening speed,
P95 tendon stiffness and the activation part of the profile, on the average
skeleton (1.75 m, 67.5 kg: the anthropometry part is `run_v3_p95a`).

Same RunSkill binary, scene, metrics, score, 1 ms physics and reset as run_v3;
ROBOLAB_V3_TENDON_SCALE and ROBOLAB_V3_RIGID work as there. ROBOLAB_PROFILE /
ROBOLAB_PROFILE_PARTS are ignored here (the task names its profile); to
ablate one part use run_v3 with ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=<part>.
"""

from body import HumanoidV2Builder, HumanoidV3Builder
from tasks.run_v3 import RIGID, TENDON_SCALE, RunV3Task


class RunV3P95Task(RunV3Task):
    name = "run_v3_p95"
    profile = "p95"
    profile_parts = "strength,speed,tendon,activation"

    def builder(self):
        kw = dict(strength=self.strength, wrists=self.wrists, profile=self.profile, profile_parts=self.profile_parts)
        if RIGID:
            return HumanoidV2Builder(self.mode, **kw)
        return HumanoidV3Builder(self.mode, stiffness_scale=TENDON_SCALE, **kw)

    def title(self):
        return "robolab: run, v3 anatomy, 95th-percentile muscles and tendons"


TASK = RunV3P95Task
