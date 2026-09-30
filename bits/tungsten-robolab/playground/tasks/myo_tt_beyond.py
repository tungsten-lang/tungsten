"""MyoChallenge 2025 table tennis on a LABELLED BEYOND-HUMAN ARM (variant "myo_beyond_arm", agent T2, 29 Sep 2026).

LABEL. Everything about this task is a BEYOND-HUMAN ARM: the official MyoSuite table-tennis body with every muscle stronger, faster to
shorten and faster to activate by invented round numbers (playground/profiles/myo_beyond_arm.json: the rule, the ladder and the go/no-go
criterion, written BEFORE any rollout ran on a rung). It is not a human profile. Its results are never to be compared with the official
trials (tt_p1, tt_p2, tt_p2_300, tt_p2_backhand) and it never touches an official champion.

WHY. Agent T (scratchpad/tt/LOG.md) showed that 90 % of phase-2 serves is out of reach for the official arm: the arm's execution noise (pad pitch
10 deg, pad velocity 0.5 m/s, place 5 cm, 1 sigma each) caps even a perfect plan near 45 %. This task asks whether a stronger, faster arm
removes that limit for the unchanged champion controller.

SWITCH. env var MYO_TT_BEYOND = the ladder rung. 0 or unset: the OFFICIAL env, the very same env class and id (`myoChallengeTableTennis<P>-v0`),
so a rollout is byte-identical to tasks/myo_tt.py's (proved by scratchpad/tt2/identity.py). 1, 2, 3: the rung's multipliers (the
JSON file's `ladder`) are applied once, when the env is constructed, to the compiled MjModel that MyoSuite's env and its Robot share (so the
stepped MjData, the sensor-synced mirror the controller reads and the bridge's MFORCE all see it), to each of the 273 actuators whose dyntype is
MUSCLE:
    peak isometric force  gainprm[2] and biasprm[2]  x strength   (the muscles' force -1 in the XML is resolved by the compile: 4.8-2150.7 N)
    maximum shortening speed vmax  gainprm[6] and biasprm[6]  x speed
    activation / deactivation time constants  dynprm[0] and dynprm[1]  x activation
UNCHANGED: the two pelvis position actuators, every geometry, tendon, mass, inertia, joint range and damping, contact, sensor, the reset, the
serve randomisation, the ball, the paddle and the scoring. The controller is told the body it has: the bridge's MFORCE line carries the compiled
(scaled) peak force of each muscle.

The rung's env is registered under `myoChallengeTableTennis<P>Beyond<rung>-v0` (kwargs of the official spec plus beyond_rung) when this module is
imported; the scaling happens at the start of the env's `_setup`, before its Robot exists and before its first step, so the model is exactly
what an XML with these numbers would compile to (MuJoCo derives nothing from these fields at compile time: acc0 and lengthrange do not depend
on the force, vmax or the time constants).

Extra metrics, only at rungs above 0 (rung 0 adds none, so its metrics dict equals the official task's on every key): beyond_rung,
beyond_f0_ratio (sum of the muscles' peak forces now over the official sum), beyond_vmax_ratio, beyond_tau_ratio.

DIAGNOSTIC WHAT-IFS (added 23:12, AFTER the go/no-go verdict of 23:09 was written into the rule file; never a candidate rung, never compared with
the ladder's results as a result): MYO_TT_BEYOND=9 with MYO_TT_BEYOND_DIAG="strength,speed,activation" applies those three multipliers instead of a
rung's (one factor at a time, or a unit check "1,1,1"), and MYO_TT_BEYOND_GROUP = arm (the 32 ARM_MUSCLES of tasks/myo_tt.py) / hand (the 31 finger and thumb
muscles) / trunk (the other 210) restricts them to one muscle group (default: all 273). Rung 9's metrics carry beyond_rung 9.
"""

import json
import os
import sys

import numpy as np

_PLAYGROUND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PLAYGROUND not in sys.path:
    sys.path.insert(0, _PLAYGROUND)

from tasks.myo_tt import PHASE, MyoTTTask  # noqa: E402

PROFILE = os.path.join(_PLAYGROUND, "profiles", "myo_beyond_arm.json")


def ladder():
    """{rung: (strength, speed, activation)} from the rule file (the single source of the multipliers)."""
    with open(PROFILE) as f:
        return {int(r["rung"]): (float(r["strength"]), float(r["speed"]), float(r["activation"])) for r in json.load(f)["ladder"]}


def rung_from_env():
    return int(os.environ.get("MYO_TT_BEYOND", "0") or "0")


DIAG_RUNG = 9


def multipliers(rung):
    """(strength, speed, activation) of a ladder rung; rung 9 = the post-verdict diagnostic what-if of MYO_TT_BEYOND_DIAG."""
    if rung == DIAG_RUNG:
        s, v, a = (float(x) for x in os.environ["MYO_TT_BEYOND_DIAG"].split(","))
        return s, v, a
    return ladder()[rung]


HAND = ("FDS", "FDP", "EDC", "EDM", "EIP", "EPL", "EPB", "FPL", "APL", "RI", "LU_RB", "UI_UB")


