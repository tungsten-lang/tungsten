"""Outcomes and the END-TO-END objective of the chained replay (round 6).

A chain replay (chainrep.Chain.run) gives one physics trace and the ticks of the stages' triggers / releases. Each triggered stage s is scored on the slice of the
trace from its trigger tick with the replay's `oracle_search.evaluate` (gate, bounce, body, apex and arrival terms; the targets are the shaping surrogates of the
earlier rounds), and the pass verdicts of the task are emulated from the same flags:

    pass 2 (the left return)    ok  <=>  the right hand's stage-2 stroke touches the incoming ball (no body contact before it) and its ball bounces      v2
    pass 3 (the right return)   ok  <=>  its ball crosses the gate, touches no body part in flight, is received by the left hand (stage 3's touch) and
                                         stage 3's ball bounces                                                                                              v3
    pass 4 (the left second)    ok  <=>  gate, no body in flight, received by the right hand (stage 4's touch), stage 4's ball bounces                        v4
    pass 5 (the right second)   ok  <=>  gate, no body in flight, and the A4 LEFT REFLEX takes it: a logistic value function of the delivered ball (valfn)  p5

The chain's expected streak from stage 2 on is  V = v2 + v2 v3 + v2 v3 v4 + v2 v3 v4 p5  (a failed pass ends the streak); the objective the fits minimise is
-V + eps * (mean normalised stage score), a small shaping term that breaks the ties of the discrete flags.
"""
import sys

import numpy as np

for _p in ("scratchpad/btl6", "scratchpad/btl5", "scratchpad/btl2"):
    if _p not in sys.path:
        sys.path.insert(0, _p)
import fit3 as F  # noqa: E402
import oracle_search as S  # noqa: E402

# shaping surrogates: the targets the stage tables were fitted for (btl2 / btl5), with moderate weights
STAGE_CFG = {
    2: dict(who="r", target=[-0.12, 0.36], vt=[-1.5, 1.5], pos_dz=0.04, vel_dz=0.25, w_pos=2.0, w_vel=0.6, apex_min=0.68, w_apex=5.0),
    3: dict(who="l", target=[0.44, -0.26], vt=[1.55, -1.55], pos_dz=0.03, vel_dz=0.15, w_pos=6.0, w_vel=1.0, apex_min=0.68, w_apex=5.0),
    4: dict(who="r", target=[0.02, 0.38], vt=[-0.09, 1.48], pos_dz=0.05, vel_dz=0.4, w_pos=8.0, w_vel=1.0, apex_min=0.50, w_apex=5.0),
}
JCAP = 30.0
JNORM = 12.0


def feats_v(apex, ax, ay, vh):
    return np.array([apex, ax, ay, vh, ax * ax, ay * ay, ax * ay, apex * vh])


def prob_v(vf, sm):
    """the value function's probability that the next stage accepts the delivered ball (summary of a clean stroke)"""
    if vf is None:
        return 0.2
    ax, ay = float(sm["arrive"][0]), float(sm["arrive"][1])
    vh = float(np.hypot(*sm["va"][:2]))
    z = (feats_v(float(sm["apex"]), ax, ay, vh) - vf["mu"]) / vf["sd"]
    return float(1.0 / (1.0 + np.exp(-(vf["w"][0] + vf["w"][1:] @ z))))


