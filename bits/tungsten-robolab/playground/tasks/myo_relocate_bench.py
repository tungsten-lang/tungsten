"""Reaching benchmark for the myo_relocate arm servo (param `bench`).

The skill tours fixed palm targets over the relocate workspace (see
MyoRelocateSkill#bench_movement) without handling the object and emits its
eased target each tick; this task scores how closely the palm follows:
mean tracking error, and the error at the end of each segment (settled).
Used to tune the servo and reflex gains by search on a cheap deterministic
objective before tuning the grasp.
"""

import numpy as np

from tasks.myo_relocate import MyoRelocateTask


class MyoRelocateBenchTask(MyoRelocateTask):
    name = "myo_relocate_bench"
    controller = None
    env_kwargs = {"max_episode_steps": 480}  # the 8-target tour: 8 x t_bench (<= 0.6 s)

    def __init__(self):
        import os
        here = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        self.controller = os.path.join(here, "bin", "robolab_myo_relocate")

    def on_command(self, sim, cmd):
        if cmd.startswith("tgt:"):
            sim._ep_tgt = np.array([float(x) for x in cmd[4:].split(",")]) / 10000.0
        super().on_command(sim, cmd)

    def on_step(self, sim, obs, reward, info):
        super().on_step(sim, obs, reward, info)
        tgt = getattr(sim, "_ep_tgt", None)
        if tgt is not None and getattr(self, "verbose_bench", False) and len(sim.infos) % 10 == 0:
            print(f"{sim.d.time:5.2f} {sim.label:14s} tgt {np.round(tgt[:3], 3)} palm {np.round(sim.u.obs_dict['palm_pos'], 3)} "
                  f"err {np.linalg.norm(sim.u.obs_dict['palm_pos'] - tgt[:3]):.3f} {getattr(sim, '_dbg', '')}")
        if tgt is not None:
            ep = sim._ep if hasattr(sim, "_ep") else {}
            ep.setdefault("err", []).append(float(np.linalg.norm(sim.u.obs_dict["palm_pos"] - tgt[:3])))
            if len(tgt) > 3:
                ps = sim.d.qpos[sim.m.jnt_qposadr[sim.m.joint("pro_sup").id]]
                ep.setdefault("ps_err", []).append(abs(float(ps) - float(tgt[3])))
            sim._ep = ep

    def metrics(self, sim, log):
        out = super().metrics(sim, log)
        seg = int(round(sim.params.get("t_bench", 0.3) / sim.u.dt))  # segment length in steps
        err = list(getattr(sim, "_ep", {}).get("err", []))
        # an episode cut short (the env ends it when the palm strays 0.5 m from
        # the object) scores the missing part of the tour at 0.5 m
        err += [0.5] * max(0, 8 * seg - len(err))
        err = np.array(err)
        ends = [float(np.mean(err[max(0, k - 5):k])) for k in range(seg, len(err) + 1, seg)]
        out["track_err"] = round(float(np.mean(err)), 4)
        out["settle_err"] = round(float(np.mean(ends)), 4) if ends else 1.0
        out["max_err"] = round(float(np.max(err)), 4)
        ps = getattr(sim, "_ep", {}).get("ps_err", [])
        out["ps_err"] = round(float(np.mean(ps)), 4) if ps else 1.0
        return out

    def score(self, metrics):
        # 0.1 rad of pronation error costs like 5 cm of palm error
        return (-(metrics.get("track_err", 1.0) + 2.0 * metrics.get("settle_err", 1.0))
                - 0.5 * metrics.get("ps_err", 1.0) - 0.05 * metrics.get("act_sq", 0.0))


TASK = MyoRelocateBenchTask
