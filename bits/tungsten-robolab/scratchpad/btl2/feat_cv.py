"""Leave-one-out R^2 of a stage's outcome scatter on the ball feature u alone vs u + pre-stroke posture (joint proxies from the muscle
contractions the controller senses: c(pos) - c(neg) per joint), replay outcomes under a given program.

    OMP_NUM_THREADS=1 .venv/bin/python scratchpad/btl2/feat_cv.py (same options as feat_scan.py)
"""
import argparse
import pickle
import sys

import numpy as np

sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
sys.path.insert(0, "scratchpad/btl2")
import oracle_gs as G  # noqa: E402
import oracle_lib as O  # noqa: E402
import oracle_multi as M  # noqa: E402
import oracle_search as S  # noqa: E402
from diag_gs import parse_seeds  # noqa: E402

JOINTS = {"arm": ["shoulder_flex", "shoulder_abd", "shoulder_rot", "elbow", "wrist_flex", "wrist_dev", "finger_mcp", "finger_pip"],
          "spine": ["spine_flex", "spine_lat", "spine_rot", "pelvis_yaw"]}


def joint_proxy(names, c, side, j):
    if j.startswith("spine") or j.startswith("pelvis"):
        return c[names.index(j + "_pos")] - c[names.index(j + "_neg")]
    return c[names.index(f"{side}_{j}_pos")] - c[names.index(f"{side}_{j}_neg")]


def loo_r2(X, y, ridge):
    n = len(y)
    pred = np.zeros(n)
    for i in range(n):
        m = np.ones(n, bool)
        m[i] = False
        Xm, ym = X[m], y[m]
        mu, sd = Xm.mean(0), Xm.std(0) + 1e-9
        Z = (Xm - mu) / sd
        A = np.column_stack([np.ones(len(ym)), Z])
        R = ridge * np.eye(A.shape[1]); R[0, 0] = 0
        b = np.linalg.solve(A.T @ A + R, A.T @ ym)
        pred[i] = np.concatenate([[1.0], (X[i] - mu) / sd]) @ b
    return 1 - np.sum((y - pred) ** 2) / np.sum((y - y.mean()) ** 2)


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
    rows = []
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
        rp.load(ks)
        c, cd, f = rp.sim.contraction()
        names = rec["names"]
        side = a.hand
        oth = "r" if side == "l" else "l"
        arm = [joint_proxy(names, c, side, j) for j in JOINTS["arm"]]
        oarm = [joint_proxy(names, c, oth, j) for j in JOINTS["arm"]]
        sp = [joint_proxy(names, c, side, j) for j in JOINTS["spine"]]
        v = sm["v"]
        rows.append((u, [v[0], v[1], v[2], sm["arrive"][0], sm["arrive"][1]], arm, oarm, sp))
    U = np.array([r[0] for r in rows]); Y = np.array([r[1] for r in rows])
    ARM = np.array([r[2] for r in rows]); OARM = np.array([r[3] for r in rows]); SP = np.array([r[4] for r in rows])
    print("n", len(rows), "posture sd (arm):", np.round(ARM.std(0), 3).tolist(), "spine:", np.round(SP.std(0), 3).tolist())
    ynames = ["rel_vx", "rel_vy", "rel_vz", "arr_x", "arr_y"]
    sets = {"u": U, "u+arm": np.column_stack([U, ARM]), "u+spine": np.column_stack([U, SP]), "u+arm+spine": np.column_stack([U, ARM, SP]),
            "u+arm+oarm+spine": np.column_stack([U, ARM, OARM, SP])}
    # greedy forward selection of single arm joints (on top of u), summed leave-one-out R^2 over all outcomes
    chosen = []
    for step in range(4):
        best = None
        for j in range(ARM.shape[1]):
            if j in chosen:
                continue
            X = np.column_stack([U, ARM[:, chosen + [j]]])
            tot = sum(loo_r2(X, Y[:, yi], 5.0) for yi in range(Y.shape[1]))
            if best is None or tot > best[1]:
                best = (j, tot)
        chosen.append(best[0])
        X = np.column_stack([U, ARM[:, chosen]])
        per = [round(loo_r2(X, Y[:, yi], 5.0), 2) for yi in range(Y.shape[1])]
        print(f"greedy joints {[JOINTS['arm'][c] for c in chosen]}: sum LOO R2 {best[1]:.2f}; per outcome {dict(zip(['vx','vy','vz','arr_x','arr_y'], per))}")
    for yi, yn in enumerate(ynames):
        y = Y[:, yi]
        s = f"{yn:7s} sd {y.std():.3f}: "
        for k, X in sets.items():
            best = max(loo_r2(X, y, r) for r in (1.0, 5.0, 20.0))
            s += f"{k} {best:+.2f}  "
        print(s)


if __name__ == "__main__":
    main()
