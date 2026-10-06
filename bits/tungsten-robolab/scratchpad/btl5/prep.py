"""Compact per-start replay data for one stage of the recorded closed-loop starts (round 5): the snapshot at the stage's trigger tick, the recorded
activations of the next NEVAL + 1 ticks, the schedule features at the trigger (predicted rising crossing x, y, time; vertical speed at the crossing; the
stroking arm's posture features), the pg_align clock shift and the baseline's pass outcomes.

    scratchpad/btl5/py scratchpad/btl5/prep.py rec_dir stage out.pkl [workers] [lead]       (stage ordinal 0..4; hand and bounce number as an5_stage.STAGES5)
"""
import os
import pickle
import sys

import numpy as np

sys.path.insert(0, "scratchpad/btl4")
sys.path.insert(0, "scratchpad/btl2")
sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
from multiprocessing import Pool  # noqa: E402

import rlib  # noqa: E402
import oracle_multi as M  # noqa: E402

STAGES5 = {0: ("r", 1), 1: ("l", 2), 2: ("r", 3), 3: ("l", 4), 4: ("r", 5), 5: ("l", 6)}
ZJ = [4, 1, 3]
NEVAL = 200
_RP = {}


def pred_cross5(rp, k, height=0.62):
    """(x, y, t) of the ball's predicted rising crossing of `height` as the skill's receive_state computes it from the sensor frame at tick k, for a
    RISING ball (the sensor's state is the current one, with the stale position) and for a FALLING ball (the state it rises from after its next bounce,
    predict_rise from the stale position): oracle_lib.Replay.pred_cross handles only the first."""
    rp.load(k)
    d, m = rp.d, rp.m
    ps = rp.rec["ball"][k - 1]
    v = d.qvel[rp.ball_dof:rp.ball_dof + 3].copy()
    spin = d.body("ball").xmat.reshape(3, 3) @ d.qvel[rp.ball_dof + 3:rp.ball_dof + 6]
    r = rp.t.predict_rise(ps.copy(), v, spin)
    vz = r[5]
    if vz <= 0.5:
        return None
    g = 9.81
    disc = vz * vz - 2.0 * g * (height - r[2])
    s = vz / g
    if disc > 0.0:
        s = (vz - np.sqrt(disc)) / g
    return (r[0] + r[3] * s, r[1] + r[4] * s, r[6] + s, float(np.sqrt(max(disc, 0.0))))


def trigger_tick5(rec, rp, bounce_no, lead, kmin):
    """The tick at which the skill's trigger fires for the stage working on the ball of floor bounce `bounce_no`: the first tick k >= kmin (after the previous
    pass's release) with the ball off the floor whose predicted rising crossing of z 0.62 is within `lead` s: the ball may still be FALLING toward the bounce."""
    ball, bv = rec["ball"], rec["ballv"]
    nb = 0
    for k in range(1, len(ball)):
        if ball[k, 2] < 0.16 and bv[k, 2] > 0 and bv[k - 1, 2] <= 0:
            nb += 1
        if nb >= bounce_no - 1 and k >= kmin and k in rec["snaps"]:
            if ball[k - 1][2] < 0.14:
                continue
            pc = pred_cross5(rp, k)
            if pc is not None and pc[2] <= lead:
                return k
    return None


def one(job):
    seed, path, stage = job[:3]
    lead = job[3] if len(job) > 3 else rlib.LEAD
    rec = pickle.load(open(path, "rb"))
    import oracle_lib as O
    rp = _RP.get("rp")        # one Replay per process (the model does not depend on the seed): swap the record instead of rebuilding the model
    if rp is None:
        rp = _RP["rp"] = O.Replay(rec)
    rp.rec = rec
    rp.act_ids = rec["act_ids"]
    hand, bn = STAGES5[stage]
    if lead <= 0.17:
        ks = M.trigger_tick(rec, rp, bn, lead=lead)
        pcf = rp.pred_cross
    else:
        kp = M.trigger_tick(rec, rp, bn - 1, lead=0.165) if bn >= 2 else 0
        ks = None if kp is None else trigger_tick5(rec, rp, bn, lead, kp + 50)
        pcf = lambda k: pred_cross5(rp, k)
    if ks is None or ks not in rec["snaps"] or ks + NEVAL + 1 > len(rec["acts"]):
        return None
    pc = pcf(ks)
    if pc is None:
        return None
    post = rp.posture(ks, hand, ZJ)
    if len(pc) > 3:
        vzc = pc[3]
    else:
        vz0 = float(rec["ballv"][ks - 1][2])
        z0 = float(rec["ball"][ks - 1][2])
        disc = vz0 * vz0 - 2 * 9.81 * (0.62 - z0)
        vzc = float(np.sqrt(disc)) if disc > 0 else 0.0
    small = {"seed": rec["seed"], "act_ids": rec["act_ids"], "names": rec["names"], "k0": 0, "snaps": {0: rec["snaps"][ks]}, "snap": rec["snaps"][ks],
             "acts": rec["acts"][ks:ks + NEVAL + 1].copy(), "pass_log": rec["pass_log"], "streak": rec["streak"]}
    return {"seed": seed, "stage": stage, "hand": hand, "ks": int(ks), "feat": np.array([pc[0], pc[1]] + post), "pt": float(pc[2]), "vzc": vzc,
            "shift": float(lead - 0.0025 - pc[2]), "lead": lead, "rec": small, "pass_ok": [bool(p.get("ok")) for p in rec["pass_log"]],
            "pass_log": rec["pass_log"], "streak": rec["streak"]}


def main():
    rec_dir, stage, outf = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    workers = int(sys.argv[4]) if len(sys.argv) > 4 else 4
    lead = float(sys.argv[5]) if len(sys.argv) > 5 else rlib.LEAD
    files = sorted(f for f in os.listdir(rec_dir) if f.startswith("rec_") and f.endswith(".pkl"))
    jobs = [(int(f[4:-4]), os.path.join(rec_dir, f), stage, lead) for f in files]
    with Pool(workers) as p:
        res = p.map(one, jobs, chunksize=4)
    res = [r for r in res if r is not None]
    pickle.dump(res, open(outf, "wb"), protocol=4)
    print("wrote", outf, len(res), "of", len(jobs))


if __name__ == "__main__":
    main()