def muscle_group(name):
    """arm / hand / trunk, for the post-verdict what-ifs (rung 9 with MYO_TT_BEYOND_GROUP)"""
    if name in MyoTTTask.ARM_MUSCLES:
        return "arm"
    if name == "OP" or name.startswith(HAND):
        return "hand"
    return "trunk"


def apply_rung(m, rung):
    """Scale the muscle actuators of the compiled MjModel `m` in place by the rung's multipliers; returns an audit dict."""
    import mujoco
    strength, speed, activation = multipliers(rung)
    mus = np.nonzero(m.actuator_dyntype == mujoco.mjtDyn.mjDYN_MUSCLE)[0]
    if rung == DIAG_RUNG and os.environ.get("MYO_TT_BEYOND_GROUP", "all") != "all":
        mus = np.array([i for i in mus if muscle_group(m.actuator(int(i)).name) == os.environ["MYO_TT_BEYOND_GROUP"]], dtype=int)
    before = (float(m.actuator_gainprm[mus, 2].sum()), float(m.actuator_gainprm[mus, 6].sum()),
              float(m.actuator_dynprm[mus, 0].sum() + m.actuator_dynprm[mus, 1].sum()))
    for arr, col, k in ((m.actuator_gainprm, 2, strength), (m.actuator_biasprm, 2, strength),
                        (m.actuator_gainprm, 6, speed), (m.actuator_biasprm, 6, speed),
                        (m.actuator_dynprm, 0, activation), (m.actuator_dynprm, 1, activation)):
        arr[mus, col] = arr[mus, col] * k
    after = (float(m.actuator_gainprm[mus, 2].sum()), float(m.actuator_gainprm[mus, 6].sum()),
             float(m.actuator_dynprm[mus, 0].sum() + m.actuator_dynprm[mus, 1].sum()))
    return {"rung": rung, "n_muscles": int(len(mus)), "strength": strength, "speed": speed, "activation": activation,
            "f0_ratio": after[0] / before[0], "vmax_ratio": after[1] / before[1], "tau_ratio": after[2] / before[2]}


def _env_class():
    from myosuite.envs.myo.myochallenge.tabletennis_v0 import TableTennisEnvV0

    class BeyondTableTennisEnv(TableTennisEnvV0):
        """The official env whose muscle actuators carry a ladder rung's multipliers (LABELLED BEYOND-HUMAN ARM)."""

        def __init__(self, model_path, obsd_model_path=None, seed=None, beyond_rung=1, **kwargs):
            self._beyond_rung = int(beyond_rung)
            super().__init__(model_path, obsd_model_path, seed, **kwargs)

        def _setup(self, *args, **kwargs):
            # the model is compiled and shared by env and Robot; scale it before the Robot is built and before the setup's first step
            self.beyond = apply_rung(self.mj_model, self._beyond_rung)
            super()._setup(*args, **kwargs)

    return BeyondTableTennisEnv


def beyond_id(rung, phase=PHASE):
    return f"myoChallengeTableTennis{phase}Beyond{rung}-v0"


def register(phase=PHASE):
    from myosuite.utils import gym
    spec = gym.spec(f"myoChallengeTableTennis{phase}-v0")
    cls = _env_class()
    for rung in list(ladder()) + ([DIAG_RUNG] if os.environ.get("MYO_TT_BEYOND_DIAG") else []):
        if beyond_id(rung, phase) not in gym.registry:
            gym.register(id=beyond_id(rung, phase), entry_point=cls, max_episode_steps=spec.max_episode_steps,
                         kwargs={**spec.kwargs, "beyond_rung": rung})


RUNG = rung_from_env()
if RUNG:
    if RUNG not in ladder() and not (RUNG == DIAG_RUNG and os.environ.get("MYO_TT_BEYOND_DIAG")):
        raise ValueError(f"MYO_TT_BEYOND={RUNG}: not a rung of {PROFILE} (0 = official, {sorted(ladder())}; 9 needs MYO_TT_BEYOND_DIAG)")
    register()


class MyoTTBeyondTask(MyoTTTask):
    """MyoTTTask on the official env (MYO_TT_BEYOND 0/unset) or on the beyond-human arm of the rung (1-3). Same skill name, same controller protocol."""

    env_id = MyoTTTask.env_id if RUNG == 0 else beyond_id(RUNG)

    def metrics(self, sim, log):
        out = super().metrics(sim, log)
        if RUNG:
            b = sim.u.beyond
            if b["rung"] != RUNG:
                raise RuntimeError(f"the env carries rung {b['rung']} but MYO_TT_BEYOND says {RUNG}")
            out["beyond_rung"] = float(b["rung"])
            out["beyond_f0_ratio"] = round(b["f0_ratio"], 4)
            out["beyond_vmax_ratio"] = round(b["vmax_ratio"], 4)
            out["beyond_tau_ratio"] = round(b["tau_ratio"], 4)
        return out


TASK = MyoTTBeyondTask
