"""Search benchmark P4: consecutive standing broad jumps (a bounding gait).

The P1 jump skill with `loop` 1 (a task-level fixed param): after each
landing (held land_hold s) it crouches, extends, flies and lands again, the
same chunk goals every cycle, for 6 s. Controller: bin/frozen/robolab_search_jump_v2.

Metrics (besides the jump's): t_fall (first floor contact by anything but a
foot, the COM below 0.5 m, or the head below the pelvis: an inverted body
that slides along on its feet is a fall, not a gait; the horizon if never), hops (airborne phases
of >= 60 ms before t_fall), distance (COM forward travel up to t_fall, m).
Score: distance, minus 1 for a fall. `seed` perturbs the start as in P1.
"""

import numpy as np

from tasks.search_jump_v2 import SearchJumpV2Task


class SearchHopsTask(SearchJumpV2Task):
    name = "search_hops"
    seconds = 6.0
    fixed_params = {"loop": 1}

    def reset(self, m, d):
        super().reset(m, d)
        self.head = m.geom("head").id
        self.inverted = None

    def before_step(self, m, d):
        super().before_step(m, d)
        if self.inverted is None and d.geom_xpos[self.head][2] < d.xpos[self.pelvis][2]:
            self.inverted = float(d.time)

    def metrics(self, m, d, log):
        out = super().metrics(m, d, log)
        if len(self.rec) < 10:
            out.update(t_fall=0.0, hops=0, distance=0.0)
            return out
        r = np.array([(t, float(f), x, z) for t, f, x, z, _, _ in self.rec])
        t = r[:, 0]
        t_fall = float(t[-1])
        bad = [tt for tt, _, is_foot in self.touches if not is_foot]
        if bad:
            t_fall = min(t_fall, bad[0])
        low = np.nonzero(r[:, 3] < 0.5)[0]
        if len(low):
            t_fall = min(t_fall, float(t[low[0]]))
        if self.inverted is not None:
            t_fall = min(t_fall, self.inverted)
        upto = t <= t_fall
        on = r[upto, 1] > 0.5
        hops, k = 0, 0
        while k < len(on):
            if not on[k] and t[k] > 0.4:
                j = k
                while j < len(on) and not on[j]:
                    j += 1
                if t[min(j, len(on) - 1)] - t[k] >= 0.06:
                    hops += 1
                k = j
            k += 1
        out["t_fall"] = round(t_fall, 3)
        out["hops"] = hops
        out["distance"] = round(float(np.interp(t_fall, t, r[:, 2]) - self.com0[0]), 3)
        out["fallen"] = t_fall < float(t[-1]) - 1e-9
        return out

    def score(self, metrics):
        if "error" in metrics or "distance" not in metrics:
            return -1e9
        return metrics["distance"] - (1.0 if metrics.get("fallen") else 0.0)

    def title(self):
        return "robolab: consecutive broad jumps (search benchmark P4)"


TASK = SearchHopsTask
