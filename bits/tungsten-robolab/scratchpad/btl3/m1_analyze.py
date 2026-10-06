"""M1b: how much of a programmed stage's outcome scatter is determined by the LIVE state some tens of ms into the stroke?

    .venv/bin/python scratchpad/btl3/m1_analyze.py out/btl3/live_champ [stages]

Reads the closed-loop traces of rec_live.py (champion in the loop). For every programmed stage (0 right launch pass, 1 left return,
2 right return; the stage starts at the first tick the track's label is g_run) it builds:

  outcomes   release velocity of the pass (the ball's velocity when the stroking hand lets go), the arrival (x, y) where the ball
             rises through z 0.62 after its bounce, the apex of that rise
  features   t0: the ball's predicted rising crossing of z 0.62 (x, y, time) at the trigger (what the gain schedule saw)
             z0: the stroking arm's posture at the trigger (8 joint angles, 8 rates; the joint proxy c(pos) - c(neg) too)
             live(+k): the same arm state plus the palm minus the predicted contact point and the palm velocity, k ticks after the trigger

and prints the leave-one-out R^2 (ridge, the best of a few penalties) of every outcome on growing feature sets.  An R^2 that rises
with k says the outcome scatter is already determined by what the controller could see at that time: the part a correction
at that time could remove, if the arm can move the palm that much in the time left.
"""
import json
import sys

import numpy as np

H = 0.62
G = 9.81
LAMS = (0.3, 1.0, 3.0, 10.0, 30.0, 100.0)


def parse_states(lab):
    r, l = [], []
    for s in lab:
        p = str(s).split("|")
        r.append(p[2].split(":")[1])
        l.append(p[3].split(":")[1])
    return np.array(r), np.array(l)


def predicted_cross(bp, bv):
    vz = bv[2]
    if vz <= 0.5:
        return None
    disc = vz * vz - 2 * G * (H - bp[2])
    s = vz / G if disc <= 0 else (vz - np.sqrt(disc)) / G
    return np.array([bp[0] + bv[0] * s, bp[1] + bv[1] * s, s])


def stage_windows(z):
    r, l = parse_states(z["label"])
    on_r = [k for k in range(1, len(r)) if r[k] == "g_run" and r[k - 1] != "g_run"]
    on_l = [k for k in range(1, len(l)) if l[k] == "g_run" and l[k - 1] != "g_run"]
    out = []
    if not on_r:
        return out
    out.append(("r", on_r[0]))
    nl = [k for k in on_l if k > on_r[0]]
    if nl:
        out.append(("l", nl[0]))
        nr = [k for k in on_r if k > nl[0]]
        if nr:
            out.append(("r", nr[0]))
    return out


def touch_release(F, k0, thr=0.3):
    n = len(F)
    kt = None
    for k in range(k0, min(n, k0 + 120)):
        if F[k] > thr:
            kt = k
            break
    if kt is None:
        return None, None
    kr = None
    for k in range(kt, n - 5):
        if np.all(F[k:k + 6] <= thr):
            kr = k
            break
    return kt, kr


def extract(z, side, k0):
    """The stage's features and outcomes for the stage starting at tick k0 (the controller's first g_run tick)."""
    ball, ballv = z["ball"], z["ballv"]
    obs = k0 - 1                      # the sensors at tick k0 read the state after tick k0 - 1
    pc = predicted_cross(ball[obs], ballv[obs])
    if pc is None:
        return None
    F = z["F_" + side]
    kt, kr = touch_release(F, k0)
    rec = {"k0": k0, "pc": pc, "kt": kt, "kr": kr}
    q, qd = z["q_" + side], z["qd_" + side]
    c, cd = z["c_" + side], z["cd_" + side]
    palm, pv = z["palm_" + side], z["pv_" + side]
    target = np.array([pc[0], pc[1], H])
    rec["live"] = {}
    for k in (0, 3, 6, 9, 12, 15, 18, 24, 30):
        i = obs + k
        if i >= len(q):
            break
        proxy = c[i, 0::2] - c[i, 1::2]
        proxyd = cd[i, 0::2] - cd[i, 1::2]
        rec["live"][k] = {"q": q[i].copy(), "qd": qd[i].copy(), "proxy": proxy, "proxyd": proxyd,
                          "palm": palm[i] - target, "pv": pv[i].copy(),
                          "ball": ball[i] - target, "bv": ballv[i].copy()}
    if kt is not None and kr is not None:
        rec["touch"] = {"palm": palm[kt] - ball[kt], "pv": pv[kt].copy(), "t": (kt - k0) * 0.005, "dur": (kr - kt) * 0.005,
                        "ball": ball[kt].copy(), "bv": ballv[kt].copy()}
        rec["rel_v"] = ballv[min(kr + 1, len(ballv) - 1)].copy()
        rec["rel_p"] = ball[min(kr + 1, len(ball) - 1)].copy()
    return rec


def arrival(z, k_from):
    """The ball's (x, y) and the apex of its rise after the first bounce following tick k_from, where it rises through H."""
    ball, ballv = z["ball"], z["ballv"]
    n = len(ball)
    kb = None
    for k in range(k_from + 1, n - 1):
        if ball[k, 2] < 0.16 and ballv[k, 2] > 0 and ballv[k - 1, 2] <= 0:
            kb = k
            break
    if kb is None:
        return None
    for k in range(kb, min(n, kb + 200)):
        if ball[k, 2] >= H and ballv[k, 2] > 0:
            apex = float(np.max(ball[kb:min(n, kb + 200), 2]))
            return np.array([ball[k, 0], ball[k, 1]]), apex, kb
    return None


