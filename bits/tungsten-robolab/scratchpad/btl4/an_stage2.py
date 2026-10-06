"""Stage-2 (right return) anatomy against the incoming apex, from rec_live traces (round 4).

    .venv/bin/python scratchpad/btl4/an_stage2.py out/btl4/live_base

Per start with a stage 2: the incoming ball's apex after the left return's bounce (stage 1's release), the apex quintile, the outcome category
(as m1_fail2.py), the release velocity of the right return, the bounce position and the arrival where the ball rises through z 0.62.
"""
import collections
import glob
import json
import sys

import numpy as np

sys.path.insert(0, "scratchpad/btl3")
import m1_analyze as A  # noqa: E402


def bounce_after(z, kr):
    ball, ballv = z["ball"], z["ballv"]
    for k in range(kr + 1, len(ball) - 1):
        if ball[k, 2] < 0.16 and ballv[k, 2] > 0 and ballv[k - 1, 2] <= 0:
            return k
    return None


def main():
    d = sys.argv[1]
    rows = []
    for fn in sorted(glob.glob(d + "/live_*.npz")):
        z = np.load(fn)
        seed = int(fn.split("_")[-1].split(".")[0])
        ws = A.stage_windows(z)
        if len(ws) < 3:
            continue
        pl = json.loads(str(z["pass_log"]))
        # stage 1 (left return) release -> incoming apex of stage 2
        side1, k01 = ws[1]
        r1 = A.extract(z, side1, k01)
        if r1 is None or "rel_v" not in r1:
            continue
        a1 = A.arrival(z, r1["kr"])
        if a1 is None:
            continue
        side, k0 = ws[2]
        rec = A.extract(z, side, k0)
        if rec is None or "rel_v" not in rec:
            continue
        e = pl[2] if len(pl) > 2 else {}
        ball, ballv = z["ball"], z["ballv"]
        kr = rec["kr"]
        kb1 = bounce_after(z, kr)
        nb = 0
        kb2 = None
        for k in range(kr + 1, len(ball) - 1):
            if ball[k, 2] < 0.16 and ballv[k, 2] > 0 and ballv[k - 1, 2] <= 0:
                nb += 1
                if nb == 2:
                    kb2 = k
                    break
        Fl = z["F_l"]
        kt = None
        for k in range(kr + 1, len(Fl)):
            if Fl[k] > 0.3:
                kt = k
                break
        a2 = A.arrival(z, kr)
        apex2 = float(ball[kb1:kb1 + 200, 2].max()) if kb1 else None
        if not e.get("gate"):
            cat = "no_gate"
        elif e.get("body"):
            cat = "body"
        elif kb1 is None:
            cat = "no_bounce"
        elif kt is None or (kb2 is not None and kt > kb2):
            cat = "no_receive"
        elif e.get("outcome") != "ok":
            cat = "wrong_hand"
        elif not e.get("ok"):
            cat = "lost_after"
        else:
            cat = "ok"
        rows.append({"seed": seed, "apex_in": a1[1], "pc": rec["pc"], "vin": z["ballv"][k0 - 1].copy(), "cat": cat, "rel_v": rec["rel_v"], "rel_p": rec["rel_p"],
                     "bounce": ball[kb1, :2] if kb1 else None, "arr": a2[0] if a2 else None, "apex_out": apex2, "touch_t": rec["touch"]["t"],
                     "ok": cat == "ok"})
    n = len(rows)
    print("stage 2 starts:", n, collections.Counter(r["cat"] for r in rows).most_common())
    ap = np.array([r["apex_in"] for r in rows])
    qs = np.quantile(ap, [0.2, 0.4, 0.6, 0.8])
    bins = np.digitize(ap, qs)
    print("apex quintile edges", np.round(qs, 3).tolist())
    cats = ["ok", "body", "no_receive", "no_gate", "wrong_hand", "lost_after", "no_bounce"]
    print(f"{'apex bin':>14s} {'n':>3s} " + " ".join(f"{c:>10s}" for c in cats))
    for b in range(5):
        sel = [r for r, bb in zip(rows, bins) if bb == b]
        lo = ap[bins == b].min()
        hi = ap[bins == b].max()
        cnt = collections.Counter(r["cat"] for r in sel)
        print(f"{lo:5.3f}-{hi:5.3f}  {len(sel):3d} " + " ".join(f"{cnt[c]:10d}" for c in cats))
    # release velocity and bounce position by category
    for c in ["ok", "body", "no_receive"]:
        sel = [r for r in rows if r["cat"] == c]
        if not sel:
            continue
        rv = np.array([r["rel_v"] for r in sel])
        rp = np.array([r["rel_p"] for r in sel])
        bn = np.array([r["bounce"] for r in sel if r["bounce"] is not None])
        ar = np.array([r["arr"] for r in sel if r["arr"] is not None])
        pc = np.array([r["pc"] for r in sel])
        print(f"{c:10s} n {len(sel):3d} rel_v {np.round(rv.mean(0), 2).tolist()} sd {np.round(rv.std(0), 2).tolist()}  rel_p {np.round(rp.mean(0), 3).tolist()}  bounce {np.round(bn.mean(0), 3).tolist()} sd {np.round(bn.std(0), 3).tolist()}"
              f"  arr {np.round(ar.mean(0), 3).tolist() if len(ar) else None} sd {np.round(ar.std(0), 3).tolist() if len(ar) else None}  incoming cross (x,y,t) {np.round(pc.mean(0), 3).tolist()} sd {np.round(pc.std(0), 3).tolist()}")
    # correlation of the incoming features with ok
    X = np.array([[r["apex_in"], r["pc"][0], r["pc"][1], r["pc"][2], r["vin"][0], r["vin"][1], r["vin"][2]] for r in rows])
    y = np.array([1.0 if r["ok"] else 0.0 for r in rows])
    names = ["apex_in", "cross_x", "cross_y", "cross_t", "vin_x", "vin_y", "vin_z"]
    for i, nme in enumerate(names):
        print(f"corr(ok, {nme}) = {np.corrcoef(X[:, i], y)[0, 1]:+.2f}   body-corr {np.corrcoef(X[:, i], np.array([1.0 if r['cat'] == 'body' else 0.0 for r in rows]))[0, 1]:+.2f}   no_receive-corr {np.corrcoef(X[:, i], np.array([1.0 if r['cat'] == 'no_receive' else 0.0 for r in rows]))[0, 1]:+.2f}")
    np.save("out/btl4/an_stage2_rows.npy", np.array(rows, dtype=object), allow_pickle=True)


if __name__ == "__main__":
    main()
