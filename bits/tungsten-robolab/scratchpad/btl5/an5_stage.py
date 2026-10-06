"""Per-start stage data of the recorded baseline: trigger ticks, schedule features (predicted crossing x, y, t, vertical speed at the crossing, the
stroking arm's posture wrist flexion / shoulder abduction / elbow) and the closed-loop outcomes of passes 1-5, for every stage 0-4.

    OMP_NUM_THREADS=1 .venv/bin/python scratchpad/btl5/an5_stage.py rec_dir out.pkl [workers]
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

STAGES5 = {0: ("r", 1), 1: ("l", 2), 2: ("r", 3), 3: ("l", 4), 4: ("r", 5)}
ZJ = [4, 1, 3]


def one(job):
    seed, path = job
    rec = pickle.load(open(path, "rb"))
    import oracle_lib as O
    rp = O.Replay(rec)
    out = {"seed": seed, "streak": rec["streak"], "pass_ok": [bool(p.get("ok")) for p in rec["pass_log"]], "pass_log": rec["pass_log"], "stages": {}}
    for st, (hand, bn) in STAGES5.items():
        ks = M.trigger_tick(rec, rp, bn, lead=rlib.LEAD)
        if ks is None or ks not in rec["snaps"]:
            continue
        pc = rp.pred_cross(ks)
        if pc is None:
            continue
        post = rp.posture(ks, hand, ZJ)
        # vertical speed at the crossing: from the sensor's rising prediction (ball_rise): recompute from the recorded ball velocity
        vz0 = float(rec["ballv"][ks - 1][2]) if ks >= 1 else 0.0
        z0 = float(rec["ball"][ks - 1][2]) if ks >= 1 else 0.0
        disc = vz0 * vz0 - 2 * 9.81 * (0.62 - z0)
        vzc = float(np.sqrt(disc)) if disc > 0 else 0.0
        out["stages"][st] = {"ks": int(ks), "x": float(pc[0]), "y": float(pc[1]), "t": float(pc[2]), "vzc": vzc, "post": post}
    return out


def main():
    rec_dir, outf = sys.argv[1], sys.argv[2]
    workers = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    files = sorted(f for f in os.listdir(rec_dir) if f.startswith("rec_") and f.endswith(".pkl"))
    jobs = [(int(f[4:-4]), os.path.join(rec_dir, f)) for f in files]
    with Pool(workers) as p:
        res = p.map(one, jobs, chunksize=4)
    pickle.dump(res, open(outf, "wb"))
    print("wrote", outf, len(res))


if __name__ == "__main__":
    main()
