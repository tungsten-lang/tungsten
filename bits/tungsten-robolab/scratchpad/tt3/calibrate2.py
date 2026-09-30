"""Linear-response model of the champion's arm, for the ideal-arm oracle O2 (agent T3).

From the record-only run of set A (out/tt3/rec_A.jsonl, out/tt3/orc_rec/<seed>.npz: per control tick the commanded posture q_fit reconstructed from the emitted muscle targets and the reached
posture q), per side and per tick index i (t = 0.01 i): the mean reached posture qbar_s[i] and the mean commanded posture fbar_s[i] over the serves of that side; and one 7 x 7 matrix G_s,
ridge regression of the reached deviation (q - qbar) on the commanded deviation (q_fit - fbar), pooled over ticks 0.05 s .. contact. The oracle arm then follows
q_ref = qbar_s[i] + G_s (q_fit - fbar_s[i]): the champion's MEAN response plus its linear response to what this serve asks, with the scatter that the command does not explain removed.
Prints the explained fraction of the reached posture's variance at contact per joint (in-sample and 2-fold cross-validated).
"""
import json, os, sys
import numpy as np
np.set_printoptions(precision=3, suppress=True, linewidth=220)
JN = ["elv_angle", "shoulder_elv", "shoulder_rot", "elbow_flexion", "pro_sup", "deviation", "flexion"]
tag = "rec"
rows = [json.loads(l) for l in open(f"out/tt3/{tag}_A.jsonl") if l.strip()]
NT = 130
data = {1: [], 2: []}
for r in rows:
    f = f"out/tt3/orc_{tag}/{r['seed']}.npz"
    if not os.path.exists(f) or r.get("side") not in (1, 2):
        continue
    z = np.load(f)
    q, qf = z["q"], z["qfit"]
    tc = r.get("t_contact") or 0.5
    data[r["side"]].append((q, qf, tc, r["seed"]))
out = {}
lam = float(sys.argv[1]) if len(sys.argv) > 1 else 0.05
DIAG = (sys.argv[2] == "diag") if len(sys.argv) > 2 else True
def build(sub):
    qbar = np.zeros((NT, 7)); fbar = np.zeros((NT, 7)); cnt = np.zeros(NT)
    for q, qf, tc, sd in sub:
        n = min(len(q), NT)
        qbar[:n] += q[:n]; fbar[:n] += qf[:n]; cnt[:n] += 1
    for i in range(NT):
        if cnt[i] == 0:
            qbar[i], fbar[i] = qbar[i - 1], fbar[i - 1]
        else:
            qbar[i] /= cnt[i]; fbar[i] /= cnt[i]
    X, Y = [], []
    for q, qf, tc, sd in sub:
        n = min(len(q), NT, int(tc / 0.01) + 1)
        i0 = 5
        X.append(qf[i0:n] - fbar[i0:n]); Y.append(q[i0:n] - qbar[i0:n])
    X, Y = np.vstack(X), np.vstack(Y)
    A = X.T @ X
    G = np.linalg.solve(A + lam * np.trace(A) / 7 * np.eye(7), X.T @ Y).T   # q_dev = G f_dev
    if DIAG:
        g = np.clip((X * Y).sum(0) / np.maximum((X * X).sum(0), 1e-12), 0.0, 1.2)
        G = np.diag(g)
    return qbar, fbar, G, X, Y, cnt
for side, nm in ((1, "fh"), (2, "bh")):
    sub = data[side]
    qbar, fbar, G, X, Y, cnt = build(sub)
    out[f"qbar{side}"], out[f"fbar{side}"], out[f"G{side}"], out[f"n{side}"] = qbar, fbar, G, cnt
    # explained variance of the reached deviation at the contact tick, in sample and 2-fold
    def r2(subA, subB):
        qb, fb, Gm, _, _, _ = build(subA)
        num = np.zeros(7); den = np.zeros(7)
        for q, qf, tc, sd in subB:
            i = min(int(tc / 0.01), len(q) - 1, NT - 1)
            dev = q[i] - qb[i]; pred = Gm @ (qf[i] - fb[i])
            num += (dev - pred) ** 2; den += dev ** 2
        return 1 - num / np.maximum(den, 1e-12)
    ins = r2(sub, sub); half = len(sub) // 2
    cv = 0.5 * (r2(sub[:half], sub[half:]) + r2(sub[half:], sub[:half]))
    print(f"== {nm} (n {len(sub)}): G (rows = reached joint, cols = asked joint)\n{G}\n   R2 of the reached deviation at contact, in-sample {ins}  2-fold CV {cv}")
    devsd = np.std([q[min(int(tc / 0.01), len(q) - 1)] - qbar[min(int(tc / 0.01), len(q) - 1)] for q, qf, tc, sd in sub], axis=0)
    print("   sd of the reached posture across serves at contact (rad):", devsd)
name = "scratchpad/tt3/results/o2_cal_A_diag.npz" if DIAG else "scratchpad/tt3/results/o2_cal_A.npz"
np.savez(name, **out)
print("saved", name)
