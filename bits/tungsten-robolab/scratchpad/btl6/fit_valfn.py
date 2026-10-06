"""Value function of the stage-4 delivery (the A4 left reflex takes the ball: pass 5 ok) from recorded G starts replayed by the chain (val_verdicts.py pickle).
    scratchpad/btl6/py scratchpad/btl6/fit_valfn.py val_verdicts.pkl out.npz [ridge]"""
import pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl6")
import chainobj as Ob
res = pickle.load(open(sys.argv[1], "rb"))
ridge = float(sys.argv[3]) if len(sys.argv) > 3 else 3.0
X, y, seeds = [], [], []
for sd, r in sorted(res.items()):
    sm = r["sm4"]; fl = r["fl"].get(4)
    if sm is None or fl is None or not (fl["touch"] and fl["bounced"] and fl["gate"] and fl["bfl"] == 0) or len(r["ok"]) < 5 or not all(r["ok"][:4]) or "arrive" not in sm:
        continue
    X.append(Ob.feats_v(float(sm["apex"]), float(sm["arrive"][0]), float(sm["arrive"][1]), float(np.hypot(*sm["va"][:2]))))
    y.append(1.0 if r["ok"][4] else 0.0); seeds.append(sd)
X, y = np.array(X), np.array(y)
n = len(y); print("clean stage-4 strokes with passes 1-4 ok:", n, "positives", int(y.sum()))
idx = np.arange(n); rng = np.random.default_rng(0); rng.shuffle(idx)
tr, te = idx[: int(0.7 * n)], idx[int(0.7 * n):]
w, mu, sd_ = Ob.fit_logistic(X[tr], y[tr], ridge)
p = 1 / (1 + np.exp(-(np.hstack([np.ones((len(te), 1)), (X[te] - mu) / sd_]) @ w)))
pos, neg = p[y[te] == 1], p[y[te] == 0]
auc = float(np.mean([(a > b) + 0.5 * (a == b) for a in pos for b in neg])) if len(pos) and len(neg) else float("nan")
print(f"held-out AUC {auc:.3f} (n {len(te)}, positives {int(y[te].sum())})")
w, mu, sd_ = Ob.fit_logistic(X, y, ridge)
np.savez(sys.argv[2], w=w, mu=mu, sd=sd_)
print("weights", np.round(w, 2).tolist())
print("mean predicted p", float(np.mean(1 / (1 + np.exp(-(np.hstack([np.ones((n, 1)), (X - mu) / sd_]) @ w))))), "base rate", y.mean())
print("apex of clean strokes: mean", X[:, 0].mean().round(3), "positives", X[y == 1, 0].mean().round(3), "negatives", X[y == 0, 0].mean().round(3))
