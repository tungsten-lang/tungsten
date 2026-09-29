"""bat_v6: the bat task (tasks/bat.py, unchanged) with a power-first practice
objective, for the v6 bat-speed searches (lib/robolab/skills/bat_power.w).

Per pitch (with BAT_SEEDED_PITCH=1 a rollout is one pitch of the sweep):

    score = power + BAT6_FAIR * fair - BAT6_FLOW * max(0, bat_flow - BAT6_FLOW_CAP)

power is the arena's (sweet-spot bat speed at contact, 0 for a miss),
fair 1 for a fair ball, bat_flow the arena's per-rollout flow score (flow plus
1.0 for a miss). Defaults: BAT6_FAIR 1.5, BAT6_FLOW 8, BAT6_FLOW_CAP 2.7 (the
bat_power_clean guard is 3.0). Rollouts may stop early: everything scored is
settled by contact + 0.8 s (pass seconds ~4.4 for the seeded pitch).
"""

import os

from tasks.bat import BatTask


class BatV6Task(BatTask):
    """Seeds >= FRESH_FROM draw a held-out-style pitch (bat.py's
    BAT_FRESH_PITCH distribution; the arena's bat_power_fresh uses seeds
    1000-1023, so practise on 2000+), smaller seeds the sweep grid."""
    FRESH_FROM = 2000
    fair_w = float(os.environ.get("BAT6_FAIR", "1.5"))
    flow_w = float(os.environ.get("BAT6_FLOW", "8"))
    flow_cap = float(os.environ.get("BAT6_FLOW_CAP", "2.7"))

    def reset(self, m, d):
        if self.seed is not None and int(self.seed) >= self.FRESH_FROM:
            self.fresh_pitch = True
        return super().reset(m, d)

    def score(self, metrics):
        res = metrics.get("pitches", [])
        if not res:
            return -10.0
        total = 0.0
        for r in res:
            total += r.get("bat_speed", 0.0) if r["hit"] else 0.0
            total += self.fair_w * (1.0 if r["hit"] and r.get("fair") else 0.0)
            flow = r.get("flow")
            flow = 9.0 if flow is None else flow + (0.0 if r["hit"] else 1.0)
            total -= self.flow_w * max(0.0, flow - self.flow_cap)
        total -= 10.0 * (len(self.pitches) - len(res))
        return total / len(res)


TASK = BatV6Task
