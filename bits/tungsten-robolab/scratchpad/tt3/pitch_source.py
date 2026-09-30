"""How much of the pad pitch / yaw scatter at contact is the arm's joint posture and how much the paddle in the hand? (agent T3)
Per side, over the hits of sets A and B (baseline champion, pass-1 logs): regress the pad normal's pitch (and yaw) at the contact row on the 8 logged servo joint angles + trunk flexion, lateral bending
(X columns 0..9) and the pelvis position; R^2 and 5-fold CV R^2 = the share explained by body posture; the residual = the paddle's motion in the fingers + everything else."""
import json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(HERE, "playground"))
import tt_impact as ti
Xs, Ps, Ys, S = [], [], [], []
for s in "AB":
    for l in open(f"out/tt3/o0_{s}.jsonl"):
        r = json.loads(l)
        if not r.get("hit") or r.get("side") not in (1, 2): continue
        z = np.load(f"out/tt3/logs_o0/{r['seed']}.npz"); k = int(z["contact"])
        if k < 3: continue
        n = z["L"][k - 1, 13:16]; n = n * np.sign(n[0]); n = n / np.linalg.norm(n)
        p, y = ti.angles_from_normal(n[None, :])
        Xs.append(np.r_[z["X"][k - 1, 0:10], z["X"][k - 1, 10:12]]); Ps.append(np.degrees(p[0])); Ys.append(np.degrees(y[0])); S.append(r["side"])
X, P, Y, S = np.array(Xs), np.array(Ps), np.array(Ys), np.array(S)
def cv_r2(A, y, lam=1e-3, folds=5):
    n = len(y); idx = np.arange(n) % folds; pred = np.zeros(n)
    for f in range(folds):
        tr, te = idx != f, idx == f
        mu, sd = A[tr].mean(0), A[tr].std(0) + 1e-9
        Z = (A[tr] - mu) / sd; w = np.linalg.solve(Z.T @ Z + lam * len(Z) * np.eye(Z.shape[1]), Z.T @ (y[tr] - y[tr].mean()))
        pred[te] = ((A[te] - mu) / sd) @ w + y[tr].mean()
    return 1 - ((y - pred) ** 2).sum() / ((y - y.mean()) ** 2).sum(), np.std(y - pred)
for side, nm in ((1, "forehand"), (2, "backhand")):
    m = S == side
    for lab, y in (("pitch", P), ("yaw", Y)):
        r2, res = cv_r2(X[m], y[m])
        print(f"{nm} (n {m.sum()}): pad {lab} sd {y[m].std():.2f} deg; explained by the body's joint angles (5-fold CV R2) {r2:.2f}; residual sd {res:.2f} deg (paddle in the hand + unlogged)")
