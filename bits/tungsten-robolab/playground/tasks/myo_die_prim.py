"""Primitive search for myo_die_v3: make primitive `force` = k turn the die
90 degrees about its nominal palm axis, and nothing else.

Same environment and skill as myo_die, cut to 0.9 s, with the skill forced
to run primitive k once after the cup (`force` must be in the params). The
score is the die's rotation over the primitive's chunk (palm frame, as
myo_die_calibrate.py measures it) projected on the nominal axis, capped at
pi/2, minus half the off-axis rotation, minus the die's drift beyond 2 cm
from where it started, minus a drop.
"""

import os

import numpy as np

from tasks.myo_die import MyoDieTask, cache, episode_store
from tasks.myo_die_calibrate import PRIMS, rotvec

AXES = {"xp": (0, 1), "xn": (0, -1), "yp": (1, 1), "yn": (1, -1), "zp": (2, 1), "zn": (2, -1)}


class MyoDiePrimTask(MyoDieTask):
    name = "myo_die_prim"
    env_kwargs = {"max_episode_steps": 90}

    def __init__(self):
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        self.controller = os.path.join(root, "bin", "robolab_myo_die_v3")

    def on_step(self, sim, obs, reward, info):
        super().on_step(sim, obs, reward, info)
        c = cache(sim)
        P = sim.d.xmat[c.frame].reshape(3, 3)
        Ro = sim.d.site_xmat[c.obj_sid].reshape(3, 3)
        ep = episode_store(sim)
        ep.setdefault("A", []).append(P.T @ Ro)
        ep.setdefault("lab", []).append(sim.label)
        ep.setdefault("pos", []).append(np.array(sim.u.obs_dict["obj_pos"], dtype=float))

    def metrics(self, sim, log):
        out = super().metrics(sim, log)
        out["held"] = float(len(sim.infos) >= self.env_kwargs["max_episode_steps"])
        ep = episode_store(sim)
        k = int(round(sim.params.get("force", -1)))
        name = PRIMS[k] if 0 <= k < len(PRIMS) else ""
        idx = [i for i, lab in enumerate(ep.get("lab", [])) if name and name in lab]
        if not idx:
            out.update({"prim_on": 0.0, "prim_off": 0.0, "prim_drift": 0.0})
            return out
        A = ep["A"]
        i0 = max(0, idx[0] - 1)
        w = rotvec(A[idx[-1]] @ A[i0].T)
        ax, sg = AXES[name.split("_")[1]]
        on = sg * w[ax]
        off = float(np.linalg.norm(np.delete(w, ax)))
        drift = float(np.linalg.norm(ep["pos"][idx[-1]] - ep["pos"][i0]))
        out.update({"prim_on": round(float(on), 4), "prim_off": round(off, 4), "prim_drift": round(drift, 4)})
        return out

    def score(self, metrics):
        on = min(metrics.get("prim_on", 0.0), np.pi / 2)
        return (on - 0.5 * metrics.get("prim_off", 0.0) - 10.0 * max(0.0, metrics.get("prim_drift", 0.0) - 0.02)
                - 1.0 * (1.0 - metrics.get("held", 0.0)))


TASK = MyoDiePrimTask
