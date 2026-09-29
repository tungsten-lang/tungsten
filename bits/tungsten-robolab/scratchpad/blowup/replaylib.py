"""Shared helpers: load a capture directory (capture.py output), rebuild the stepped MjData bit for bit, and step it.

    m, ring = replaylib.load(DIR)                # model.mjb + ring.npz (+ fail.npz)
    d = replaylib.data_at(m, ring, k)            # MjData holding ring state k (the state AFTER control step k, incl. its ctrl)
    replaylib.control_step(m, d, ctrl, n=10)     # apply ctrl, n mj_step calls (MyoSuite: frame_skip 10)
    replaylib.quiet()                            # silence MuJoCo warnings (they are also the blow-up signal: see WarnCatcher)
"""
import numpy as np
import mujoco


def load(path):
    m = mujoco.MjModel.from_binary_path(path.rstrip("/") + "/model.mjb")
    r = dict(np.load(path.rstrip("/") + "/ring.npz"))
    return m, r


def data_at(m, ring, k):
    d = mujoco.MjData(m)
    mujoco.mj_setState(m, d, ring["state"][k], int(ring["spec"]))
    return d


def ctrl_of(m, ring, k):
    """the ctrl stored with ring state k (the ctrl applied during control step k)"""
    d = mujoco.MjData(m)
    mujoco.mj_setState(m, d, ring["state"][k], int(ring["spec"]))
    return d.ctrl.copy()


class WarnCatcher:
    """user warning callback that records (time, message) and lets the rollout continue"""

    def __init__(self):
        self.events = []
        self.d = None

    def __call__(self, msg):
        self.events.append((None if self.d is None else float(self.d.time), msg))


def quiet():
    mujoco.set_mju_user_warning(lambda msg: None)


def control_step(m, d, ctrl, n=10):
    d.ctrl[:] = ctrl
    for _ in range(n):
        mujoco.mj_step(m, d)
