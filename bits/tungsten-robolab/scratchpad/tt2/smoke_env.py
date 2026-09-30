"""Smoke test: build the official env and the rung envs, compare the scaled actuator fields (agent T2)."""
import os, sys
HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(HERE, "playground"))
os.environ.setdefault("TT_ENV", "P2")
import numpy as np, mujoco
from myosuite.utils import gym
import warnings; warnings.filterwarnings("ignore")
rung = int(os.environ.get("MYO_TT_BEYOND", "0") or 0)
from tasks import myo_tt_beyond as mtb
off = gym.make("myoChallengeTableTennisP2-v0").unwrapped
mo = off.mj_model
print("registered rungs:", [k for k in gym.registry if "Beyond" in k])
mus = np.nonzero(mo.actuator_dyntype == mujoco.mjtDyn.mjDYN_MUSCLE)[0]
oth = np.nonzero(mo.actuator_dyntype != mujoco.mjtDyn.mjDYN_MUSCLE)[0]
for r in sorted(mtb.ladder()):
    if rung and r != rung: continue
    if not rung: 
        # rung 0 run: the beyond ids are not registered; skip
        break
    e = gym.make(mtb.beyond_id(r)).unwrapped
    m = e.mj_model
    S, V, A = mtb.ladder()[r]
    print("rung", r, "audit", e.beyond, "| robot model is env model:", e.robot.mj_model is m)
    print("  F0 ratio min/max", (m.actuator_gainprm[mus, 2] / mo.actuator_gainprm[mus, 2]).min(), (m.actuator_gainprm[mus, 2] / mo.actuator_gainprm[mus, 2]).max(), "expected", S)
    print("  bias F0 ratio", np.unique(np.round(m.actuator_biasprm[mus, 2] / mo.actuator_biasprm[mus, 2], 9)))
    print("  vmax ratio", np.unique(np.round(m.actuator_gainprm[mus, 6] / mo.actuator_gainprm[mus, 6], 9)), "bias", np.unique(np.round(m.actuator_biasprm[mus, 6] / mo.actuator_biasprm[mus, 6], 9)), "expected", V)
    print("  tau_act ratio", np.unique(np.round(m.actuator_dynprm[mus, 0] / mo.actuator_dynprm[mus, 0], 9)), "tau_deact", np.unique(np.round(m.actuator_dynprm[mus, 1] / mo.actuator_dynprm[mus, 1], 9)), "expected", A)
    same = all(np.array_equal(getattr(m, k), getattr(mo, k)) for k in ("actuator_gainprm", "actuator_biasprm", "actuator_dynprm") if False)
    print("  pelvis actuators unchanged:", all(np.array_equal(m.actuator_gainprm[i], mo.actuator_gainprm[i]) and np.array_equal(m.actuator_biasprm[i], mo.actuator_biasprm[i]) and np.array_equal(m.actuator_dynprm[i], mo.actuator_dynprm[i]) for i in oth))
    # everything else identical?
    diffs = []
    for name in dir(mo):
        if name.startswith("_"): continue
        try:
            a, b = getattr(mo, name), getattr(m, name)
        except Exception:
            continue
        if isinstance(a, np.ndarray) and isinstance(b, np.ndarray) and a.shape == b.shape and a.dtype.kind in "fiub":
            if not np.array_equal(a, b, equal_nan=True) if a.dtype.kind == "f" else not np.array_equal(a, b):
                diffs.append(name)
    print("  model arrays that differ from the official compile:", diffs)
