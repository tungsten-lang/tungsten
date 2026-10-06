"""Shared extraction for the dither / regression work: per run and stage the features at decision times, the outcomes and the offsets."""
import json
import sys

import numpy as np

sys.path.insert(0, "scratchpad/btl3")
import m1_analyze as A  # noqa: E402

LEAD = 0.165
H = 0.62
G = 9.81


def next_input(z, kr, lead=LEAD):
    """The ball's state at the NEXT stage's trigger (its first tick, after the first floor bounce following the release at tick kr, whose predicted rising
    crossing of z 0.62 is within `lead`): returns dict(k, pc (x, y, t), bv (3), bp (3)) or None."""
    ball, ballv = z["ball"], z["ballv"]
    n = len(ball)
    kb = None
    for k in range(kr + 1, n - 1):
        if ball[k, 2] < 0.16 and ballv[k, 2] > 0 and ballv[k - 1, 2] <= 0:
            kb = k
            break
    if kb is None:
        return None
    for k in range(kb + 1, min(n, kb + 150)):
        if ball[k - 1, 2] < 0.14:
            continue
        pc = A.predicted_cross(ball[k - 1], ballv[k - 1])
        if pc is not None and pc[2] <= lead:
            return {"k": k, "pc": pc, "bv": ballv[k - 1].copy(), "bp": ball[k - 1].copy()}
    return None


def stage_run(z, stage):
    """Everything about stage `stage` (program ordinal 0, 1, 2) of one run, or None if the stage did not run to a release."""
    ws = A.stage_windows(z)
    if len(ws) <= stage:
        return None
    side, k0 = ws[stage]
    rec = A.extract(z, side, k0)
    if rec is None or "rel_v" not in rec:
        return None
    pl = json.loads(str(z["pass_log"]))
    e = pl[stage] if stage < len(pl) else {}
    nxt = next_input(z, rec["kr"])
    a = A.arrival(z, rec["kr"])
    c, cd = z["c_" + side], z["cd_" + side]
    live = {}
    for k in (0, 6, 12, 20, 30):
        i = k0 + k                       # the controller's view at tick k0 + k: the contraction recorded for that tick
        if i >= len(c):
            return None
        live[k] = np.concatenate([c[i][0::2] - c[i][1::2], cd[i][0::2] - cd[i][1::2]])
    out = {"k0": k0, "kt": rec["kt"], "kr": rec["kr"], "side": side, "pc": rec["pc"], "bv0": z["ballv"][k0 - 1].copy(), "live": live,
           "rel_v": rec["rel_v"], "touch": rec["touch"], "arr": a[0] if a else None, "apex": a[1] if a else None, "next": nxt,
           "gate": bool(e.get("gate")), "body": int(e.get("body", 0) or 0), "ok": bool(e.get("ok")), "outcome": e.get("outcome")}
    nxt_e = pl[stage + 1] if stage + 1 < len(pl) else {}
    out["next_ok"] = bool(nxt_e.get("ok"))
    out["next_released"] = bool(nxt_e.get("released"))
    out["next_outcome"] = nxt_e.get("outcome")
    return out