def eval_stage(run, s):
    """(J, summary, body_pre, body_flight) of stage s on the slice of the trace from its trigger tick; None if the stage never triggered."""
    ss = run["stage"].get(s)
    if ss is None:
        return None
    t0 = ss["t0"]
    o = run["out"]
    n = len(o["pos"])
    if t0 >= n - 3:
        return None
    cfg = STAGE_CFG[s]
    hand = 1 if cfg["who"] == "r" else 0
    sl = {k: o[k][t0:] for k in ("pos", "vel", "cf", "legs", "palm")}
    sl["prehit"] = o["prehit"][t0:, hand]
    sl["t0"] = o["t0"] + t0 * 0.005
    S.ARR.clear()
    S.ARR.update({"pos_dz": cfg["pos_dz"], "vel_dz": cfg["vel_dz"], "target": cfg["target"], "vt": cfg["vt"], "pre": True,
                  "w_pos": cfg["w_pos"], "w_vel": cfg["w_vel"], "apex_min": cfg["apex_min"], "w_apex": cfg["w_apex"], "apex_tgt": None, "valfn": None})
    J, sm = F.evaluate5(sl, cfg["who"])
    pre = 0
    if sm.get("touch"):
        pc = hand
        touch = np.nonzero(sl["cf"][:, pc] > 0.3)[0]
        first = touch[0]
        pre = int(np.sum(sl["cf"][:first, 3] > 0.3)) + int(sl["prehit"][first] > 0)
    body = int(sm.get("body", 0)) if sm.get("bounced") else 0
    return J, sm, pre, max(body - pre, 0)


def chain_outcome(run, s0, vf=None, eps=0.15):
    """Flags, the chain's expected streak V and the objective for a chain replay that started at stage s0."""
    res = {}
    for s in (2, 3, 4):
        if s >= s0:
            res[s] = eval_stage(run, s)
    fl = {}
    for s, r in res.items():
        if r is None:
            fl[s] = dict(touch=False, bounced=False, gate=False, bfl=1, pre=0, J=JCAP, sm=None)
        else:
            J, sm, pre, bfl = r
            fl[s] = dict(touch=bool(sm.get("touch")), bounced=bool(sm.get("bounced")), gate=bool(sm.get("gate", 0) > 0), bfl=bfl, pre=pre, J=min(J, JCAP), sm=sm)
    g = lambda s, k, default=False: fl[s][k] if s in fl else default      # noqa: E731
    v2 = 1.0 if (g(2, "touch") and g(2, "bounced") and g(2, "pre", 0) == 0) else 0.0
    v3 = 1.0 if (g(2, "gate") and g(2, "bfl", 1) == 0 and g(2, "bounced") and g(3, "touch") and g(3, "bounced")) else 0.0
    v4 = 1.0 if (g(3, "gate") and g(3, "bfl", 1) == 0 and g(3, "bounced") and g(4, "touch") and g(4, "bounced")) else 0.0
    p5 = 0.0
    if 4 in fl and fl[4]["sm"] is not None and fl[4]["touch"] and fl[4]["bounced"] and fl[4]["gate"] and fl[4]["bfl"] == 0 and "arrive" in fl[4]["sm"]:
        p5 = prob_v(vf, fl[4]["sm"])
    if s0 == 2:
        V = v2 + v2 * v3 + v2 * v3 * v4 + v2 * v3 * v4 * p5
    elif s0 == 3:
        v3 = 1.0 if (g(3, "touch") and g(3, "bounced") and g(3, "pre", 0) == 0) else 0.0       # the stage-2 part of pass 3 is the record's
        V = v3 + v3 * v4 + v3 * v4 * p5
    else:
        v4 = 1.0 if (g(4, "touch") and g(4, "bounced") and g(4, "pre", 0) == 0) else 0.0
        V = v4 + v4 * (p5 if p5 > 0 else 0.0)
    sh = float(np.mean([fl[s]["J"] / JNORM for s in fl]))
    return {"V": V, "obj": -V + eps * sh, "v2": v2, "v3": v3, "v4": v4, "p5": p5, "fl": fl, "sh": sh}


def fit_logistic(X, y, ridge):
    mu, sd = X.mean(0), X.std(0) + 1e-9
    Z = (X - mu) / sd
    Z1 = np.hstack([np.ones((len(Z), 1)), Z])
    w = np.zeros(Z1.shape[1])
    R = ridge * np.eye(len(w))
    R[0, 0] = 0
    for _ in range(100):
        p = 1 / (1 + np.exp(-Z1 @ w))
        gr = Z1.T @ (p - y) + R @ w
        H = Z1.T @ (Z1 * (p * (1 - p))[:, None]) + R
        w = w - np.linalg.solve(H, gr)
    return w, mu, sd
