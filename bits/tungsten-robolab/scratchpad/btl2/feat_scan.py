"""Which pre-stroke body-state variables explain a stage's outcome scatter (beyond the ball's predicted crossing u)?

    OMP_NUM_THREADS=1 .venv/bin/python scratchpad/btl2/feat_scan.py --npz prog.npz --params P --ctl C --hand l --muscles left_arm --bounce-no 2 \
        --t-lo 1.70 --t-hi 2.40 --t-end 3.0 --require 1 --target=0.45,-0.25 --vt=1.5,-1.5 --cache scratchpad/btl2/runs/rec_s0v4 [--seeds 801..900]

For every recorded start: the replay outcome under the program (release velocity, bounce, arrival), the state at the trigger snapshot
(every joint angle and rate, the palms' positions and velocities relative to the predicted crossing), then for each outcome the R^2 of a
linear fit on u alone and the joint variables that add the most (greedy forward selection, up to 4).
"""
import argparse
import pickle
import sys

import numpy as np

sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
sys.path.insert(0, "scratchpad/btl2")
import mujoco  # noqa: E402
import oracle_gs as G  # noqa: E402
import oracle_lib as O  # noqa: E402
import oracle_multi as M  # noqa: E402
import oracle_search as S  # noqa: E402
from diag_gs import parse_seeds  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", default="801..900")
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
    ap.add_argument("--target", default="")
    ap.add_argument("--vt", default="")
    ap.add_argument("--cache", required=True)
    ap.add_argument("--gmax", type=float, default=1.0)
    a = ap.parse_args()
    cache = pickle.load(open(a.cache + ".pkl", "rb"))
    z = np.load(a.npz)
    nom, sc = z["nom"], z["sc"]
    n, nprog = 160, 80
    rows, names = [], None
    recs, kst = {}, {}
    for sd in parse_seeds(a.seeds):
        key = (sd, a.params, a.ctl, a.t_lo, a.t_hi, a.t_end)
        if key not in cache:
            continue
        rec = cache[key]
        rp = O.Replay(rec)
        ks = M.trigger_tick(rec, rp, a.bounce_no, lead=32 * 0.005 + 0.005)
        if ks is None or ks not in rec["snaps"]:
            continue
        pl = rec["pass_log"]
        if a.require and not (len(pl) >= a.require and all(pl[i]["gate"] and pl[i]["body"] == 0 for i in range(a.require))):
            continue
        pc = rp.pred_cross(ks)
        if pc is None:
            continue
        u = np.clip((np.array(pc[:2]) - nom) / sc, -2.5, 2.5)
        idx = S.muscle_set(rec["names"], a.muscles)
        S.ARR.update({"pos_dz": 0.03, "vel_dz": 0.15, "target": [float(v) for v in a.target.split(",")] if a.target else None,
                      "vt": [float(v) for v in a.vt.split(",")] if a.vt else None, "pre": True})
        cfg = {"idx": idx, "kt": z["kt"], "nprog": nprog, "gmax": a.gmax}
        base = rec["acts"][ks:ks + n + 1]
        ov = G.program_gs(z["x"], cfg, base, n, u)
        pcx = 0 if a.hand == "l" else 1

        def stop(i, pos, vel, cf):
            if i < 20 or vel[i, 2] <= 0 or pos[i, 2] < 0.60:
                return False
            return bool(np.any(cf[:i + 1, pcx] > 0.3)) and bool(np.any(cf[:i + 1, 2] > 0.2))
        out = rp.run(ov, ticks=n, start=ks, stop=stop, hand_col=pcx)
        J, sm = S.evaluate(out, "full", a.hand)
        if not sm.get("bounced") or "arrive" not in sm:
            continue
        # the state at the snapshot
        rp.load(ks)
        m, d = rp.m, rp.d
        feats, fn = [], []
        for j in range(m.njnt):
            if m.jnt_type[j] == mujoco.mjtJoint.mjJNT_FREE:
                continue
            nm = m.joint(j).name
            adr, dof = m.jnt_qposadr[j], m.jnt_dofadr[j]
            feats += [d.qpos[adr], d.qvel[dof]]
            fn += [nm, nm + "'"]
        for si, sd_ in enumerate("lr"):
            p = d.site_xpos[rp.palm_ids[si]]
            feats += [p[0] - pc[0], p[1] - pc[1], p[2] - 0.62]
            fn += [f"{sd_}palm_dx", f"{sd_}palm_dy", f"{sd_}palm_dz"]
        names = fn
        v = sm["v"]
        rows.append((sd, u, [v[0], v[1], v[2], sm["arrive"][0], sm["arrive"][1], sm["bounce"][0], sm["bounce"][1]], np.array(feats), J))
    U = np.array([r[1] for r in rows])
    Y = np.array([r[2] for r in rows])
    F = np.array([r[3] for r in rows])
    ynames = ["rel_vx", "rel_vy", "rel_vz", "arr_x", "arr_y", "bnc_x", "bnc_y"]
    print("n", len(rows), "J mean", round(float(np.mean([r[4] for r in rows])), 3))
    keep = [i for i in range(F.shape[1]) if F[:, i].std() > 1e-6]
    Fz = (F[:, keep] - F[:, keep].mean(0)) / F[:, keep].std(0)
    for yi, yn in enumerate(ynames):
        y = Y[:, yi]
        X = np.column_stack([np.ones(len(y)), U])
        beta = np.linalg.lstsq(X, y, rcond=None)[0]
        r2 = 1 - np.sum((y - X @ beta) ** 2) / np.sum((y - y.mean()) ** 2)
        chosen = []
        cur = X
        cur_r2 = r2
        for _ in range(4):
            best = None
            for c in range(Fz.shape[1]):
                if c in chosen:
                    continue
                Xc = np.column_stack([cur, Fz[:, c]])
                b = np.linalg.lstsq(Xc, y, rcond=None)[0]
                rr = 1 - np.sum((y - Xc @ b) ** 2) / np.sum((y - y.mean()) ** 2)
                if best is None or rr > best[1]:
                    best = (c, rr)
            chosen.append(best[0])
            cur = np.column_stack([cur, Fz[:, best[0]]])
            cur_r2 = best[1]
        print(f"{yn}: sd {y.std():.3f}, R2 on u {r2:.2f}; + " + ", ".join(f"{names[keep[c]]}" for c in chosen) + f" -> R2 {cur_r2:.2f}")


if __name__ == "__main__":
    main()
