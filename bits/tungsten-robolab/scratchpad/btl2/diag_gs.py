"""Per-start diagnosis of a gain-scheduled stage program on the recorded starts (replay only, one process).

    .venv/bin/python scratchpad/btl2/diag_gs.py --seeds 801..880 --params P --ctl C --hand l --muscles left_arm --bounce-no 2 \
        --t-lo 1.70 --t-hi 2.40 --t-end 3.0 --require 1 --npz prog.npz --target=0.45,-0.25 --vt=1.5,-1.5 --cache scratchpad/btl2/runs/rec_s0v2

Prints for every start: the predicted arrival feature of the incoming ball, the replay's release state, the bounce point, apex, arrival
state at the other hand and what failed (touch / gate / body / apex / arrival), then a tally of the failure reasons.
"""
import argparse
import os
import pickle
import sys
from collections import Counter

import numpy as np

sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
sys.path.insert(0, "scratchpad/btl2")
import oracle_gs as G  # noqa: E402
import oracle_lib as O  # noqa: E402
import oracle_multi as M  # noqa: E402
import oracle_search as S  # noqa: E402
from common import load  # noqa: E402


def parse_seeds(s):
    out = []
    for part in s.split(","):
        if ".." in part:
            a, b = part.split("..")
            out += list(range(int(a), int(b) + 1))
        elif part:
            out.append(int(part))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", required=True)
    ap.add_argument("--params", required=True)
    ap.add_argument("--ctl", required=True)
    ap.add_argument("--npz", required=True)
    ap.add_argument("--hand", default="l")
    ap.add_argument("--muscles", default="left_arm")
    ap.add_argument("--bounce-no", type=int, default=2)
    ap.add_argument("--require", type=int, default=0)
    ap.add_argument("--t-lo", type=float, default=1.70)
    ap.add_argument("--t-hi", type=float, default=2.40)
    ap.add_argument("--t-end", type=float, default=3.0)
    ap.add_argument("--lead", type=int, default=32)
    ap.add_argument("--eval", type=float, default=0.80)
    ap.add_argument("--window", type=float, default=0.40)
    ap.add_argument("--pos-dz", type=float, default=0.03)
    ap.add_argument("--vel-dz", type=float, default=0.15)
    ap.add_argument("--target", default="")
    ap.add_argument("--vt", default="")
    ap.add_argument("--no-pre", action="store_true")
    ap.add_argument("--gmax", type=float, default=1.0)
    ap.add_argument("--cache", required=True)
    ap.add_argument("--nom", default="", help="feature nominal x,y (default: from the npz)")
    a = ap.parse_args()
    seeds = parse_seeds(a.seeds)
    cache = pickle.load(open(a.cache + ".pkl", "rb"))
    n = int(round(a.eval / 0.005))
    nprog = int(round(a.window / 0.005))
    recs, kstart = {}, {}
    for sd in seeds:
        key = (sd, a.params, a.ctl, a.t_lo, a.t_hi, a.t_end)
        if key not in cache:
            continue
        rec = cache[key]
        ks = M.trigger_tick(rec, O.Replay(rec), a.bounce_no, lead=a.lead * 0.005 + 0.005)
        if ks is None or ks not in rec["snaps"]:
            continue
        pl = rec["pass_log"]
        if a.require and not (len(pl) >= a.require and all(pl[i]["gate"] and pl[i]["body"] == 0 for i in range(a.require))):
            continue
        recs[sd] = rec
        kstart[sd] = ks
    z = np.load(a.npz)
    nom, sc = z["nom"], z["sc"]
    feat = {}
    zj = [int(v) for v in z["zj"]] if "zj" in z.files else []
    for sd in recs:
        feat[sd] = G.stage_features(O.Replay(recs[sd]), kstart[sd], a.hand, zj)
    seeds = [s for s in recs if feat[s] is not None]
    u = {s: np.clip((feat[s] - nom) / sc, -2.5, 2.5) for s in seeds}
    any_rec = recs[seeds[0]]
    idx = S.muscle_set(any_rec["names"], a.muscles)
    kt = z["kt"]
    cfg = {"idx": idx, "kt": kt, "nprog": nprog, "kstart": kstart, "n": n, "mode": "full", "who": a.hand, "gmax": a.gmax,
           "arr": {"pos_dz": a.pos_dz, "vel_dz": a.vel_dz, "target": [float(v) for v in a.target.split(",")] if a.target else None,
                   "vt": [float(v) for v in a.vt.split(",")] if a.vt else None, "pre": not a.no_pre},
           "u": u}
    G.init_worker(recs, cfg)
    tgt = S.RIGHT_TARGET if a.hand == "l" else S.LEFT_TARGET
    reasons = Counter()
    Js = []
    print("seed   J     u(x,y)        release (vx,vy,vz)  bounce      apex arrive(x,y)   va(vx,vy)    reason")
    for s in seeds:
        J, sm = G.eval_one((z["x"], s, np.zeros(len(u[s]))))
        Js.append(J)
        if not sm.get("touch"):
            why = "no touch"
        elif not sm.get("bounced"):
            why = "no bounce"
        else:
            bad = []
            if sm["gate"] == 0:
                bad.append("gate")
            if sm["body"] > 0:
                bad.append(f"body{sm['body']}")
            if sm["apex"] < 0.58:
                bad.append("apex")
            if float(np.hypot(*(np.array(sm["arrive"]) - tgt))) >= 0.14:
                bad.append("arrival")
            if sm["bgd"] > 0.10:
                bad.append("bgd")
            why = "+".join(bad) if bad else "ok"
        reasons[why] += 1
        if sm.get("bounced"):
            v = sm["v"]
            print(f"{s} {J:5.2f} ({u[s][0]:+.1f},{u[s][1]:+.1f}) ({v[0]:+.2f},{v[1]:+.2f},{v[2]:+.2f}) ({sm['bounce'][0]:+.2f},{sm['bounce'][1]:+.2f}) "
                  f"{sm['apex']:.2f} ({sm['arrive'][0]:+.2f},{sm['arrive'][1]:+.2f}) ({sm['va'][0]:+.2f},{sm['va'][1]:+.2f}) {why}")
        else:
            print(f"{s} {J:5.2f} ({u[s][0]:+.1f},{u[s][1]:+.1f}) {why}")
    print("J mean", round(float(np.mean(Js)), 3), "median", round(float(np.median(Js)), 3), dict(reasons))


if __name__ == "__main__":
    main()
