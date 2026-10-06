"""A value function of the state delivered to a stage: P(the stage's pass is ok | ball state at its trigger), logistic regression on the training records."""
import pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl4"); sys.path.insert(0, "scratchpad/btl2")
import rlib, fit_v
import oracle_lib as O, oracle_multi as M

FEATS = ["x", "y", "vzc", "vx", "vy", "vz", "t"]

def trigger_features(rp, rec, ks):
    pc = fit_v.pred_cross_full(rp, ks)
    if pc is None:
        return None
    bv = rec["ballv"][ks - 1]
    return np.array([pc[0], pc[1], pc[3], bv[0], bv[1], bv[2], pc[2]])

def fit_logistic(X, y, lam=1.0, iters=50):
    mu, sd = X.mean(0), X.std(0) + 1e-9
    Z = np.column_stack([np.ones(len(X)), (X - mu) / sd])
    w = np.zeros(Z.shape[1])
    for _ in range(iters):
        p = 1 / (1 + np.exp(-Z @ w))
        g = Z.T @ (p - y) + lam * np.r_[0, w[1:]]
        Hm = Z.T @ (Z * (p * (1 - p))[:, None]) + lam * np.diag(np.r_[0, np.ones(len(w) - 1)])
        w = w - np.linalg.solve(Hm, g)
    return mu, sd, w

def predict(mu, sd, w, X):
    Z = np.column_stack([np.ones(len(X)), (np.atleast_2d(X) - mu) / sd])
    return 1 / (1 + np.exp(-Z @ w))

def auc(p, y):
    o = np.argsort(p); r = np.empty(len(p)); r[o] = np.arange(len(p))
    n1 = y.sum(); n0 = len(y) - n1
    return (r[y == 1].sum() - n1 * (n1 - 1) / 2) / (n1 * n0)

if __name__ == "__main__":
    stage = int(sys.argv[1])
    rp = None
    X, Y = [], []
    for sd in range(13001, 13841):
        rec = pickle.load(open(f"out/btl4/rec/rec_{sd}.pkl", "rb"))
        if rp is None:
            rp = O.Replay(rec)
        rp.rec = rec; rp.act_ids = rec["act_ids"]
        hand, bn = rlib.STAGES[stage]
        ks = M.trigger_tick(rec, rp, bn, lead=rlib.LEAD)
        if ks is None or ks not in rec["snaps"]:
            continue
        f = trigger_features(rp, rec, ks)
        if f is None:
            continue
        pl = rec["pass_log"]
        X.append(f); Y.append(1.0 if (stage < len(pl) and pl[stage]["ok"]) else 0.0)
    X = np.array(X); Y = np.array(Y)
    n = len(Y); tr = np.arange(n) % 3 != 0; te = ~tr
    for cols in ([2], [0, 1, 2], [0, 1, 2, 3, 4, 5], list(range(7))):
        mu, sd_, w = fit_logistic(X[tr][:, cols], Y[tr], lam=3.0)
        p = predict(mu, sd_, w, X[te][:, cols])
        print(f"stage {stage} features {[FEATS[c] for c in cols]}: held-out AUC {auc(p, Y[te]):.3f}  (n {n}, ok {Y.mean():.2f}); coefs {np.round(w, 2).tolist()}")
    mu, sd_, w = fit_logistic(X, Y, lam=3.0)
    np.savez(f"scratchpad/btl4/runs/valfn_stage{stage}.npz", mu=mu, sd=sd_, w=w)