def loo_r2(X, y, lams=LAMS):
    n = len(y)
    best = -9.0
    mu, sd = X.mean(0), X.std(0) + 1e-9
    Z = (X - mu) / sd
    A = np.column_stack([np.ones(n), Z])
    for lam in lams:
        R = lam * np.eye(A.shape[1])
        R[0, 0] = 0
        # leave-one-out residuals of ridge in closed form: e_i / (1 - h_ii)
        M = np.linalg.solve(A.T @ A + R, A.T)
        Hm = A @ M
        e = y - Hm @ y
        loo = e / (1 - np.diag(Hm))
        r2 = 1 - np.sum(loo ** 2) / np.sum((y - y.mean()) ** 2)
        best = max(best, r2)
    return best


def feats(rec, k, kind):
    L = rec["live"][k]
    if kind == "t0":
        return np.array([rec["pc"][0], rec["pc"][1], rec["pc"][2]])
    if kind == "arm":
        return np.concatenate([L["q"], L["qd"]])
    if kind == "proxy":
        return np.concatenate([L["proxy"], L["proxyd"]])
    if kind == "palm":
        return np.concatenate([L["palm"], L["pv"]])
    raise ValueError(kind)


def main():
    import glob
    d = sys.argv[1]
    files = sorted(glob.glob(d + "/live_*.npz"))
    rows = {0: [], 1: [], 2: []}
    for fn in files:
        z = np.load(fn)
        pl = json.loads(str(z["pass_log"]))
        for si, (side, k0) in enumerate(stage_windows(z)):
            rec = extract(z, side, k0)
            if rec is None or "rel_v" not in rec:
                continue
            a = arrival(z, rec["kr"])
            rec["arr"] = a[0] if a else None
            rec["apex"] = a[1] if a else None
            rec["ok"] = bool(pl[si]["ok"]) if si < len(pl) else False
            rec["seed"] = int(fn.split("_")[-1].split(".")[0])
            rows[si].append(rec)
    for si in (0, 1, 2):
        R = rows[si]
        print(f"\n=== stage {si} ({'right launch pass' if si == 0 else 'left return' if si == 1 else 'right return'}): {len(R)} starts with a touch and a release")
        if len(R) < 20:
            continue
        RV = np.array([r["rel_v"] for r in R])
        touch_t = np.array([r["touch"]["t"] for r in R])
        dur = np.array([r["touch"]["dur"] for r in R])
        print(f"touch {touch_t.mean() * 1000:.0f} +- {touch_t.std() * 1000:.0f} ms after the trigger, contact {dur.mean() * 1000:.0f} +- {dur.std() * 1000:.0f} ms;"
              f" release v mean {np.round(RV.mean(0), 2).tolist()} sd {np.round(RV.std(0), 2).tolist()}")
        have_arr = [i for i, r in enumerate(R) if r["arr"] is not None]
        ARR = np.array([R[i]["arr"] for i in have_arr])
        print(f"arrival (n {len(have_arr)}) mean {np.round(ARR.mean(0), 3).tolist()} sd {np.round(ARR.std(0), 3).tolist()}; ok {sum(r['ok'] for r in R)}/{len(R)}")
        outs = {"vx": (RV[:, 0], list(range(len(R)))), "vy": (RV[:, 1], list(range(len(R)))), "vz": (RV[:, 2], list(range(len(R)))),
                "arr_x": (ARR[:, 0], have_arr), "arr_y": (ARR[:, 1], have_arr)}
        # touch geometry as an outcome predictor (what the contact determines)
        TG = np.array([np.concatenate([r["touch"]["palm"], r["touch"]["pv"]]) for r in R])
        print("release velocity from the touch geometry (palm - ball offset, palm velocity at the first touch; LOO R^2):",
              {n: round(loo_r2(TG[idx], y[idx] if False else y), 2) for n, (y, idx) in list(outs.items())[:3]})
        print(f"{'set':34s}" + "".join(f"{n:>8s}" for n in outs))
        sets = [("t0 (ball crossing)", [("t0", 0)]),
                ("t0 + arm@0 (q,qd)", [("t0", 0), ("arm", 0)]),
                ("t0 + proxy@0", [("t0", 0), ("proxy", 0)])]
        for k in (6, 12, 18, 24):
            sets.append((f"t0 + arm@0 + arm@+{k * 5}ms", [("t0", 0), ("arm", 0), ("arm", k)]))
            sets.append((f"t0 + arm@0 + arm,palm@+{k * 5}ms", [("t0", 0), ("arm", 0), ("arm", k), ("palm", k)]))
            sets.append((f"t0 + proxy@0 + proxy,palm@+{k * 5}ms", [("t0", 0), ("proxy", 0), ("proxy", k), ("palm", k)]))
        for name, spec in sets:
            line = f"{name:34s}"
            for on, (y, idx) in outs.items():
                X = np.array([np.concatenate([feats(R[i], k, kind) for kind, k in spec]) for i in idx])
                line += f"{loo_r2(X, y):8.2f}"
            print(line)


if __name__ == "__main__":
    main()
