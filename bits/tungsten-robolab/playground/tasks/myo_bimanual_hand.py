"""Search objective for the bimanual handover itself: myo_bimanual's
environment, skill, metrics and staged score, plus a term for a genuine
handover: frames in which the prosthesis alone holds the box off the
pillars (touching it while the myo hand does not, box above 1.0 m). The
staged score's prosthesis-contact stage also pays for a prosthesis hand
pressed against the box from below while the myo hand still holds it; this
one only pays once the box has changed hands.
"""

from tasks.myo_bimanual import MyoBimanualTask, episode_store


class MyoBimanualHandTask(MyoBimanualTask):
    name = "myo_bimanual_hand"

    def on_step(self, sim, obs, reward, info):
        super().on_step(sim, obs, reward, info)
        tb = sim.u.obs_dict["touching_body"]
        if tb[1] > 0 and tb[0] == 0 and float(sim.u.obs_dict["obj_pos"][2]) > 1.0:
            ep = episode_store(sim)
            ep["pros_only"] = ep.get("pros_only", 0) + 1

    def metrics(self, sim, log):
        out = super().metrics(sim, log)
        out["pros_only"] = episode_store(sim).get("pros_only", 0)
        return out

    def score(self, m):
        return super().score(m) + 0.5 * min(1.0, m.get("pros_only", 0) / 50.0)


TASK = MyoBimanualHandTask
