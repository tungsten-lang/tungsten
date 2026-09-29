"""Open-loop physics probes from saved states (no controller process): restore the MuJoCo state of a dumped run at tick k0,
step it with the recorded activations (A lines) plus a perturbation, read the contact. Answers 'which muscles move the
kick's contact point, and by how much'.

  from kprobe import Probe
  p = Probe()                                  # one sim per process
  r = p.run(pack, k0, perturb=None)            # exact replay: r['tr'] equals the dump's trace
  r = p.run(pack, k0, perturb=dict(joint='hip_rotation_r', sign=+1, tau=15, t0=0.05, dur=0.1))
"""
import gzip
import math
import os
import pickle
import sys

import numpy as np

sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
import kcommon as K


def load(path):
    with gzip.open(path, "rb") as f:
        return pickle.load(f)


class Probe:
    def __init__(self, seed=5000):
        K.ensure()
        # a controller is never started: the sim only provides the env, task and helpers
        self.sim = K.make_sim({}, K.P1_CTL, seed, dict(noise=0.0, dx=0.0, dy=0.0))
        self.sim.record = False
        m = self.sim.m
        import mujoco
        self.mujoco = mujoco
        self.nm = self.sim.n
        self.mid = np.array(self.sim.muscle_ids)
        self.fmax = np.maximum(m.actuator_gainprm[self.mid, 2], 1e-6)
        self.dof = {}
        for j in range(m.njnt):
            self.dof[m.joint(j).name] = m.jnt_dofadr[j]

    def moments(self):
        """Live moment arms (dL/dq) of every muscle about every dof, at the current state."""
        sim = self.sim
        m, d = sim.m, sim.d
        mom = np.zeros((m.nu, m.nv))
        self.mujoco.mju_sparse2dense(mom, d.actuator_moment, d.moment_rownnz, d.moment_rowadr, d.moment_colind)
        return mom[self.mid]

    def torque_drive(self, joints, taus, mom):
        """Minimum-norm nonnegative activation increments giving torques taus about joints (N m at full FLV): each muscle's torque per
        unit activation is -arm * Fmax (peak isometric force)."""
        # rows: joints; a = A^T (A A^T)^-1 tau over the muscles whose sign is right for the first joint with nonzero tau
        A = np.array([-mom[:, self.dof[j]] * self.fmax for j in joints])  # (nj, nm) torque per unit activation
        act = np.ones(self.nm, bool)
        tau = np.array(taus, float)
        a = np.zeros(self.nm)
        for _ in range(8):
            As = A[:, act]
            G = As @ As.T + 1e-9 * np.eye(len(joints))
            y = np.linalg.solve(G, tau)
            av = As.T @ y
            a[:] = 0.0
            a[act] = av
            neg = a < 0
            if not neg.any():
                break
            act = act & ~neg
            a[neg] = 0.0
        return np.clip(a, 0.0, 1.0)

    def run(self, pack, k0, perturb=None, until=None, extra=None, law=None):
        sim = self.sim
        task = sim.task
        task.reset_stats()
        task._sim = sim
        sim.label = ""
        # gymnasium's TimeLimit counts every step since the env's reset: rewind it (2000 steps ends an episode)
        w = sim.env
        while w is not None and w is not sim.u:
            if hasattr(w, "_elapsed_steps"):
                w._elapsed_steps = 0
            w = getattr(w, "env", None)
        sim.restore(pack["state"][k0])
        n = self.nm
        A = pack["A"]
        j = k0
        t_start = sim.d.time
        pert = None
        if perturb:
            mom = self.moments()
            joints = perturb["joints"] if "joints" in perturb else [perturb["joint"]]
            signs = perturb.get("signs", [perturb.get("sign", 1.0)])
            taus = [s * perturb["tau"] * perturb.get("w", [1.0] * len(joints))[i] for i, s in enumerate(signs)]
            pert = self.torque_drive(joints, taus, mom)
        info = {}
        while True:
            tok = A[j].split() if j < len(A) else A[-1].split()
            act = np.clip(np.array([float(x) for x in tok[1:1 + n]]), 0.0, 1.0)
            sim.label = tok[1 + 2 * n] if len(tok) > 1 + 2 * n else ""
            if law is not None:
                c = law(sim, task, sim.d.time - t_start)
                if c is not None:
                    act = np.clip(act + self.torque_drive(c["joints"], c["taus"], self.moments()), 0.0, 1.0)
            if pert is not None:
                el = sim.d.time - t_start
                if perturb.get("t0", 0.0) <= el < perturb.get("t0", 0.0) + perturb.get("dur", 0.1):
                    act = np.clip(act + pert, 0.0, 1.0)
            obs, reward, term, trunc, info = sim.env.step(sim.action_from(act))
            task.on_step(sim, obs, reward, info)
            j += 1
            if term or trunc:
                break
            if until is not None and sim.d.time >= until:
                break
            if task.touch_t is not None and sim.d.time > task.touch_t + 0.25:
                break
            if j > len(A) + 60:
                break
        m = task.metrics(sim, [])
        return {"m": m, "tr": task.tr, "task": task, "touch_t": task.touch_t}


def cross_summary(r, xc=-0.10):
    """the toe (bofoot) relative to the ball when it passes xc behind the ball centre (interpolated), the time, and the toe
    velocity there; None if it never gets there (a fall or a swing that stops short)."""
    tr = r["tr"]
    prev = None
    for row in tr:
        d = row["bof_r"] - row["ball"]
        if prev is not None and prev[0][0] < xc <= d[0]:
            u = (xc - prev[0][0]) / max(d[0] - prev[0][0], 1e-9)
            dd = prev[0] + u * (d - prev[0])
            return {"y": float(dd[1]), "z": float(dd[2]), "t": prev[1] + u * (row["t"] - prev[1]),
                    "v": [float(v) for v in row["vtoe_r"]]}
        prev = (d, row["t"])
        if row["ball"][0] > 40.05:  # the ball has left
            break
    return None


def contact_summary(r):
    """toe (bofoot) relative to the ball at the first touch tick, the ball speed and launch."""
    tr = r["tr"]
    t = r["touch_t"]
    out = {"ball_speed": r["m"].get("ball_speed"), "launch": r["m"].get("launch_deg"), "touch": t}
    if t is None:
        return out
    for row in tr:
        if row["t"] >= t - 1e-9:
            d = row["bof_r"] - row["ball"]
            out["toe"] = [float(v) for v in d]
            out["vtoe"] = [float(v) for v in row["vtoe_r"]]
            break
    return out


if __name__ == "__main__":
    # exactness check: open-loop replay from the swing start reproduces the dump
    path = sys.argv[1]
    pack = load(path)
    tr0 = pack["trace"]
    k0 = next(i for i, r in enumerate(tr0) if r["lab"] == "swing") - 3
    p = Probe()
    r = p.run(pack, k0)
    worst = 0.0
    for a, b in zip(r["tr"], tr0[k0:]):
        worst = max(worst, float(np.max(np.abs(a["bof_r"] - b["bof_r"]))), abs(a["t"] - b["t"]))
    print("k0", k0, "replayed steps", len(r["tr"]), "max deviation from the dump", worst)
    print(contact_summary(r), pack["row"]["ball_speed"], pack["row"].get("ct_toe"))
