"""long_jump_mine: which approach states make the jump fail?

Takes the captured approach states (long_jump_limits.py capture --from pen,
one <name>_s<seed>_capture.npz per start), runs the skill's take-off program
from each (long_jump_limits.py handover, saved as a hand-over set), then the
landing program (with or without the ballistic-time clock) on each hand-over,
and prints, per start, the approach features at the penultimate touchdown
(torso pitch and rate, COM speed, the plant-side foot's geometry) beside the
outcome (take-off valid, foul, vz, L, official mark). Answers: do the failures
of the full rollouts cluster in the approach state?

    .venv/bin/python playground/long_jump_mine.py <name> <handover_set> <il program> [--tg 0.61] [--workers 3]

`name` is the capture prefix (p95mn -> p95mn_s8001 ...), <handover_set> the
`handover --name` output, matching the captures in order (variants off).
"""

import argparse
import json
import math
import multiprocessing as mp
import os
import sys

os.environ.setdefault("MUJOCO_GL", "cgl")
import mujoco  # noqa: E402
import numpy as np  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import long_jump_limits as L  # noqa: E402
import long_jump_diag as D  # noqa: E402


def features(body, cap):
    """Approach state at the penultimate touchdown (the capture's state)."""
    m, d = body.m, body.d
    mujoco.mj_setState(m, d, cap["state"], L.SPEC)
    mujoco.mj_forward(m, d)
    mujoco.mj_subtreeVel(m, d)
    pel = body.pelvis
    com = d.subtree_com[pel]
    v = d.subtree_linvel[pel]
    tv = np.zeros(6)
    mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_BODY, body.torso, tv, 0)
    plant = cap["plant"]
    pen = "l" if plant == "r" else "r"
    return {
        "torso": body.torso_pitch(), "torso_rate": float(tv[1]), "pelvis": D.pitch_of(body, "pelvis"),
        "com_z": float(com[2]), "vx": float(v[0]), "vz": float(v[2]),
        "Ly": float(d.subtree_angmom[pel][1]),
        "gap": float(cap["board_x"] - L.seen_site_x(body, f"{pen}_toe")),
        "swing_ahead": float(d.xpos[m.body(f"{plant}_foot").id][0] - com[0]),
        "swing_z": float(d.xpos[m.body(f"{plant}_foot").id][2]),
        "pen_ahead": float(d.xpos[m.body(f"{pen}_foot").id][0] - com[0]),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("handover")
    ap.add_argument("program")
    ap.add_argument("--tg", type=float, default=0.0)
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--capture", default=None, help="a capture of the same scene (default: the first of the set)")
    a = ap.parse_args()
    hos = L.load_handover(a.handover)
    names = [h["name"] for h in hos]
    c0 = L.load_capture(a.capture or names[0])
    body = L.Body(c0["task"], c0["board_x"], json.loads(c0["env"]))
    feats = {}
    for nm in names:
        feats[nm] = features(body, L.load_capture(nm))
    with mp.Pool(a.workers, initializer=D._scan_init, initargs=(a.handover, names[0], a.program)) as pool:
        res = pool.map(D._scan_one, [(i, a.tg, None) for i in range(len(hos))], chunksize=1)
    print("name             torso  rate   pel    z     vx    vz    Ly   gap   swing  sz  | valid foul  vz    L    Dboard mark  pitch")
    rows = []
    for h, r in zip(hos, res):
        f = feats[h["name"]]
        rows.append((h, f, r))
        print("%-16s %5.2f %5.2f %5.2f %5.2f %5.2f %5.2f %5.1f %5.2f %5.2f %4.2f | %d %d %5.2f %5.1f %5.2f %5.2f %s" % (
            h["name"], f["torso"], f["torso_rate"], f["pelvis"], f["com_z"], f["vx"], f["vz"], f["Ly"], f["gap"],
            f["swing_ahead"], f["swing_z"], 1 if h["valid"] else 0, 1 if h["foul"] else 0, h["vz"] or 0.0,
            h["L"] or 0.0, h["D_board"] or 0.0, r[0], "" if r[2] is None else "%.2f" % r[2]))
    # summary
    ok = [r for h, f, r in rows if h["valid"] and not h["foul"]]
    bad = [r for r in ok if r[0] < -2.0]
    print(f"\n{len(rows)} starts: take-off invalid {sum(1 for h, f, r in rows if not h['valid'])}, foul {sum(1 for h, f, r in rows if h['valid'] and h['foul'])}, "
          f"landing roll-overs {len(bad)} of {len(ok)}; mean mark of legal {np.mean([r[0] for r in ok if r[0] > 0]):.3f}")
    # which features separate the roll-overs / weak take-offs
    for key in ("torso", "torso_rate", "pelvis", "com_z", "vx", "vz", "Ly", "gap", "swing_ahead", "swing_z"):
        xs = np.array([f[key] for h, f, r in rows if h["valid"]])
        ys = np.array([h["vz"] for h, f, r in rows if h["valid"]])
        ls = np.array([h["L"] for h, f, r in rows if h["valid"]])
        if len(xs) > 3 and xs.std() > 1e-9:
            print("corr %-12s vs take-off vz %+.2f, vs L %+.2f" % (key, np.corrcoef(xs, ys)[0, 1], np.corrcoef(xs, ls)[0, 1]))


if __name__ == "__main__":
    main()
