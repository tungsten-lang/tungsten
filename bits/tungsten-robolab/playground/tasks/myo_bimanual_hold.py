"""Search objective for the myo arm's half of the bimanual handover: pick the
box, carry it into the prosthesis's reach and hold it there. Same environment
and skill as myo_bimanual; the prosthesis is kept out of the way (m_late = 1
with a long m_settle in the params). A handover needs the box held still,
within the MPL arm's reach (x >= REACH_X; it is 12 cm short at x = -0.2),
for the 1-2 s the prosthesis takes to come in and close.

  held      frames the myo hand touches the box while it is off the pillar
  held_in   of those, frames with the box at x >= REACH_X and moving
            slower than 5 cm/s
  hold_speed  mean box speed over the held frames after 2.5 s (the arm's
            oscillation about the handover point; shaping)
"""

import numpy as np

from tasks.myo_bimanual import MyoBimanualTask, episode_store

REACH_X = -0.06


class MyoBimanualHoldTask(MyoBimanualTask):
    name = "myo_bimanual_hold"

    def on_step(self, sim, obs, reward, info):
        super().on_step(sim, obs, reward, info)
        ep = episode_store(sim)
        od = sim.u.obs_dict
        p = np.array(od["obj_pos"], dtype=float)
        prev = ep.get("prev_p")
        ep["prev_p"] = p
        if od["touching_body"][0] > 0 and p[2] > 1.15:
            ep["held"] = ep.get("held", 0) + 1
            v = np.linalg.norm(p - prev) / 0.01 if prev is not None else 1.0
            if sim.d.time > 2.5:
                ep.setdefault("speeds", []).append(v)
            if p[0] >= REACH_X and v < 0.05:
                ep["held_in"] = ep.get("held_in", 0) + 1

    def metrics(self, sim, log):
        out = super().metrics(sim, log)
        ep = episode_store(sim)
        out["held"] = ep.get("held", 0)
        out["held_in"] = ep.get("held_in", 0)
        out["hold_speed"] = round(float(np.mean(ep["speeds"])), 4) if ep.get("speeds") else 1.0
        return out

    def score(self, m):
        return (min(1.0, m.get("held", 0) / 300.0) + min(1.0, m.get("held_in", 0) / 150.0)
                + 0.5 * max(0.0, 1.0 - m.get("hold_speed", 1.0) / 0.3)
                + 0.2 * min(1.0, max(0.0, m.get("max_obj_z", 1.1) - 1.12) / 0.1))


TASK = MyoBimanualHoldTask
